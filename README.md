# madoka

主にカスタムROMのビルド実行用スクリプトです。  
優秀なマネージャーのつもりですが、セットアップまではしてくれません。

## 機能

- 実行時の引数によるROM選択・ビルドターゲット・ツイート可否・ `repo sync` 可否・ `make clean` 可否 の指定
    - 対話型でないので一度実行すれば終了まで操作不要
- 開始/終了時にTwitterへ投稿
    - [oysttyer](https://github.com/oysttyer/oysttyer) に丸投げしています。
    - 各自で使う際はハッシュタグとか変えといてください
- ログの保存、ビルド成否による保存先の振り分け
- 複数種類のカスタムROMに対応可能
    - ファイル名のフォーマット等、対応は各自で
    - とりあえずCyanogenModとResurrection RemixとAOKPのフォーマットに対応しています
        - が、バージョンベタ打ちなのが欠点
- 終了時に [Pushbullet](https://www.pushbullet.com/) APIを使用したプッシュ通知
    - アクセストークンの発行が必要です
- ビルド完了時に [MEGA](https://mega.nz) へのアップロード
    - MEGAのアカウント及び別途 [megatools](https://megatools.megous.com/) のセットアップが必要
    - あとたぶんMEGA上でフォルダ作っとかないとコケるかも？
- ビルド完了後に別ディレクトリへROMの `.zip` を退避
    - デフォルトでは `~/rom` になっています
    - 連続で複数機種ビルドする際に毎回 `make clean` する運用も可能に

## 用法

```bash
mkdir -p build
cd build
git clone https://github.com/lindwurm/madoka.git
```

- ディレクトリ構造こんな感じになります
    - `~/build` の名前はスクリプトに関係しませんし、わたしは実際のところ `~/ssd` にしていて、この実態は `/ssd1` にマウントされたSSDだったりします。)

```
~/
|
|-- build/
|   |-- aokp/
|   |-- cm13/
|   |-- log/
|   |   |-- fail/
|   |   `-- success/
|   |-- madoka/
|   |   |-- build.sh
|   |   |-- LICENSE
|   |   `-- README.md
|   `-- rr/
`-- rom/  
    `-- ${device}/
```

実際の使い方は以下の通りです。可否は0(否)か1(可)かで指定してください。

```bash
./build.sh [ROMのディレクトリ名] [ビルドターゲット] <ツイート可否> <repo sync可否> <make clean可否>
```

## ライセンス

**madoka** は The MIT License で提供されます。

## 作者

- lindwurm
    - Twitter: [@lindwurm](https://twitter.com/lindwurm)
    - GitHub: [@lindwurm](https://github.com/lindwurm)
    - Web: [maud.io](https://maud.io)
    - Blog: [dev:mordiford](http://dev.maud.io)
