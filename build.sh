#!/bin/sh
set -e

# 如果存在旧的目录和文件，就清理掉
# 仅清理工作目录，不清理系统目录，因为默认用户每次使用新的容器进行构建（仓库中的构建指南是这么指导的）
rm -rf *.tar.gz \
    openssl-3.3.4 \
    yaml-0.2.5 \
    zlib-1.3.1 \
    libffi-3.4.5 \
    ruby-3.4.5 \
    ruby-3.4.5-ohos-arm64

# 准备一些杂项的命令行工具
curl -L -O https://github.com/Harmonybrew/ohos-coreutils/releases/download/9.9/coreutils-9.9-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-grep/releases/download/3.12/grep-3.12-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-gawk/releases/download/5.3.2/gawk-5.3.2-ohos-arm64.tar.gz
tar -zxf coreutils-9.9-ohos-arm64.tar.gz -C /opt
tar -zxf grep-3.12-ohos-arm64.tar.gz -C /opt
tar -zxf gawk-5.3.2-ohos-arm64.tar.gz -C /opt

# 准备鸿蒙版 llvm、make、m4、perl、autoconf
curl -L -O https://github.com/Harmonybrew/ohos-llvm/releases/download/20251121/llvm-21.1.5-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-make/releases/download/4.4.1/make-4.4.1-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-m4/releases/download/1.4.20/m4-1.4.20-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-perl/releases/download/5.42.0/perl-5.42.0-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-autoconf/releases/download/2.72/autoconf-2.72-ohos-arm64.tar.gz
tar -zxf llvm-21.1.5-ohos-arm64.tar.gz -C /opt
tar -zxf make-4.4.1-ohos-arm64.tar.gz -C /opt
tar -zxf m4-1.4.20-ohos-arm64.tar.gz -C /opt
tar -zxf perl-5.42.0-ohos-arm64.tar.gz -C /opt
tar -zxf autoconf-2.72-ohos-arm64.tar.gz -C /opt

# 设置环境变量
export PATH=/opt/coreutils-9.9-ohos-arm64/bin:$PATH
export PATH=/opt/grep-3.12-ohos-arm64/bin:$PATH
export PATH=/opt/gawk-5.3.2-ohos-arm64/bin:$PATH
export PATH=/opt/llvm-21.1.5-ohos-arm64/bin:$PATH
export PATH=/opt/make-4.4.1-ohos-arm64/bin:$PATH
export PATH=/opt/m4-1.4.20-ohos-arm64/bin:$PATH
export PATH=/opt/perl-5.42.0-ohos-arm64/bin:$PATH
export PATH=/opt/autoconf-2.72-ohos-arm64/bin:$PATH
export CC=clang
export CXX=clang++
export LD=ld.lld
export NM=llvm-nm
export AR=llvm-ar

# 编译 openssl
curl -L -O https://github.com/openssl/openssl/releases/download/openssl-3.3.4/openssl-3.3.4.tar.gz
tar zxf openssl-3.3.4.tar.gz
cd openssl-3.3.4
sed -i "s/SSL_CERT_FILE/PORTABLE_RUBY_SSL_CERT_FILE/g" include/internal/common.h
./Configure --prefix=/opt/openssl-3.3.4-ohos-arm64 --openssldir=/etc/ssl no-legacy no-module no-shared no-engine linux-aarch64
make -j$(nproc)
make install_dev
cd ..

# 编译 yaml
curl -L -O https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz
tar zxf yaml-0.2.5.tar.gz
cd yaml-0.2.5
./configure --prefix=/opt/yaml-0.2.5-ohos-arm64 --disable-dependency-tracking --enable-static --disable-shared --host=aarch64-linux
make -j$(nproc)
make install
cd ..

# 编译 zlib
curl -L -O https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
tar zxf zlib-1.3.1.tar.gz
cd zlib-1.3.1
./configure --prefix=/opt/zlib-1.3.1-ohos-arm64 --static
make -j$(nproc)
make install
cd ..

# 编译 libffi
curl -L -O https://github.com/libffi/libffi/releases/download/v3.4.5/libffi-3.4.5.tar.gz
tar zxf libffi-3.4.5.tar.gz
cd libffi-3.4.5
./configure --prefix=/opt/libffi-3.4.5-ohos-arm64 --enable-static --disable-shared --disable-docs --host=aarch64-linux
make -j$(nproc)
make install
cd ..

# 编译 ruby
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
cd ..

# 履行开源义务，把使用的开源软件的 license 全部聚合起来放到制品中
ruby_license=$(cat ruby-3.4.5/COPYING; echo)
openssl_license=$(cat openssl-3.3.4/LICENSE.txt; echo)
openssl_authors=$(cat openssl-3.3.4/AUTHORS.md; echo)
yaml_license=$(cat yaml-0.2.5/License; echo)
zlib_license=$(cat zlib-1.3.1/LICENSE; echo)
libffi_license=$(cat libffi-3.4.5/LICENSE; echo)
printf '%s\n' "$(cat <<EOF
This document describes the licenses of all software distributed with the
bundled application.
==========================================================================

ruby
=============
$ruby_license

openssl
=============
==license==
$openssl_license
==authors==
$openssl_authors

LibYAML
=============
$yaml_license

zlib
=============
$zlib_license

libffi
=============
$libffi_license
EOF
)" > /opt/ruby-3.4.5-ohos-arm64/licenses.txt

# 打包最终产物
cp -r /opt/ruby-3.4.5-ohos-arm64 ./
tar -zcf ruby-3.4.5-ohos-arm64.tar.gz ruby-3.4.5-ohos-arm64

# 这一步是针对手动构建场景做优化。
# 在 docker run --rm -it 的用法下，有可能文件还没落盘，容器就已经退出并被删除，从而导致压缩文件损坏。
# 使用 sync 命令强制让文件落盘，可以避免那种情况的发生。
sync
