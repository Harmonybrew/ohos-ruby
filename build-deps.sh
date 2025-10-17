#!/bin/sh
set -e

mkdir /opt/ohos-sdk
curl -L -O https://repo.huaweicloud.com/openharmony/os/6.0-Release/ohos-sdk-windows_linux-public.tar.gz
tar -zxf ohos-sdk-windows_linux-public.tar.gz -C /opt/ohos-sdk
cd /opt/ohos-sdk/linux
unzip -q native-*.zip
cd - >/dev/null

export OHOS_SDK=/opt/ohos-sdk/linux
export AS=${OHOS_SDK}/native/llvm/bin/llvm-as
export CC="${OHOS_SDK}/native/llvm/bin/clang --target=aarch64-linux-ohos"
export CXX="${OHOS_SDK}/native/llvm/bin/clang++ --target=aarch64-linux-ohos"
export LD=${OHOS_SDK}/native/llvm/bin/ld.lld
export STRIP=${OHOS_SDK}/native/llvm/bin/llvm-strip
export RANLIB=${OHOS_SDK}/native/llvm/bin/llvm-ranlib
export OBJDUMP=${OHOS_SDK}/native/llvm/bin/llvm-objdump
export OBJCOPY=${OHOS_SDK}/native/llvm/bin/llvm-objcopy
export NM=${OHOS_SDK}/native/llvm/bin/llvm-nm
export AR=${OHOS_SDK}/native/llvm/bin/llvm-ar
export CFLAGS="-fPIC -D__MUSL__=1"
export CXXFLAGS="-fPIC -D__MUSL__=1"

curl -L -O https://github.com/openssl/openssl/releases/download/openssl-3.3.4/openssl-3.3.4.tar.gz
tar zxf openssl-3.3.4.tar.gz
cd openssl-3.3.4
sed -i "s/SSL_CERT_FILE/PORTABLE_RUBY_SSL_CERT_FILE/g" include/internal/common.h
./Configure --prefix=/opt/openssl-3.3.4-ohos-arm64 --openssldir=/etc/ssl no-legacy no-module no-shared no-engine linux-aarch64
make -j$(nproc)
make install_dev
cd ..

curl -L -O https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz
tar zxf yaml-0.2.5.tar.gz
cd yaml-0.2.5
./configure --prefix=/opt/yaml-0.2.5-ohos-arm64 --disable-dependency-tracking --enable-static --disable-shared --host=aarch64-linux
make -j$(nproc)
make install
cd ..

curl -L -O https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
tar zxf zlib-1.3.1.tar.gz
cd zlib-1.3.1
./configure --prefix=/opt/zlib-1.3.1-ohos-arm64 --static
make -j$(nproc)
make install
cd ..

curl -L -O https://github.com/libffi/libffi/releases/download/v3.4.5/libffi-3.4.5.tar.gz
tar zxf libffi-3.4.5.tar.gz
cd libffi-3.4.5
./configure --prefix=/opt/libffi-3.4.5-ohos-arm64 --enable-static --disable-shared --disable-docs --host=aarch64-linux
make -j$(nproc)
make install
cd ..

cd /opt
tar -zcf openssl-3.3.4-ohos-arm64.tar.gz openssl-3.3.4-ohos-arm64
tar -zcf yaml-0.2.5-ohos-arm64.tar.gz yaml-0.2.5-ohos-arm64
tar -zcf zlib-1.3.1-ohos-arm64.tar.gz zlib-1.3.1-ohos-arm64
tar -zcf libffi-3.4.5-ohos-arm64.tar.gz libffi-3.4.5-ohos-arm64
