# EasyScreenRecord への貢献

EasyScreenRecord への貢献に興味を持っていただきありがとうございます。このドキュメントでは、貢献の方法について説明します。

## 貢献の方法

### Issue の報告

バグを発見した場合や機能リクエストがある場合は、[GitHub Issues](https://github.com/nyanko3141592/EasyScreenRecord/issues) で報告してください。

#### バグ報告のテンプレート

```markdown
## バグの説明
[バグの簡潔な説明]

## 再現手順
1. '...' を開く
2. '...' をクリック
3. '...' までスクロール
4. エラーが発生

## 期待される動作
[期待される動作の説明]

## 実際の動作
[実際に起こった動作]

## 環境
- macOS バージョン: [例: 14.0]
- アプリバージョン: [例: 1.0.0]
- Mac モデル: [例: MacBook Pro M1]

## スクリーンショット
[該当する場合は添付]
```

#### 機能リクエストのテンプレート

```markdown
## 機能の説明
[追加したい機能の説明]

## 動機
[なぜこの機能が必要か]

## 提案する解決策
[どのように実装するか]

## 代替案
[検討した他の方法]
```

### Pull Request

コードの貢献は Pull Request で受け付けています。

#### PR 作成の流れ

1. **リポジトリをフォーク**
   ```bash
   # GitHub で Fork ボタンをクリック
   git clone https://github.com/YOUR_USERNAME/EasyScreenRecord.git
   cd EasyScreenRecord
   ```

2. **ブランチを作成**
   ```bash
   git checkout -b feature/your-feature-name
   # または
   git checkout -b fix/your-bug-fix
   ```

3. **変更を実装**
   - [開発ガイド](./DEVELOPER_GUIDE.md)を参照
   - コードスタイルに従う
   - 適切なコミットメッセージを書く

4. **動作確認**
   ```bash
   cd EasyScreenRecord/EasyScreenRecord
   ./run.sh
   ```

5. **コミット**
   ```bash
   git add .
   git commit -m "feat: 機能の簡潔な説明"
   ```

6. **プッシュ & PR 作成**
   ```bash
   git push origin feature/your-feature-name
   # GitHub で Pull Request を作成
   ```

## コードスタイル

### Swift コードスタイル

- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) に従う
- インデントは 4 スペース
- 行の長さは 120 文字以内を推奨

### コード構成

```swift
// MARK: - Properties

private var someProperty: String

// MARK: - Lifecycle

init() {
    // 初期化
}

// MARK: - Public Methods

func publicMethod() {
    // 実装
}

// MARK: - Private Methods

private func privateMethod() {
    // 実装
}
```

### コミットメッセージ

[Conventional Commits](https://www.conventionalcommits.org/) 形式を推奨します。

| プレフィックス | 用途 |
|---------------|------|
| `feat:` | 新機能 |
| `fix:` | バグ修正 |
| `docs:` | ドキュメントのみ |
| `style:` | フォーマット変更（動作に影響なし） |
| `refactor:` | リファクタリング |
| `perf:` | パフォーマンス改善 |
| `test:` | テスト追加・修正 |
| `chore:` | ビルドプロセス等 |

#### 例

```
feat: スマートズームにダブルクリックトリガーを追加

- ダブルクリック検知ロジックを実装
- ZoomSettings にトリガー設定を追加
- 設定UIにトグルを追加

Closes #42
```

## Pull Request ガイドライン

### PR の内容

- 1つの PR では 1つの機能/修正に集中
- 大きな変更は複数の PR に分割
- WIP の場合はタイトルに `[WIP]` を付ける

### PR の説明

```markdown
## 変更内容
[変更の概要]

## 変更の種類
- [ ] バグ修正
- [ ] 新機能
- [ ] 破壊的変更
- [ ] ドキュメント更新

## テスト方法
[テスト手順]

## チェックリスト
- [ ] コードがビルドできる
- [ ] 手動テストを実施した
- [ ] ドキュメントを更新した（必要な場合）
```

### レビュープロセス

1. CI チェックが通ることを確認
2. メンテナーがレビュー
3. フィードバックに対応
4. 承認後にマージ

## 開発の優先事項

現在、以下の分野での貢献を特に歓迎しています：

### 高優先度

- [ ] ユニットテストの追加
- [ ] 権限エラーのハンドリング改善
- [ ] 保存先選択機能の実装

### 中優先度

- [ ] フレームレート設定の拡張
- [ ] 録画品質オプション
- [ ] ローカライズ対応

### 低優先度

- [ ] テーマ対応（ダークモード等）
- [ ] ショートカットのカスタマイズ
- [ ] 録画履歴機能

## 行動規範

### 基本原則

- 敬意を持って他者に接する
- 建設的なフィードバックを心がける
- 多様な意見を尊重する

### コミュニケーション

- 日本語または英語で OK
- Issue/PR での質問は歓迎
- 不明点は遠慮なく聞いてください

## 質問・サポート

- **一般的な質問**: [GitHub Discussions](https://github.com/nyanko3141592/EasyScreenRecord/discussions)
- **バグ報告**: [GitHub Issues](https://github.com/nyanko3141592/EasyScreenRecord/issues)
- **開発者**: [@nyanko3141592](https://github.com/nyanko3141592)

## ライセンス

貢献されたコードは MIT License の下でライセンスされます。
