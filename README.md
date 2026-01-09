# EasyScreenRecord

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-brightgreen" alt="macOS Version">
  <img src="https://img.shields.io/github/v/release/nyanko3141592/EasyScreenRecord" alt="Release">
  <img src="https://img.shields.io/github/license/nyanko3141592/EasyScreenRecord" alt="License">
</p>

<p align="center">
  <strong>スマートズーム機能付き画面録画アプリ for macOS</strong>
</p>

<p align="center">
  <a href="https://nyanko3141592.github.io/EasyScreenRecord/">🌐 ホームページ</a> •
  <a href="https://github.com/nyanko3141592/EasyScreenRecord/releases/latest">📦 ダウンロード</a>
</p>

---

## 特徴

- **🔍 スマートズーム** - タイピング、ダブルクリック、テキスト選択を検知して自動ズーム
- **📝 自動字幕** - タイピング内容をリアルタイム表示（ターミナル・ブラウザ対応）
- **🎯 範囲選択録画** - ドラッグで録画範囲を自由に選択
- **🎨 フォーカス表示** - 録画範囲外をグレーアウト、ズーム領域に追従
- **⚡ 軽量** - ネイティブSwiftUIアプリ、メニューバーから即座にアクセス
- **🛠️ カスタマイズ** - ズーム倍率/フレームサイズ、スムージング等を細かく調整

## インストール

### DMGからインストール（推奨）

1. [最新リリース](https://github.com/nyanko3141592/EasyScreenRecord/releases/latest)からDMGをダウンロード
2. DMGを開いて`EasyScreenRecord.app`をApplicationsにドラッグ
3. `システム設定 → プライバシーとセキュリティ → アクセシビリティ`で許可
4. 初回は右クリック→「開く」で起動（署名なしアプリのため）

### ソースからビルド

```bash
git clone https://github.com/nyanko3141592/EasyScreenRecord.git
cd EasyScreenRecord/EasyScreenRecord
./run.sh
```

## 使い方

### 基本操作

1. メニューバーのアイコンをクリック
2. 「Start Recording」で範囲選択画面を表示
3. ドラッグで録画範囲を選択
4. スマートズーム・字幕のオプションを設定
5. 「録画開始」ボタンをクリック
6. 録画停止はメニューバーから

### キーボードショートカット

| ショートカット | 動作 |
|--------------|------|
| `⌘R` | 録画開始/停止 |
| `⇧⌘F` | フルスクリーン録画開始 |
| `⌘,` | 設定を開く |
| `Enter` | 範囲選択を確定して録画開始 |
| `ESC` | 範囲選択をキャンセル |

### ズームトリガー

スマートズームは以下のアクションで発動します（個別にON/OFF可能）:

- **タイピング** - キーボード入力を検知
- **ダブルクリック** - マウスのダブルクリックを検知
- **テキスト選択** - テキストの選択操作を検知

### 設定項目

| カテゴリ | 設定 | 説明 |
|---------|------|------|
| 一般 | Smart Zoom | 自動ズームのON/OFF |
| | ズームモード | 倍率指定 or フレームサイズ指定 |
| | プリセット | 滑らか / 標準 / 高速 |
| 録画 | 保存先 | 録画ファイルの保存フォルダ |
| | フレームレート | 30fps / 60fps |
| | カーソル表示 | 録画にカーソルを含める |
| 字幕 | 自動字幕 | タイピング内容を字幕表示 |
| | フォントサイズ | 字幕の大きさ |
| | 表示位置 | 上部 / 下部 |

## 動作環境

- macOS 14.0 (Sonoma) 以降
- Apple Silicon / Intel Mac
- 画面収録の権限
- アクセシビリティの権限

## 技術仕様

- **フレームワーク**: SwiftUI, ScreenCaptureKit, AVFoundation
- **出力形式**: MOV (H.264)
- **解像度**: Retina対応（2倍スケール）

## クイックスタート（開発者向け）

```bash
# リポジトリをクローン
git clone https://github.com/nyanko3141592/EasyScreenRecord.git
cd EasyScreenRecord/EasyScreenRecord

# ビルドして起動
./run.sh
```

詳細は [開発ガイド](./DEVELOPER_GUIDE.md) を参照してください。

## 開発

```bash
# 開発用ビルド＆起動
./run.sh

# クリーンビルド
./run.sh --clean

# リリース用DMG作成
./build-dmg.sh
```

## ドキュメント

| ドキュメント | 説明 |
|-------------|------|
| [アーキテクチャ](./ARCHITECTURE.md) | システム設計・コンポーネント構成 |
| [開発ガイド](./DEVELOPER_GUIDE.md) | 開発環境セットアップ・ビルド方法 |
| [コントリビューション](./CONTRIBUTING.md) | 貢献の方法・コードスタイル |

## 貢献

バグ報告、機能リクエスト、Pull Request を歓迎します。詳細は [CONTRIBUTING.md](./CONTRIBUTING.md) をご覧ください。

## ライセンス

MIT License

## 作者

[@nyanko3141592](https://github.com/nyanko3141592)
