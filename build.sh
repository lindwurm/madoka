#!/bin/bash

# ビルド用
export LC_ALL=C.UTF-8
export ALLOW_MISSING_DEPENDENCIES=true

# 変数読み込み
if [ -f .env ]; then
	source .env
else
	echo "ERROR: 同梱のファイル .env.sample を .env の名前でコピーし、必要な設定を記入してください。" 1>&2
	exit 1
fi

# 作っとく
mkdir -p ../log/success ../log/fail ${OUTPUT_PATH}

# 実行時の引数が正しいかチェック
if [ $# -lt 2 ]; then
	echo "指定された引数は$#個です。" 1>&2
	echo "仕様: $CMDNAME [ビルドディレクトリ] [ターゲット] [オプション]" 1>&2
	echo "オプション" 1>&2
	echo "  -t: publish toot" 1>&2
	echo "  -s: repo sync " 1>&2
	echo "  -c: make clean" 1>&2
	echo "  -n: set SELINUX_IGNORE_NEVERALLOWS" 1>&2
	echo "  -d: destroy ccache (zero statics)" 1>&2
	echo "ログは自動的に記録されます。" 1>&2
	exit 1
fi

builddir=$1
device=$2
shift 2

while getopts :tscnd argument; do
case $argument in
	t) toot=true ;;
	s) sync=true ;;
	c) clean=true ;;
	n) allow_neverallow=true ;;
	d) destroy_ccache=true ;;
	*) echo "正しくない引数が指定されました。" 1>&2
	   exit 1 ;;
esac
done

cd ../$builddir

# setup ccache
if [ "$CCACHE_ENABLE" = "true" ]; then
	export USE_CCACHE=1
	export CCACHE_EXEC=/usr/bin/ccache
	mkdir -p ${CCACHE_DIR}/$builddir
	export CCACHE_DIR=${CCACHE_DIR}/$builddir

	# -d stands for destroy_ccache
	if [ "$destroy_ccache" = "true" ]; then
		ccache -C -z
		echo -e "\n"
	fi
	ccache -M 30G
fi

# repo sync
if [ "$sync" = "true" ]; then
	repo sync -j$(nproc) -c --force-sync --no-clone-bundle --no-tags
	echo -e "\n"
fi

# -n stands for SELINUX_IGNORE_NEVERALLOWS
if [ "$allow_neverallow" = "true" ]; then
	export SELINUX_IGNORE_NEVERALLOWS=true
fi

# 現在日時取得、ログのファイル名設定
starttime=$(date '+%Y/%m/%d %T')
filetime=$(date -u '+%Y%m%d_%H%M%S')
filename="${filetime}_${builddir}_${device}.log"

# いつもの
source build/envsetup.sh

# ディレクトリ名からツイート用のROM情報の設定をする
if [ $builddir = "lineage" ]; then
	breakfast $device
	vernum="$(get_build_var PRODUCT_VERSION_MAJOR).$(get_build_var PRODUCT_VERSION_MINOR)"
	source="LineageOS ${vernum}"
	short="${source}"
	zipname="lineage-$(get_build_var LINEAGE_VERSION)"
	newzipname="lineage-$(get_build_var PRODUCT_VERSION_MAJOR).$(get_build_var PRODUCT_VERSION_MINOR)-${filetime}-$(get_build_var LINEAGE_BUILDTYPE)-${device}"

elif [ $builddir = "floko" ]; then
	breakfast $device
	vernum="$(get_build_var FLOKO_VERSION)"
	source="FlokoROM v${vernum}"
	short="${source}"
	zipname="$(get_build_var LINEAGE_VERSION)"
	newzipname="Floko-v${vernum}-${device}-${filetime}-$(get_build_var FLOKO_BUILD_TYPE)"
else
	echo "Error: Please define your ROM information."
	exit 1
fi

# make clean
if [ "$clean" = "true" ]; then
	# Android 11 or later, `make clean` is deprecated.
	if [ $(get_build_var PLATFORM_VERSION) -ge 11 ]; then
		build/soong/soong_ui.bash --make-mode clean
	else
		make clean
	fi
	echo -e "\n"
fi

# 開始時の投稿
if [ "$toot" = "true" ]; then
	twstart=$(echo -e "${device} 向け ${source} のビルドを開始します。 \n\n$starttime #${TOOT_HASHTAG}")
	echo $twstart | toot --visibility ${TOOT_VISIBILITY}
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

# 結果の投稿
if [ "$toot" = "true" ]; then
	endtime=$(date '+%Y/%m/%d %H:%M:%S')
	twfinish=$(echo -e "$statustw\n\n$endstr\n\n$endtime #${TOOT_HASHTAG}")
	echo $twfinish | toot --visibility ${TOOT_VISIBILITY}
fi

# Pushbullet APIを使ってプッシュ通知も投げる。文言は適当に結果から切り出したもの
if [ "$ENABLE_PUSHBULLET" = "true" ]; then

pbtitle=$(echo -e "${statusdir}: Build ${short} for ${device}")
pbbody=$(cat -v "log/$filename" | tail -n 3 | tr -d '\n' | cut -d "#" -f 5-5 | cut -c 2-)

curl -u ${PUSHBULLET_TOKEN}: -X POST \
  https://api.pushbullet.com/v2/pushes \
  --header "Content-Type: application/json" \
  --data-binary "{\"type\": \"note\", \"title\": \"${pbtitle}\", \"body\": \"${pbbody}\"}"

fi

# ログ移す
mv -v log/$filename log/$statusdir/

echo -e "\n"

# ビルドが成功してたら
if [ $ans -eq 1 ]; then

	# よく使うので先に定義
	outdir="${builddir}/out/target/product/${device}/"

	# リネームする
	mv -v --backup=t ${outdir}/${zipname}.zip ${newzipname}.zip

	# アップローダーがあるなら device と newzipname を与えて投げてもらう
	if [ "$ENABLE_UPLOAD" = "true" ]; then
		source madoka/.env $device $newzipname
		eval $UPLOADER
	fi

	# OUTPUT_PATH で指定されたパスにデバイス名でディレクトリを作成、ファイルを移動
	mkdir -p ${OUTPUT_PATH}/$device

	mv -v ${newzipname}.zip ${OUTPUT_PATH}/${device}/${newzipname}.zip

	# Move sha256/md5 checksum
	if [ -f ${outdir}/${zipname}.zip.sha256sum ]
		mv -v ${outdir}/${zipname}.zip.sha256sum ${OUTPUT_PATH}/${device}/${newzipname}.zip.sha256sum

	else if [ -f ${outdir}/${zipname}.zip.md5sum ]; then
		mv -v ${outdir}/${zipname}.zip.md5sum ${OUTPUT_PATH}/${device}/${newzipname}.zip.md5sum
	fi

	# Move changelog if exist
	if [ -f ${outdir}/changelog_${device}.txt ]; then
		mv -v ${outdir}/changelog_${device}.txt ${OUTPUT_PATH}/${device}/changelog/${newzipname}.zip_changelog.txt
	fi

	echo -e "\n"
fi
