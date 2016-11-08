#!/bin/bash

mkdir -p ../log/success ../log/fail ~/rom

# YOUR_ACCESS_TOKEN には https://www.pushbullet.com/#settings/account から取得したトークンを使用
PUSHBULLET_TOKEN=YOUR_ACCESS_TOKEN

# ツイート用のハッシュタグを必要に応じて変えてください
TWEET_TAG="madokaBuild"

# 実行時の引数が正しいかチェック
if [ $# -lt 2 ]; then
	echo "指定された引数は$#個です。" 1>&2
	echo "仕様: $CMDNAME [ビルドディレクトリ] [ターゲット] [-t] [-s] [-c]" 1>&2
	echo "ツイートは-t、repo syncは-s、make cleanは-cを指定してください。" 1>&2
	echo "ログは自動的に記録されます。" 1>&2
	exit 1
fi

builddir=$1
device=$2
shift 2

while getopts :tsc argument; do
case $argument in
	t) tweet=true ;;
	s) sync=true ;;
	c) clean=true ;;
	*) echo "正しくない引数が指定されました。" 1>&2
	   exit 1 ;;
esac
done

cd ../$builddir

# repo sync
if [ "$sync" = "true" ]; then
	repo sync -j8 -c -f --force-sync --no-clone-bundle
	echo -e "\n"
fi

# make clean
if [ "$clean" = "true" ]; then
	make clean
	echo -e "\n"
fi

# 現在日時取得、ログのファイル名設定
# CMやRRの場合、吐き出すzipのファイル名はUTC基準での日付なので注意
starttime=$(date '+%Y/%m/%d %T')
filetime=$(date -u '+%Y%m%d_%H%M%S')
filename="${filetime}_${builddir}_${device}.log"

# いつもの
source build/envsetup.sh
breakfast $device

# ディレクトリ名からツイート用のROM情報の設定をする
if [ $builddir = cm13 ]; then
	source="CyanogenMod 13.0"
	short="CM13"
	zipname="cm-$(get_build_var CM_VERSION)"
	newzipname="cm-$(get_build_var PRODUCT_VERSION_MAJOR).$(get_build_var PRODUCT_VERSION_MINOR)-${filetime}-$(CM_BUILDTYPE)-$(get_build_var CM_BUILD)"

elif [ $builddir = rr ]; then
	vernum=$(get_build_var PRODUCT_VERSION)
	source="ResurrectionRemix v${vernum}"
	short="RR v${vernum}"
	zipname="$(get_build_var CM_VERSION)"
	newzipname="ResurrectionRemix-M-v$(get_build_var PRODUCT_VERSION)-${filetime}-$(get_build_var CM_BUILD)"

else
# 一応対処するけど他ROMについては上記を参考にちゃんと書いてもらわないと後がめんどい
	source=$builddir
	short="${source}"
	zipname="*"
	newzipname="${zipname}"
fi

# 開始時のツイート
if [ "$tweet" = "true" ]; then
	twstart=$(echo -e "${device} 向け ${source} のビルドを開始します。 \n\n$starttime #${TWEET_TAG}")
	perl ~/oysttyer/oysttyer.pl -ssl -status="$twstart"
fi

# ビルド
mka bacon 2>&1 | tee "../log/$filename"

if [ $(echo ${PIPESTATUS[0]}) -eq 0 ]; then
	ans=1
	statusdir="success"
	endstr=$(tail -n 3 "../log/$filename" | tr -d '\n' | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' | sed 's/#//g' | sed 's/make completed successfully//g' | sed 's/^[ ]*//g')
	statustw="${zipname} のビルドに成功しました！"
else
	ans=0
	statusdir="fail"
	endstr=$(tail -n 3 "../log/$filename" | tr -d '\n' | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' | sed 's/#//g' | sed 's/make failed to build some targets//g' | sed 's/^[ ]*//g')
	statustw="${device} 向け ${source} のビルドに失敗しました…"
fi

cd ..

echo -e "\n"

# 結果のツイート
if [ "$tweet" = "true" ]; then
	endtime=$(date '+%Y/%m/%d %H:%M:%S')
	twfinish=$(echo -e "$statustw\n\n$endstr\n\n$endtime #${TWEET_TAG}")
	perl ~/oysttyer/oysttyer.pl -ssl -status="$twfinish" -autosplit=cut
fi

# Pushbullet APIを使ってプッシュ通知も投げる。文言は適当に
pbtitle=$(echo -e "${statusdir}: Build ${short} for ${device}")
pbbody=$(cat -v "log/$filename" | tail -n 3 | tr -d '\n' | cut -d "#" -f 5-5 | cut -c 2-)

curl -u ${PUSHBULLET_TOKEN}: -X POST \
  https://api.pushbullet.com/v2/pushes \
  --header "Content-Type: application/json" \
  --data-binary "{\"type\": \"note\", \"title\": \"${pbtitle}\", \"body\": \"${pbbody}\"}"

# ログ移す
mv -v log/$filename log/$statusdir/

echo -e "\n"

# ビルドが成功してればGoogle Driveに上げつつ ~/rom に移動しておく
if [ $ans -eq 1 ]; then

	# gdrive https://github.com/prasmussen/gdrive を使います
	# golang をインストールした上でREADMEの Download からバイナリ落として来る
	# 適当に ~/gdrive あたりに置いて chmod 755 gdrive
	# ~/gdrive list で初回はWebからトークン取得してフォルダのIdを取る
	# 端末ごとに振り分けたいなら以下のように機種名で振り分けて gpath にフォルダのIdを振る
	# 最低限 FOLDER_ID はきちんと設定してください
	# 用法: ~/gdrive upload -p <フォルダのId> <アップロードするファイル名>

	case $device in
		hammerhead)
			gpath="HAMMERHEAD_FOLDER_ID";;
		shamu)
			gpath="SHAMU_FOLDER_ID";;
		bullhead)
			gpath="BULLHEAD_FOLDER_ID";;
		angler)
			gpath="ANGLER_FOLDER_ID";;
		*)
			gpath="FOLDER_ID"
	esac

	mv -v $builddir/out/target/product/$device/${zipname}.zip ${newzipname}.zip
	~/gdrive upload -p $gpath ${newzipname}.zip

	mkdir -p ~/rom/$device

	mv -v ${newzipname}.zip ~/rom/$device/${newzipname}.zip
	mv -v $builddir/out/target/product/$device/${zipname}.zip.md5sum ~/rom/$device/${newzipname}.zip.md5sum

	echo -e "\n"

fi
