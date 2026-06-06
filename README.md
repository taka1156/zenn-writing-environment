# Zenn Writing Environment

Zennの記事執筆・校正・プレビューをローカル(Dev Containers)で行うための作業環境です。

## Zennとは

> ![Zenn](/zenn-logo.png)
>
>
>Zennは「知見を共有するエンジニアに対価を」をコンセプトとした技術情報共有コミュ>ニティです。
>
>開発の知見やアイデアを得たら、気軽に記事にしましょう。
>
>あなたが詳しいトピックについては、ウェブで読める本にまとめて販売してみましょう。もちろん無料で公開してもOKです。
>
>Zennには有料のバッジを贈ることで著者を応援する仕組みがあります。バッジを受け取った著者にはZennから現金やAmazonギフトカードが還元されます。あなたが残した知見に助けられた誰かが、あなたにバッジを贈ってくれるかもしれません。

## Zennプロフィール

記事一覧はこちら:

https://zenn.dev/taka1156

## セットアップ

```bash
yarn install
```

## よく使うコマンド

- `yarn na`: テンプレートから新規記事を作成
- `yarn tl`: 記事の textlint を実行
- `yarn tlf`: 記事の textlint を自動修正付きで実行
- `yarn pv`: Zenn のローカルプレビューを起動

## ディレクトリ構成

- `articles/`: 記事ファイル
- `books/`: 本コンテンツ
- `template/article.md`: 新規記事用テンプレート
- `scripts/customNewZennArticle.mjs`: 新規記事生成スクリプト

## 記事作成フロー

1. `yarn na` で `articles/` に新しい記事ファイルを作成
2. 記事を執筆
3. `yarn tl` または `yarn tlf` で校正
4. `yarn pv` で表示を確認
