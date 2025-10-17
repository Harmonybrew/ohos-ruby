#!/bin/sh
set -e

alpine_repository_url="http://dl-cdn.alpinelinux.org/alpine/v3.22/main/aarch64/"

download_alpine_index() {
    mkdir -p /opt/alpine-index
    cd /opt/alpine-index/
    curl -fsSL -O "${alpine_repository_url}/APKINDEX.tar.gz"
    tar -zxf APKINDEX.tar.gz
    cd - >/dev/null
}

get_apk_url() {
    package_name=$1
    version=$(grep -A 2 "^P:${package_name}$" /opt/alpine-index/APKINDEX | grep '^V:' | sed 's/^V://')
    apk_url="${alpine_repository_url}${package_name}-${version}.apk"
    echo $apk_url
}

query_component() {
  component=$1
  curl 'https://ci.openharmony.cn/api/daily_build/build/list/component' \
    -H 'Accept: application/json, text/plain, */*' \
    -H 'Content-Type: application/json' \
    --data-raw '{"projectName":"openharmony","branch":"master","pageNum":1,"pageSize":10,"deviceLevel":"","component":"'${component}'","type":1,"startTime":"2025080100000000","endTime":"20990101235959","sortType":"","sortField":"","hardwareBoard":"","buildStatus":"success","buildFailReason":"","withDomain":1}'
}

# Setup tools
download_alpine_index
curl -L -O $(get_apk_url m4)
curl -L -O $(get_apk_url autoconf)
curl -L -O $(get_apk_url jq)
curl -L -O $(get_apk_url oniguruma)
curl -L -O $(get_apk_url busybox-static)
curl -L -O $(get_apk_url make)
for file in *.apk; do
  tar -zxf $file -C /
done
rm /bin/xargs
ln -s /bin/busybox.static /bin/xargs
ln -s /bin/busybox.static /bin/tr
ln -s /bin/busybox.static /bin/expr
ln -s /bin/busybox.static /bin/awk
ln -s /bin/busybox.static /bin/unzip
ln -s /bin/busybox.static /bin/fold

# Setup ohos-sdk
sdk_ohos_download_url=$(query_component "ohos-sdk-public_ohos" | jq -r ".data.list.dataList[0].obsPath")
curl $sdk_ohos_download_url -o ohos-sdk-public_ohos.tar.gz
mkdir /opt/ohos-sdk
tar -zxf ohos-sdk-public_ohos.tar.gz -C /opt/ohos-sdk
cd /opt/ohos-sdk/ohos/
unzip -q native-*.zip
unzip -q toolchains-*.zip
cd - >/dev/null

# Setup deps
tar -zxf openssl-3.3.4-ohos-arm64.tar.gz -C /opt
tar -zxf yaml-0.2.5-ohos-arm64.tar.gz -C /opt
tar -zxf zlib-1.3.1-ohos-arm64.tar.gz -C /opt
tar -zxf libffi-3.4.5-ohos-arm64.tar.gz -C /opt

# Setup env 
export OHOS_SDK=/opt/ohos-sdk/ohos
export AS=${OHOS_SDK}/native/llvm/bin/llvm-as
export CC=${OHOS_SDK}/native/llvm/bin/clang
export CXX=${OHOS_SDK}/native/llvm/bin/clang++
export LD=${OHOS_SDK}/native/llvm/bin/ld.lld
export STRIP=${OHOS_SDK}/native/llvm/bin/llvm-strip
export RANLIB=${OHOS_SDK}/native/llvm/bin/llvm-ranlib
export OBJDUMP=${OHOS_SDK}/native/llvm/bin/llvm-objdump
export OBJCOPY=${OHOS_SDK}/native/llvm/bin/llvm-objcopy
export NM=${OHOS_SDK}/native/llvm/bin/llvm-nm
export AR=${OHOS_SDK}/native/llvm/bin/llvm-ar
export CFLAGS="-fPIC -D__MUSL__=1"
export CXXFLAGS="-fPIC -D__MUSL__=1"

# Build perl (autoconf depends on perl)
curl -L https://github.com/Perl/perl5/archive/refs/tags/v5.42.0.tar.gz -o perl5-5.42.0.tar.gz
tar -zxf perl5-5.42.0.tar.gz
cd perl5-5.42.0
sed -i 's/defined(__ANDROID__)/defined(__ANDROID__) || defined(__OHOS__)/g' perl_langinfo.h
./Configure \
    -des \
    -Dprefix=/ \
    -Dcc=$CC \
    -Dcpp=$CXX \
    -Dar=$AR \
    -Dnm=$NM \
    -Accflags=-D_GNU_SOURCE
make -j$(nproc)
make install
cd ..

# Build ruby
curl -L -O https://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.5.tar.gz
tar -zxf ruby-3.4.5.tar.gz
cd ruby-3.4.5
patch -p1 < ../0001-add-target-os.patch
patch -p1 < ../0002-change-variable-name.patch
autoconf
./configure \
  --prefix=/opt/ruby-3.4.5-ohos-arm64 \
  --host=aarch64-linux \
  --enable-load-relative \
  --with-static-linked-ext \
  --disable-install-doc \
  --disable-install-rdoc \
  --disable-install-capi \
  --with-opt-dir=/opt/openssl-3.3.4-ohos-arm64:/opt/yaml-0.2.5-ohos-arm64:/opt/zlib-1.3.1-ohos-arm64:/opt/libffi-3.4.5-ohos-arm64
make -j$(nproc)
make install

# Codesign
/opt/ohos-sdk/ohos/toolchains/lib/binary-sign-tool sign -inFile /opt/ruby-3.4.5-ohos-arm64/bin/ruby -outFile /opt/ruby-3.4.5-ohos-arm64/bin/ruby -selfSign 1
find /opt/ruby-3.4.5-ohos-arm64/lib/ -type f | grep -E '\.so(\.[0-9]+)*$' | xargs -I {} /opt/ohos-sdk/ohos/toolchains/lib/binary-sign-tool sign -inFile {} -outFile {} -selfSign 1

cp COPYING /opt/ruby-3.4.5-ohos-arm64/

cd /opt
tar -zcf ruby-3.4.5-ohos-arm64.tar.gz ruby-3.4.5-ohos-arm64
