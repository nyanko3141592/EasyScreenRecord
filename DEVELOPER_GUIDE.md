# EasyScreenRecord 開発ガイド

このガイドでは、EasyScreenRecord の開発環境セットアップ、ビルド方法、デバッグ手順について説明します。

## 目次

- [必要条件](#必要条件)
- [開発環境セットアップ](#開発環境セットアップ)
- [ビルド方法](#ビルド方法)
- [デバッグ](#デバッグ)
- [コード構成](#コード構成)
- [テスト](#テスト)
- [トラブルシューティング](#トラブルシューティング)

## 必要条件

### ハードウェア

- Apple Silicon または Intel Mac

### ソフトウェア

| 要件 | バージョン |
|------|-----------|
| macOS | 14.0 (Sonoma) 以降 |
| Xcode | 15.0 以降 |
| Swift | 5.9 以降 |
| Command Line Tools | `xcode-select --install` でインストール |

### 権限

開発・テストには以下の権限が必要です：

1. **画面収録** - `システム設定 → プライバシーとセキュリティ → 画面収録`
2. **アクセシビリティ** - `システム設定 → プライバシーとセキュリティ → アクセシビリティ`

## 開発環境セットアップ

### 1. リポジトリのクローン

```bash
git clone https://github.com/nyanko3141592/EasyScreenRecord.git
cd EasyScreenRecord
```

### 2. プロジェクトを開く

#### Xcode を使用する場合

```bash
cd EasyScreenRecord
open EasyScreenRecord.xcodeproj
```

#### コマンドラインのみで開発する場合

```bash
cd EasyScreenRecord/EasyScreenRecord
./run.sh
```

### 3. 署名設定（Xcode）

1. Xcode でプロジェクトを開く
2. ターゲット「EasyScreenRecord」を選択
3. 「Signing & Capabilities」タブを開く
4. 「Team」を自分の Apple Developer アカウントに変更
5. 「Signing Certificate」を「Sign to Run Locally」に設定

## ビルド方法

### 開発ビルド（推奨）

```bash
cd EasyScreenRecord/EasyScreenRecord
./run.sh
```

これにより：
- Debug 構成でビルド
- 自動的にアプリを起動
- 既存のプロセスがあれば終了してから起動

### クリーンビルド

```bash
./run.sh --clean
```

キャッシュをクリアしてから再ビルドします。

### リリースビルド

```bash
./run.sh --release
```

最適化された Release 構成でビルドします。

### DMG 作成（配布用）

```bash
./build-dmg.sh
```

署名されていない配布用 DMG ファイルを作成します。

### Xcode でのビルド

1. スキームを「EasyScreenRecord」に設定
2. 実行先を「My Mac」に設定
3. `Cmd + B` でビルド
4. `Cmd + R` で実行

## デバッグ

### ログ出力

アプリケーションのログはコンソールに出力されます。

```bash
# ターミナルで実行してログを確認
./run.sh
```

### 主要なデバッグポイント

| 場所 | 目的 |
|------|------|
| `ScreenRecorder.swift:startRecording()` | 録画開始処理 |
| `ScreenRecorder.swift:stream(_:didOutputSampleBuffer:)` | フレーム受信 |
| `ScreenRecorder.swift` zoom関連メソッド | ズーム処理 |
| `AccessibilityUtils.swift` | カーソル位置検出 |

### Xcode デバッグ

1. ブレークポイントを設定
2. `Cmd + R` でデバッグ実行
3. Variables View で変数を確認
4. LLDB コンソールでコマンド実行

### 権限関連のデバッグ

権限が正しく設定されているか確認：

```bash
# アクセシビリティ権限の確認
tccutil reset Accessibility com.your.bundle.id

# 画面収録権限の確認
tccutil reset ScreenCapture com.your.bundle.id
```

## コード構成

### ディレクトリ構造

```
EasyScreenRecord/
├── EasyScreenRecord/
│   ├── Models/                 # ビジネスロジック
│   │   ├── ScreenRecorder.swift
│   │   ├── ZoomSettings.swift
│   │   └── AccessibilityUtils.swift
│   │
│   ├── ViewModels/             # UI状態管理
│   │   └── RecorderViewModel.swift
│   │
│   ├── Views/                  # SwiftUI Views
│   │   ├── EasyScreenRecordApp.swift
│   │   ├── ContentView.swift
│   │   ├── RegionSelectorView.swift
│   │   └── RecordingOverlayView.swift
│   │
│   ├── Assets.xcassets/        # 画像・アイコン
│   ├── run.sh                  # 開発用スクリプト
│   └── build-dmg.sh            # DMG作成スクリプト
│
├── ARCHITECTURE.md             # アーキテクチャ説明
├── DEVELOPER_GUIDE.md          # このファイル
├── CONTRIBUTING.md             # コントリビューションガイド
└── CURRENT_STATUS.md           # 現在の状態
```

### 命名規則

| 種類 | 規則 | 例 |
|------|------|-----|
| クラス/構造体 | UpperCamelCase | `ScreenRecorder`, `ZoomSettings` |
| 変数/関数 | lowerCamelCase | `isRecording`, `startRecording()` |
| 定数 | lowerCamelCase | `maxZoomScale` |
| ファイル | クラス名.swift | `ScreenRecorder.swift` |

### コードスタイル

- Swift 標準のコードスタイルを使用
- `// MARK: -` でセクション分け
- 複雑なロジックにはインラインコメント

## テスト

### 手動テスト

現在は手動テストが主な検証方法です。

#### 基本的なテスト項目

1. **録画開始/停止**
   - メニューバーから録画開始
   - ショートカット（`Cmd + R`）で開始/停止
   - 正常に MOV ファイルが保存されるか確認

2. **範囲選択**
   - ドラッグで範囲を選択
   - 選択範囲のリサイズ
   - ESC でキャンセル

3. **スマートズーム**
   - テキストエディタでタイピング時にズーム
   - タイピング停止でズームアウト
   - スムーズな遷移

4. **権限エラー**
   - 権限なしで起動時の挙動
   - 権限付与後の再起動

### ユニットテスト（今後の課題）

現在ユニットテストは未実装です。追加予定：

- `ZoomSettings` のシリアライズ/デシリアライズ
- 座標変換ロジック
- ステートマシン遷移

## トラブルシューティング

### ビルドエラー

#### 「Code Sign error」

```
解決策:
1. Xcode → Preferences → Accounts でサインイン
2. ターゲット設定で Team を選択
3. 「Sign to Run Locally」を選択
```

#### 「ScreenCaptureKit is only available on macOS 12.3+」

```
解決策:
1. Deployment Target が 14.0 以上か確認
2. Xcode を最新版にアップデート
```

### 実行時エラー

#### 「録画が開始されない」

```
確認事項:
1. システム設定 → 画面収録 で許可されているか
2. ターミナル/Xcode を再起動
3. 権限をリセットして再付与
```

#### 「EXC_BAD_ACCESS」

```
一般的な原因:
- Accessibility API の不適切な使用
- 解放済みオブジェクトへのアクセス

対処法:
- AccessibilityUtils の CFTypeRef 管理を確認
- window.isReleasedWhenClosed = false を確認
```

#### 「AVAssetWriter failed」

```
確認事項:
1. 保存先ディレクトリに書き込み権限があるか
2. ディスク容量が十分か
3. 他のプロセスがファイルをロックしていないか
```

### パフォーマンス問題

#### 「CPU 使用率が高い」

```
確認事項:
1. フレームレート設定 (60fps → 30fps)
2. 録画解像度
3. ズームスムージング設定
```

#### 「録画がカクつく」

```
対処法:
1. 他のアプリケーションを終了
2. フレームレートを下げる
3. 録画範囲を小さくする
```

## 開発のヒント

### デバッグ出力を追加

```swift
#if DEBUG
print("[DEBUG] \(#function): \(value)")
#endif
```

### 状態遷移のログ

```swift
func setState(_ newState: RecordingState) {
    print("[State] \(state) → \(newState)")
    state = newState
}
```

### Accessibility API のテスト

```swift
// カーソル位置の取得テスト
if let position = AccessibilityUtils.getTypingCursorPosition() {
    print("Cursor at: \(position)")
}
```

## 関連ドキュメント

- [ARCHITECTURE.md](./ARCHITECTURE.md) - システムアーキテクチャ
- [CONTRIBUTING.md](./CONTRIBUTING.md) - コントリビューションガイド
- [README.md](./EasyScreenRecord/README.md) - ユーザー向けドキュメント
