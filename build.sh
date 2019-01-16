#!/bin/bash

# ビルド用
export LANG=C
export LC_ALL=C.UTF-8
export ALLOW_MISSING_DEPENDENCIES=true
export SOONG_ALLOW_MISSING_DEPENDENCIES=true
export CCACHE_DIR=~/ccache
export USE_CCACHE=1

# 作っとく
mkdir -p ../log/success ../log/fail ~/rom

# YOUR_ACCESS_TOKEN には https://www.pushbullet.com/#settings/account から取得したトークンを使用
PUSHBULLET_TOKEN=YOUR_ACCESS_TOKEN

# ツイート用のハッシュタグを必要に応じて変えてください
TWEET_TAG="madokaBuild"

# 実行時の引数が正しいかチェック
if [ $# -lt 2 ]; then
	echo "指定された引数は$#個です。" 1>&2
	echo "仕様: $CMDNAME [ビルドディレクトリ] [ターゲット] [-t] [-s] [-c] [-x]" 1>&2
	echo "ツイートは-t、repo syncは-s、make cleanは-c、非公開の場合は-xを指定してください。" 1>&2
	echo "ログは自動的に記録されます。" 1>&2
	exit 1
fi

builddir=$1
device=$2
shift 2

while getopts :tscx argument; do
case $argument in
	t) tweet=true ;;
	s) sync=true ;;
	c) clean=true ;;
        x) private_build=true ;;
	*) echo "正しくない引数が指定されました。" 1>&2
	   exit 1 ;;
esac
done

cd ../$builddir
prebuilts/misc/linux-x86/ccache/ccache -M 30G

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
starttime=$(date '+%Y/%m/%d %T')
filetime=$(date -u '+%Y%m%d_%H%M%S')
filename="${filetime}_${builddir}_${device}.log"

# いつもの
source build/envsetup.sh
breakfast $device

# ディレクトリ名からツイート用のROM情報の設定をする
if [ $builddir = lineage ]; then
	vernum="$(get_build_var PRODUCT_VERSION_MAJOR).$(get_build_var PRODUCT_VERSION_MINOR)"
	source="LineageOS ${vernum}"
	short="${source}"
	zipname="lineage-$(get_build_var LINEAGE_VERSION)"
	newzipname="lineage-$(get_build_var PRODUCT_VERSION_MAJOR).$(get_build_var PRODUCT_VERSION_MINOR)-${filetime}-${get_build_var LINEAGE_BUILDTYPE}-$(device)"

elif [ $builddir = aicp ]; then
	vernum="$(get_build_var AICP_BRANCH)-$(get_build_var VERSION)"
	source="AICP-${vernum}"
	short="${source}"
	zipname="$(get_build_var AICP_VERSION)"
	newzipname="aicp_${device}_${vernum}-$(get_build_var AICP_BUILDTYPE)-${filetime}"

elif [ $builddir = du ]; then
        vernum="$(get_build_var DU_BASE_VERSION)"
        source="DirtyUnicorns ${vernum}"
        short="${source}"
        zipname="$(get_build_var DU_VERSION)"
        newzipname="du_${device}_${vernum}-${filetime}-$(get_build_var DU_BUILD_TYPE)"

elif [ $builddir = floko ]; then
        vernum="$(get_build_var AICP_BRANCH)-$(get_build_var VERSION)"
        source="floko-${vernum}"
        short="${source}"
        zipname="$(get_build_var AICP_VERSION)"
        newzipname="floko_${device}_${vernum}-$(get_build_var AICP_BUILDTYPE)-${filetime}"

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
	echo $twstart | toot
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

# jack-server絶対殺すマン
prebuilts/sdk/tools/jack-admin kill-server

cd ..

echo -e "\n"

# 結果のツイート
if [ "$tweet" = "true" ]; then
	endtime=$(date '+%Y/%m/%d %H:%M:%S')
	twfinish=$(echo -e "$statustw\n\n$endstr\n\n$endtime #${TWEET_TAG}")
	perl ~/oysttyer/oysttyer.pl -ssl -status="$twfinish" -autosplit=cut
	echo $twfinish | toot
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

if [ "$private_build" = "true" ]; then
        publishdir="private/rom"
else
        publishdir="public/rom"
fi

# ビルドが成功してたら
if [ $ans -eq 1 ]; then
	# リネームする
	mv -v --backup=t $builddir/out/target/product/$device/${zipname}.zip ${newzipname}.zip

	# Nextcloud に上げる。 https://github.com/cghdev/cloud-dl 使用
	~/cloud-dl -k ${publishdir}/${device}/
	~/cloud-dl -u ${newzipname}.zip ${publishdir}/${device}/

  # ~/rom に上げる
	mkdir -p ~/rom/$device
	mv -v ${newzipname}.zip ~/rom/$device/${newzipname}.zip
	mv -v $builddir/out/target/product/$device/${zipname}.zip.md5sum ~/rom/$device/${newzipname}.zip.md5sum

	echo -e "\n"
fi
