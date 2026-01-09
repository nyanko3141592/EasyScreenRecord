import Foundation
import AppKit
import Carbon.HIToolbox

/// Input monitor for detecting typing, double-click, and text selection
class InputMonitor {
    static let shared = InputMonitor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Typing detection
    private(set) var lastKeyPressTime: Date = .distantPast
    private(set) var isTyping: Bool = false

    // Typed text buffer for subtitles
    private var typedTextBuffer: String = ""
    private let maxBufferLength: Int = 100
    private var bufferClearTimer: Timer?

    // Modifier key display settings
    var showModifierKeys: Bool = true

    // Double-click detection
    private(set) var lastDoubleClickTime: Date = .distantPast
    private(set) var lastDoubleClickPosition: CGPoint = .zero
    private var lastClickTime: Date = .distantPast
    private var lastClickPosition: CGPoint = .zero
    private let doubleClickInterval: TimeInterval = 0.3
    private let doubleClickRadius: CGFloat = 5.0

    // Text selection detection
    private(set) var lastTextSelectionTime: Date = .distantPast
    private(set) var hasActiveSelection: Bool = false
    private var lastSelectedText: String = ""
    private var selectionCheckTimer: Timer?

    // Keys to ignore (modifiers, function keys, navigation)
    private static let ignoredKeyCodes: Set<Int> = [
        kVK_Command, kVK_Shift, kVK_Option, kVK_Control,
        kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl,
        kVK_Function, kVK_CapsLock,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_Escape,
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
    ]

    private init() {}

    func startMonitoring() {
        guard eventTap == nil else { return }

        // Create event tap to capture keyboard and mouse events
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                      (1 << CGEventType.leftMouseDown.rawValue) |
                                      (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            // Handle tap disabled event
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = InputMonitor.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            let monitor = InputMonitor.shared

            switch type {
            case .keyDown:
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                if !InputMonitor.ignoredKeyCodes.contains(keyCode) {
                    let flags = event.flags
                    let hasCommandOrControl = flags.contains(.maskCommand) || flags.contains(.maskControl)

                    // Always update typing state for non-modifier keys
                    monitor.lastKeyPressTime = Date()
                    monitor.isTyping = true

                    // Capture character for subtitle buffer
                    if hasCommandOrControl && monitor.showModifierKeys {
                        // Show modifier + key combination (e.g., ⌘C)
                        monitor.handleModifierKeyPress(keyCode: keyCode, flags: flags, event: event)
                    } else if !hasCommandOrControl {
                        // Normal typing without command/control
                        monitor.handleKeyPress(keyCode: keyCode, event: event)
                    }
                }

            case .leftMouseDown:
                let now = Date()
                let position = event.location

                // Check for double-click
                let timeSinceLastClick = now.timeIntervalSince(monitor.lastClickTime)
                let distance = hypot(position.x - monitor.lastClickPosition.x,
                                   position.y - monitor.lastClickPosition.y)

                if timeSinceLastClick < monitor.doubleClickInterval && distance < monitor.doubleClickRadius {
                    monitor.lastDoubleClickTime = now
                    monitor.lastDoubleClickPosition = position
                    #if DEBUG
                    print("[InputMonitor] Double-click detected at \(position)")
                    #endif
                }

                monitor.lastClickTime = now
                monitor.lastClickPosition = position

            case .leftMouseUp:
                // Schedule text selection check after mouse up
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    monitor.checkTextSelection()
                }

            default:
                break
            }

            return Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        ) else {
            #if DEBUG
            print("[InputMonitor] Failed to create event tap. Check accessibility permissions.")
            #endif
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)

        #if DEBUG
        print("[InputMonitor] Started monitoring input events")
        #endif
    }

    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
        isTyping = false
        selectionCheckTimer?.invalidate()
        selectionCheckTimer = nil

        #if DEBUG
        print("[InputMonitor] Stopped monitoring input events")
        #endif
    }

    /// Check for text selection changes
    private func checkTextSelection() {
        guard let selectedText = getSelectedText(), !selectedText.isEmpty else {
            if hasActiveSelection {
                hasActiveSelection = false
                lastSelectedText = ""
            }
            return
        }

        // New or changed selection
        if selectedText != lastSelectedText {
            lastSelectedText = selectedText
            lastTextSelectionTime = Date()
            hasActiveSelection = true
            #if DEBUG
            print("[InputMonitor] Text selection detected: \(selectedText.prefix(50))")
            #endif
        }
    }

    /// Get currently selected text using Accessibility API
    private func getSelectedText() -> String? {
        var focusedElement: CFTypeRef?
        let systemWideElement = AXUIElementCreateSystemWide()
        var result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result != .success || focusedElement == nil {
            if let app = NSWorkspace.shared.frontmostApplication {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            }
        }

        guard result == .success, let element = focusedElement else { return nil }

        var selectedTextValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)

        if selectedResult == .success, let text = selectedTextValue as? String {
            return text
        }
        return nil
    }

    // MARK: - Query Methods

    func isTypingActive(within interval: TimeInterval) -> Bool {
        let timeSinceLastKey = Date().timeIntervalSince(lastKeyPressTime)
        let active = timeSinceLastKey < interval
        if !active { isTyping = false }
        return active
    }

    func isDoubleClickActive(within interval: TimeInterval) -> Bool {
        return Date().timeIntervalSince(lastDoubleClickTime) < interval
    }

    func isTextSelectionActive(within interval: TimeInterval) -> Bool {
        return hasActiveSelection && Date().timeIntervalSince(lastTextSelectionTime) < interval
    }

    func getDoubleClickPosition() -> CGPoint? {
        if isDoubleClickActive(within: 2.0) {
            return lastDoubleClickPosition
        }
        return nil
    }

    // MARK: - Text Buffer Methods

    /// Build modifier key symbols string from event flags
    private func getModifierSymbols(from flags: CGEventFlags) -> String {
        var symbols = ""
        // Order: Control, Option, Shift, Command (standard macOS order)
        if flags.contains(.maskControl) { symbols += "⌃" }
        if flags.contains(.maskAlternate) { symbols += "⌥" }
        if flags.contains(.maskShift) { symbols += "⇧" }
        if flags.contains(.maskCommand) { symbols += "⌘" }
        return symbols
    }

    /// Handle key press with modifiers (e.g., ⌘C, ⌃⌥Delete)
    private func handleModifierKeyPress(keyCode: Int, flags: CGEventFlags, event: CGEvent) {
        let modifiers = getModifierSymbols(from: flags)
        guard !modifiers.isEmpty else { return }

        // Get key name for special keys or character for regular keys
        let keyString: String
        switch keyCode {
        case kVK_Delete: keyString = "Delete"
        case kVK_ForwardDelete: keyString = "⌦"
        case kVK_Return, kVK_ANSI_KeypadEnter: keyString = "↩"
        case kVK_Tab: keyString = "⇥"
        case kVK_Space: keyString = "Space"
        case kVK_Escape: keyString = "⎋"
        case kVK_UpArrow: keyString = "↑"
        case kVK_DownArrow: keyString = "↓"
        case kVK_LeftArrow: keyString = "←"
        case kVK_RightArrow: keyString = "→"
        default:
            // Get character from event
            if let chars = getCharactersFromEvent(event), !chars.isEmpty {
                keyString = chars.uppercased()
            } else {
                return
            }
        }

        // Add space before shortcut if buffer is not empty
        if !typedTextBuffer.isEmpty && !typedTextBuffer.hasSuffix(" ") {
            typedTextBuffer += " "
        }

        typedTextBuffer += "[\(modifiers)\(keyString)]"

        // Trim if too long
        if typedTextBuffer.count > maxBufferLength {
            typedTextBuffer = String(typedTextBuffer.suffix(maxBufferLength))
        }

        scheduleBufferClear()
    }

    /// Handle key press and add character to buffer
    private func handleKeyPress(keyCode: Int, event: CGEvent) {
        // Handle special keys
        switch keyCode {
        case kVK_Delete: // Backspace
            if !typedTextBuffer.isEmpty {
                typedTextBuffer.removeLast()
            }
            return
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // Clear buffer on Enter (new line)
            typedTextBuffer = ""
            return
        case kVK_Tab:
            typedTextBuffer += " "
            return
        case kVK_Space:
            typedTextBuffer += " "
            scheduleBufferClear()
            return
        default:
            break
        }

        // Get the character from the event
        if let characters = getCharactersFromEvent(event) {
            typedTextBuffer += characters

            // Trim if too long
            if typedTextBuffer.count > maxBufferLength {
                typedTextBuffer = String(typedTextBuffer.suffix(maxBufferLength))
            }

            scheduleBufferClear()
        }
    }

    /// Get characters from CGEvent
    private func getCharactersFromEvent(_ event: CGEvent) -> String? {
        var length: Int = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)

        guard length > 0 else { return nil }

        var chars = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &chars)

        return String(utf16CodeUnits: chars, count: length)
    }

    /// Schedule buffer clear after inactivity
    private func scheduleBufferClear() {
        bufferClearTimer?.invalidate()
        bufferClearTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.typedTextBuffer = ""
        }
    }

    /// Get the current typed text buffer
    func getTypedBuffer() -> String? {
        guard isTypingActive(within: 3.0), !typedTextBuffer.isEmpty else {
            return nil
        }
        return typedTextBuffer
    }

    /// Clear the typed text buffer
    func clearTypedBuffer() {
        typedTextBuffer = ""
    }
}

// MARK: - Legacy compatibility
typealias KeyboardMonitor = InputMonitor

struct AccessibilityUtils {

    // Text input role identifiers (used as fallback)
    private static let textInputRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
        "AXWebArea",
        "AXScrollArea",
    ]

    private static var lastDebugLog: Date = .distantPast

    /// Get cursor position - uses keyboard monitoring + focused element position
    static func getTypingCursorPosition() -> CGPoint? {
        // Check if typing is active (keyboard was pressed recently)
        // Use a short window (0.5s) - if no typing, return nil immediately
        guard KeyboardMonitor.shared.isTypingActive(within: 0.5) else {
            return nil
        }

        // Typing detected - now find position to zoom to
        return getFocusedElementPosition()
    }

    /// Get position of the currently focused element (for zoom target)
    /// Strategy: try caret position first, then fall back to mouse cursor
    /// (element/window center is often wrong for Terminal/browsers)
    /// All positions are returned in screen coordinates (top-left origin, matching Accessibility API)
    static func getFocusedElementPosition() -> CGPoint? {
        let frontApp = NSWorkspace.shared.frontmostApplication

        // 1. Try to get focused element and its caret position
        var focusedElement: CFTypeRef?
        let systemWideElement = AXUIElementCreateSystemWide()
        var result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result != .success || focusedElement == nil {
            if let app = frontApp {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            }
        }

        if result == .success, let element = focusedElement {
            let axElement = element as! AXUIElement

            // Try caret position (most precise - works for text editors, some text fields)
            if let caretPos = getCaretPosition(for: axElement) {
                #if DEBUG
                if Date().timeIntervalSince(lastDebugLog) > 1.0 {
                    print("[Position] Using caret: \(caretPos)")
                    lastDebugLog = Date()
                }
                #endif
                return caretPos
            }

            // For small elements (likely text fields), use element center
            if let elemPos = getSmallElementPosition(for: axElement) {
                #if DEBUG
                if Date().timeIntervalSince(lastDebugLog) > 1.0 {
                    print("[Position] Using small element: \(elemPos)")
                    lastDebugLog = Date()
                }
                #endif
                return elemPos
            }
        }

        // 2. Fall back to mouse cursor position
        // This is better than window center for Terminal/browsers where caret position isn't available
        // Users typically have their focus (and often mouse) near where they're typing
        if let mousePos = getMousePositionInScreenCoords() {
            #if DEBUG
            if Date().timeIntervalSince(lastDebugLog) > 1.0 {
                print("[Position] Using mouse: \(mousePos)")
                lastDebugLog = Date()
            }
            #endif
            return mousePos
        }

        return nil
    }

    /// Get element frame (position and size) from AXUIElement
    private static func getElementFrame(for element: AXUIElement) -> (position: CGPoint, size: CGSize)? {
        var pointValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pointValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let pointRef = pointValue, CFGetTypeID(pointRef) == AXValueGetTypeID(),
              let sizeRef = sizeValue, CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }

        var pos = CGPoint.zero
        var size = CGSize.zero

        AXValueGetValue(pointRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        guard size.width > 0 && size.height > 0 else { return nil }
        return (pos, size)
    }

    /// Get element center position
    private static func getElementCenter(for element: AXUIElement) -> CGPoint? {
        guard let frame = getElementFrame(for: element) else { return nil }
        return CGPoint(x: frame.position.x + frame.size.width / 2, y: frame.position.y + frame.size.height / 2)
    }

    /// Get element position only if it's a small element (likely a text field, not a whole window)
    private static func getSmallElementPosition(for element: AXUIElement) -> CGPoint? {
        guard let frame = getElementFrame(for: element) else { return nil }

        // Only use element position if it's reasonably small (like a text field)
        let maxReasonableSize: CGFloat = 400
        guard frame.size.width < maxReasonableSize && frame.size.height < maxReasonableSize else {
            return nil
        }

        return CGPoint(x: frame.position.x + frame.size.width / 2, y: frame.position.y + frame.size.height / 2)
    }

    /// Get mouse cursor position in screen coordinates (top-left origin)
    private static func getMousePositionInScreenCoords() -> CGPoint? {
        let mouseLocation = NSEvent.mouseLocation

        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                guard let primaryScreen = NSScreen.screens.first else { return nil }
                let primaryHeight = primaryScreen.frame.height
                let screenY = primaryHeight - mouseLocation.y
                return CGPoint(x: mouseLocation.x, y: screenY)
            }
        }

        return nil
    }

    private static func isTextInputElement(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleResult == .success) ? (roleValue as? String ?? "") : ""

        // Check for known text input roles
        if textInputRoles.contains(role) {
            return true
        }

        // Check for selected text range attribute (strong indicator of text input)
        // This works for most text inputs including web browsers
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        if rangeResult == .success {
            return true
        }

        // Check if element has editable text trait (for web browsers, Electron apps, etc.)
        var editableValue: CFTypeRef?
        let editableResult = AXUIElementCopyAttributeValue(element, "AXInsertionPointLineNumber" as CFString, &editableValue)
        if editableResult == .success {
            return true
        }

        // Check for AXFocused attribute on text-like elements (web content)
        if role == "AXStaticText" || role == "AXWebArea" || role == "AXGroup" || role == "AXUnknown" {
            var rangeValue2: CFTypeRef?
            let rangeResult2 = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue2)
            if rangeResult2 == .success {
                return true
            }
        }

        // Check for value attribute with string and editable flag
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if valueResult == .success, valueRef is String {
            // Check if element is editable
            var editableRef: CFTypeRef?
            let editableAttrResult = AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableRef)
            if editableAttrResult == .success {
                return true
            }
        }

        // Additional check: some web browsers mark the element as having a role description
        // that includes "text" or "input"
        var roleDescValue: CFTypeRef?
        let roleDescResult = AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescValue)
        if roleDescResult == .success, let roleDesc = roleDescValue as? String {
            let lowerDesc = roleDesc.lowercased()
            if lowerDesc.contains("text") || lowerDesc.contains("入力") || lowerDesc.contains("テキスト") {
                return true
            }
        }

        return false
    }

    private static func getCaretPosition(for element: AXUIElement) -> CGPoint? {
        // Try to get selected text range
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)

        guard rangeResult == .success, let rangeRef = rangeValue else {
            return nil
        }

        // Get bounds for the selected range (caret position)
        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsValue
        )

        if boundsResult == .success,
           let boundsRef = boundsValue,
           CFGetTypeID(boundsRef) == AXValueGetTypeID() {
            var bounds = CGRect.zero
            AXValueGetValue(boundsRef as! AXValue, .cgRect, &bounds)

            // Return the center of the caret bounds
            // For a caret (zero-width selection), this will be the insertion point
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }

        return nil
    }

    /// Get the currently typed/selected text from the focused element
    /// Returns (text, isTypingActive) tuple
    static func getTypedText() -> String? {
        // Check typing with longer window for subtitle display
        guard KeyboardMonitor.shared.isTypingActive(within: 3.0) else {
            return nil
        }

        return getTextFromFocusedElement()
    }

    /// Get text from focused element without typing check (for subtitle refresh)
    static func getTextFromFocusedElement() -> String? {
        var focusedElement: CFTypeRef?

        // Get focused element from system-wide
        let systemWideElement = AXUIElementCreateSystemWide()
        var result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        // Fallback to frontmost app
        if result != .success || focusedElement == nil {
            if let app = NSWorkspace.shared.frontmostApplication {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            }
        }

        guard result == .success, let element = focusedElement else {
            return nil
        }

        let axElement = element as! AXUIElement

        // Try to get selected text first
        var selectedTextValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        if selectedResult == .success, let selectedText = selectedTextValue as? String, !selectedText.isEmpty {
            return selectedText
        }

        // Get full value and extract recent text (last line or portion)
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef)
        if valueResult == .success, let text = valueRef as? String, !text.isEmpty {
            // Get the last line or last portion of text (for subtitle display)
            let lines = text.components(separatedBy: .newlines)
            if let lastLine = lines.last, !lastLine.isEmpty {
                // Limit to reasonable length for subtitle
                let maxLength = 80
                if lastLine.count > maxLength {
                    return String(lastLine.suffix(maxLength))
                }
                return lastLine
            }
        }

        return nil
    }

}
