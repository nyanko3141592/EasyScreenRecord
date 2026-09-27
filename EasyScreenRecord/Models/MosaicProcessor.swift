import Foundation
import AVFoundation
import CoreImage
import ScreenCaptureKit
import os

/// Everything needed to render one output frame.
/// Rects are display-local points with a top-left origin.
struct CompositorState: Sendable {
    var sourceRect: CGRect
    var mosaicRects: [CGRect] = []
    var mosaicBlockSize: CGFloat = 16
    var mosaicStyle: MosaicStyle = .pixelate
}

// MARK: - Mosaic Renderer (pure Core Image, no state)

nonisolated enum MosaicRenderer {
    /// Convert a display-local top-left point rect into Core Image pixel space (bottom-left origin).
    static func pixelRect(_ rect: CGRect, pointScale: CGFloat, imageHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX * pointScale,
            y: imageHeight - rect.maxY * pointScale,
            width: rect.width * pointScale,
            height: rect.height * pointScale
        )
    }

    /// Mask `rects` (Core Image pixel space) of `image`.
    /// The mosaic is applied on the full captured frame, before any zoom crop,
    /// so masked content can never leak regardless of the zoom position.
    static func applyMosaic(to image: CIImage, rects: [CGRect], blockPixels: CGFloat, style: MosaicStyle) -> CIImage {
        let extent = image.extent
        let targets = rects.map { $0.integral.intersection(extent) }.filter { !$0.isNull && !$0.isEmpty }
        guard !targets.isEmpty else { return image }

        let block = max(2, blockPixels)
        let clamped = image.clampedToExtent()
        let effect: CIImage
        switch style {
        case .pixelate:
            // Blur first so each block becomes the average of its area (a true mosaic),
            // rather than CIPixellate's single sample per block.
            effect = clamped
                .applyingGaussianBlur(sigma: Double(block) * 0.5)
                .applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: block,
                    kCIInputCenterKey: CIVector(x: 0, y: 0)
                ])
        case .blur:
            effect = clamped.applyingGaussianBlur(sigma: Double(block) * 1.5)
        case .fill:
            effect = CIImage(color: CIColor(red: 0.08, green: 0.08, blue: 0.08))
        }

        var result = image
        for rect in targets {
            result = effect.cropped(to: rect).composited(over: result)
        }
        return result.cropped(to: extent)
    }

    /// Full frame pipeline: mosaic → crop `state.sourceRect` → aspect-fit into `outputSize`.
    static func composite(frame: CIImage, displaySize: CGSize, state: CompositorState, outputSize: CGSize) -> CIImage {
        let extent = frame.extent
        let pointScale = extent.width / max(displaySize.width, 1)

        let mosaicRects = state.mosaicRects.map {
            pixelRect($0, pointScale: pointScale, imageHeight: extent.height)
        }
        let masked = applyMosaic(
            to: frame,
            rects: mosaicRects,
            blockPixels: state.mosaicBlockSize * pointScale,
            style: state.mosaicStyle
        )

        let outputRect = CGRect(origin: .zero, size: outputSize)
        let background = CIImage(color: .black).cropped(to: outputRect)

        var crop = pixelRect(state.sourceRect, pointScale: pointScale, imageHeight: extent.height).intersection(extent)
        if crop.isNull || crop.width < 1 || crop.height < 1 { crop = extent }

        let k = min(outputSize.width / crop.width, outputSize.height / crop.height)
        let dx = (outputSize.width - crop.width * k) / 2
        let dy = (outputSize.height - crop.height * k) / 2
        let transform = CGAffineTransform(translationX: -crop.minX, y: -crop.minY)
            .concatenating(CGAffineTransform(scaleX: k, y: k))
            .concatenating(CGAffineTransform(translationX: dx, y: dy))

        return masked
            .cropped(to: crop)
            .transformed(by: transform)
            .composited(over: background)
            .cropped(to: outputRect)
    }
}

// MARK: - Frame Compositor

/// Receives frames from ScreenCaptureKit, applies mosaic + zoom crop, and writes
/// a constant-frame-rate video. Frames are emitted on a fixed timer (re-using the latest
/// captured frame) so zoom animations stay smooth even when the screen content is static.
nonisolated final class FrameCompositor: NSObject, SCStreamOutput, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "EasyScreenRecord.compositor", qos: .userInitiated)

    let outputURL: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let outputSize: CGSize
    private let displaySize: CGSize
    private let frameRate: Int
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let state: OSAllocatedUnfairLock<CompositorState>

    // Confined to sampleQueue
    private var latestFrame: CVPixelBuffer?
    private var timer: DispatchSourceTimer?
    private var sessionStarted = false
    private var finished = false
    private var framesWritten = 0

    /// - Parameters:
    ///   - displaySize: captured display size in points
    ///   - outputSize: video size in pixels
    init(outputURL: URL, displaySize: CGSize, outputSize: CGSize, frameRate: Int, quality: CGFloat, initialState: CompositorState) throws {
        self.outputURL = outputURL
        self.displaySize = displaySize
        self.frameRate = max(1, frameRate)
        self.state = OSAllocatedUnfairLock(initialState: initialState)

        let width = (Int(outputSize.width) >> 1) << 1
        let height = (Int(outputSize.height) >> 1) << 1
        self.outputSize = CGSize(width: width, height: height)

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // Bitrate based on quality (2x to 6x pixels per second-ish, same formula as before)
        let bitrate = Int(Double(width * height) * (2.0 + Double(quality) * 4.0))
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: self.frameRate,
                AVVideoMaxKeyFrameIntervalKey: self.frameRate
            ]
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "FrameCompositor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "FrameCompositor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Start writing failed"])
        }
        super.init()
    }

    /// Update zoom / mosaic parameters. Safe to call from any thread.
    func update(_ newState: CompositorState) {
        state.withLock { $0 = newState }
    }

    func start() {
        sampleQueue.async { [self] in
            let t = DispatchSource.makeTimerSource(queue: sampleQueue)
            t.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / frameRate), leeway: .milliseconds(1))
            t.setEventHandler { [weak self] in self?.writeFrame() }
            timer = t
            t.resume()
        }
    }

    /// Stop writing and finalize the file. Returns the URL if at least one frame was written.
    func finish() async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            sampleQueue.async { [self] in
                finished = true
                timer?.cancel()
                timer = nil
                latestFrame = nil

                guard sessionStarted, writer.status == .writing else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(returning: nil)
                    return
                }
                input.markAsFinished()
                writer.finishWriting { [self] in
                    if writer.status == .completed {
                        print("[Compositor] Wrote \(framesWritten) frames to \(outputURL.path)")
                        continuation.resume(returning: outputURL)
                    } else {
                        print("[Compositor] Finish failed: \(String(describing: writer.error))")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    // MARK: SCStreamOutput (called on sampleQueue)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !finished, sampleBuffer.isValid else { return }

        // Only complete frames carry new pixels; idle frames mean "nothing changed".
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let rawStatus = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: rawStatus),
           status != .complete {
            return
        }
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        latestFrame = pixelBuffer
    }

    /// Feed a frame directly (used by tests; the stream path calls this logic on sampleQueue)
    func ingest(_ pixelBuffer: CVPixelBuffer) {
        nonisolated(unsafe) let buffer = pixelBuffer
        sampleQueue.async { [self] in
            guard !finished else { return }
            latestFrame = buffer
        }
    }

    // MARK: Writing (sampleQueue)

    private func writeFrame() {
        guard !finished, let frame = latestFrame else { return }
        guard writer.status == .writing else {
            if writer.status == .failed {
                print("[Compositor] Writer failed: \(String(describing: writer.error))")
                finished = true
                timer?.cancel()
            }
            return
        }
        guard input.isReadyForMoreMediaData else { return }

        let time = CMClockGetTime(CMClockGetHostTimeClock())
        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            sessionStarted = true
        }

        guard let pool = adaptor.pixelBufferPool else { return }
        var outBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
        guard let outBuffer else { return }

        let current = state.withLock { $0 }
        let image = MosaicRenderer.composite(
            frame: CIImage(cvPixelBuffer: frame),
            displaySize: displaySize,
            state: current,
            outputSize: outputSize
        )
        ciContext.render(image, to: outBuffer, bounds: CGRect(origin: .zero, size: outputSize), colorSpace: colorSpace)

        if adaptor.append(outBuffer, withPresentationTime: time) {
            framesWritten += 1
        } else {
            print("[Compositor] Append failed: \(String(describing: writer.error))")
        }
    }
}
