<div align="center">

# Image Dedupe

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![タイプ](https://img.shields.io/badge/type-Photo%20Dedupe-2563eb)
![アーキテクチャ](https://img.shields.io/badge/architecture-local--first-059669)

</div>

Image Dedupe は、iPhone の写真とビデオを整理するための Mac アプリです。

ケーブルでつないでスキャンすれば、すべてが一つのウィンドウに並びます。並べ替えできるリスト、あるいはサムネイルのグリッド。その横にプレビューとメタデータ。探したいものを検索し、残したいものをダウンロードし、不要になったものを削除できます。

iPhone との通信は、Apple 自身の ImageCaptureCore を使ってケーブル経由で行います。アカウントなし、クラウドなし、解析なし、ネットワーク通信なし。何ひとつ Mac の外に出ません。

そして、勝手に削除されるものは何もありません。アプリが提案し、決めるのはあなたです。

## Image Dedupe を選ぶ理由

- 🔒 **すべてローカルで完結**：サインイン不要、アップロードなし、テレメトリなし。あなたの Mac とケーブルだけ。
- 🧊 **あえて保守的に**：重複は自動削除ではなく、確認してもらうための候補です。
- 🔍 **すぐに見つかる**：ファイル名で検索、あるいは `name:`、`kind:`、`size:`、`duration:` フィルタで絞り込み。
- 🖼️ **確認してから操作**：リストとグリッド、並べ替え可能な列、プレビューと実際の EXIF メタデータを表示するインスペクタ。
- ⬇️ **選んだものだけダウンロード**：進行状況の表示、いつでもキャンセル、保存先の事前チェック、無断の上書きなし。
- 🗑️ **削除は明確な意思で**：アプリ内での明示的な確認、監査記録の保存、そして完了後の自動再スキャン。
- 🆓 **無料、MIT ライセンス**。

## スクリーンショット

<div align="center">
  <img src="assets/duplicates-review.png" width="88%" alt="Image Dedupe の重複レビュー画面：QVKQ5385.JPG — 2 copies というグループ見出しの下に 2 つのコピーが並び、一方が残す側として示され、インスペクタにプレビューと EXIF メタデータが表示されている" />
</div>

<br/>

<table>
	<tr>
		<td align="center" colspan="2"><strong>Scanned 4189 items. Conservative duplicates: 1.</strong><br/>このステータス行こそが、このアプリの考え方そのものです。確信できるものだけを提案します。</td>
	</tr>
	<tr>
		<td align="center"><strong>つないでスキャン</strong></td>
		<td align="center"><strong>リスト表示とインスペクタ</strong></td>
	</tr>
	<tr>
		<td align="center"><img src="assets/scan-empty.png" alt="iPhone の接続を待つ Image Dedupe の空の状態と Scan iPhone ボタン" /></td>
		<td align="center"><img src="assets/all-media-list.png" alt="名前・種類・日付・ファイルサイズの列、チェックボックス選択、検索フィールド、右側のインスペクタを備えた Image Dedupe のリストブラウザ" /></td>
	</tr>
	<tr>
		<td align="center"><strong>グリッド表示</strong></td>
		<td align="center"><strong>レビュー待ちの重複</strong></td>
	</tr>
	<tr>
		<td align="center"><img src="assets/all-media-grid.png" alt="同じライブラリをサムネイルで表示した Image Dedupe のグリッドブラウザ" /></td>
		<td align="center"><img src="assets/duplicates-review.png" alt="同じファイルの 2 つのコピーからなる Image Dedupe の重複グループ。一方が残す側として示されている" /></td>
	</tr>
</table>

## インストール

[リリースページ](https://github.com/howtoexitvim/ImageDedupe/releases)から DMG をダウンロードし（現在のリリースは `ImageDedupe-v1.0`、バージョン 1.0.0）、**Image Dedupe** をアプリケーションフォルダにドラッグします。

このビルドは ad-hoc 署名で、まだ公証を受けていません。そのためダウンロードフラグを外すまで macOS がブロックします。ターミナルで一度だけ実行してください。

```sh
xattr -dr com.apple.quarantine "/Applications/Image Dedupe.app"
```

その後は通常どおり開けます。

**必要なもの：** macOS 14 以降の Apple シリコン Mac、この Mac を信頼済みでロック解除された iPhone、データ転送対応のケーブル、そしてスキャン中はイメージキャプチャと写真アプリを終了しておくこと。

## ソースからのビルド

macOS 14 以降と Swift 6.2 ツールチェーンが必要です。

```sh
./scripts/build-debug-app.sh
open "$(swift build --show-bin-path)/Image Dedupe.app"
swift test
```

## これから

Developer ID 署名と Apple の公証はまだ対応できていません。上記の隔離フラグの手順が必要なのはそのためです。ユニバーサルビルドも予定しています。（本アプリはかつて iPhone Dedupe という名前でした。既存の履歴と設定は自動的に引き継がれます。）

## License

[MIT](LICENSE)
