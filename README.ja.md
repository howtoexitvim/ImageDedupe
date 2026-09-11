<div align="center">

# Image Dedupe

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Photo%20Dedupe-2563eb)
![Local First](https://img.shields.io/badge/architecture-local--first-059669)

</div>

Image Dedupe は、接続した iPhone のメディアを確認し、選んだファイルをダウンロードし、控えめな重複候補を見つけ、確認済みのデバイス上の項目を意図して削除するための Mac ネイティブアプリです。

Apple の ImageCaptureCore フレームワークの上に構築されています。アカウントもクラウドバックエンドも解析も、カタログのアップロードもネットワーククライアントもありません。すべてが自分の Mac の中で完結します。

勝手に削除されることはありません。アプリは提案するだけで、決めるのはあなたです。

旧称 iPhone Dedupe。改名後も既存の操作履歴と設定は自動的に引き継がれます。識別子として安定している必要がある箇所にのみ、旧名称が残っています。

## インストール

[リリースページ](https://github.com/howtoexitvim/ImageDedupe/releases)から DMG をダウンロードし（現在のリリースは `ImageDedupe-v1.0`、バージョン 1.0.0）、アプリを「アプリケーション」にドラッグしてから、ダウンロードの隔離属性を解除します。

```sh
xattr -dr com.apple.quarantine "/Applications/Image Dedupe.app"
```

このビルドはアドホック署名で、Apple の公証は**受けていません**。そのため、この操作をするまで Gatekeeper が起動をブロックします。対応環境は macOS 14 以降、Apple シリコン（arm64）のみです。公証されていないバイナリを実行したくない場合は、以下の手順でソースからビルドしてください。

スキャンの前に iPhone のロックを解除してこの Mac を信頼し、「イメージキャプチャ」「写真」など、デバイスセッションを占有し得るアプリを終了してください。

## 安全性

安全性はこのプロジェクトの目的そのものであり、付け足された機能ではありません。

- 重複検出は意図的に控えめです。あくまで確認用の*候補*を提示するだけで、自動削除は行いません。
- デバイス上の削除には必ずアプリ内での明示的な確認が必要で、監査記録を永続化し、削除後に自動で再スキャンします。リトライは検証のみを行います。
- 自動処理や開発用ハーネスによる削除には、対象のフィクスチャファイル名を明示した新しい承認が追加で必要です。過去の承認を再利用することはできません。
- ダウンロードはまず非公開の場所にステージングされ、ディスクリプタ相対かつ上書きしない方式でコミットされます。既存ファイルが黙って置き換えられることはありません。
- アカウントなし、クラウドなし、解析なし、ネットワーククライアントなし。
- ローカルのビルドゲートが Hardened Runtime を強制し、アプリはトラッキングなしのプライバシーマニフェストを同梱しています。

## 機能

- フォーカスを共有するネイティブの List / Grid ブラウザと、明示的なチェックボックス選択；
- ファイル名検索に加え、`name:`、`kind:`、`size:`、`duration:` フィルタ；
- 並べ替え可能で状態が保存される List の列；
- 段階的に読み込まれる静的な Inspector プレビュー（最大 2048 ピクセル、メモリキャッシュに上限あり）；
- 控えめな重複候補 — 自動削除は行いません；
- ダウンロードの進捗、処理中ファイルの状態、キャンセル、保存先の事前チェック、衝突のブロック；
- 明示的なデバイス削除の確認、永続化された監査記録、自動再スキャン、検証のみのリトライ；
- 部分的な失敗とキャンセルを保存する Results 履歴；
- 主要ワークフローにおけるフルキーボードアクセスと VoiceOver セマンティクス。

## 動作要件

- macOS 14 以降、Apple シリコン（arm64）；
- Swift 6.2 ツールチェーン（ビルドする場合）；
- ロック解除済みで信頼済みの iPhone と、データ転送対応のケーブル；
- スキャン中は「イメージキャプチャ」「写真」など、デバイスセッションを占有し得るアプリを終了しておくこと。

## ビルドと実行

通常のローカル Debug アプリバンドルをビルドします。

```sh
./scripts/build-debug-app.sh
open "$(swift build --show-bin-path)/Image Dedupe.app"
```

UI とアクセシビリティのテストには `.app` バンドルを使ってください。SwiftPM の実行ファイルを直接起動すると macOS の通常のアプリ登録を経由しないため、受け入れ確認の経路にはなりません。

テストスイート全体を実行します。

```sh
swift test
swift test -c release
```

最新の検証済みベースラインは、Debug と Release の両構成で XCTest 650 件と Swift Testing 22 件です。

バンドル用スクリプトは、対象そのものが実行中のあいだは置き換えや再署名を拒否します。再ビルドの前にアプリを終了してください。これにより、macOS が実行中のプロセスを `Code Signature Invalid` で終了させるのを防げます。

## リリース候補

明示的にローカル限定・配布不可のアドホック Hardened Runtime 候補をビルドします。

```sh
IMAGE_DEDUPE_ALLOW_ADHOC=1 ./scripts/build-release-candidate.sh
```

配布可能な候補をビルドするには、呼び出し側が所有する Developer ID Application の署名 ID を指定します。

```sh
IMAGE_DEDUPE_SIGNING_IDENTITY="Developer ID Application: …" \
  ./scripts/build-release-candidate.sh
```

呼び出し側が所有する `notarytool` のキーチェーンプロファイルを設定したうえで、次を実行します。

```sh
IMAGE_DEDUPE_SIGNING_IDENTITY="Developer ID Application: …" \
IMAGE_DEDUPE_NOTARY_PROFILE="profile-name" \
  ./scripts/notarize-release.sh "/path/to/Image Dedupe.app"
```

リリーススクリプトは、必要な署名や公証の入力が欠けている場合には安全側に倒して失敗します。このリポジトリには一切の認証情報を保存していません。

## ディスクイメージ

`scripts/package-dmg.sh` は、ビルド済みの候補を `dist/Image-Dedupe-<version>.dmg` に、おなじみの「アプリケーションへドラッグ」レイアウトで包みます。あえてビルドは行いません。`build-release-candidate.sh` が生成したバンドルをそのまま梱包するので、配布される成果物は検証を通ったものそのものであり、それに似た別のビルドではありません。

```sh
IMAGE_DEDUPE_ALLOW_ADHOC=1 ./scripts/package-dmg.sh
```

梱包前にバンドルへ `verify-release.sh` を再実行し、`IMAGE_DEDUPE_ALLOW_ADHOC=1` が明示的に設定されていない限りアドホック署名を拒否します。ディスクイメージこそ、未検証のバンドルが「ローカルの失敗」から「誰かのダウンロード」に変わる地点だからです。`IMAGE_DEDUPE_SIGNING_IDENTITY` を設定すればイメージ自体も署名されます。スタップリングはバンドルに対して行われるため、梱包の前に `.app` を公証してください。

`dist/` は無視され、コミットされることはありません。

## プロジェクト構成

- `Sources/DeduperCore`：純粋なモデル、検索/ソート、重複判定ポリシー、表示、リトライポリシー；
- `Sources/DeviceMediaKit`：直列化された ImageCaptureCore ゲートウェイと、安全なファイルシステム境界；
- `Sources/ImageDedupeApp`：SwiftUI/AppKit アプリケーション、状態、永続化、ビュー；
- `Sources/ImageDedupeVerifier`：開発専用の実機ハーネス；
- `Tests`：ユニット、統合、レンダラ、操作、永続化、セキュリティ回帰テスト；
- `Packaging`：アプリの Info.plist とプライバシーマニフェスト；
- `scripts`：Debug/Release のバンドル、検証、公証用ツール。

## 現状

実機の iPhone に接続して動作を確認し、3,961 件中 3,961 件のメディア項目を読み込みました。ソースとローカルの Hardened Runtime ビルドゲートは完成しています。

正直なところ、まだ残っている作業もあります。Developer ID による署名、Apple の公証とスタップリング、クリーンな Mac での Gatekeeper 検証、ユニバーサルビルド、そして App Sandbox を採用するかの判断です。これらが片付くまでは、配布する DMG には上記の隔離属性の解除が必要です。

## ライセンス

[MIT](LICENSE)
