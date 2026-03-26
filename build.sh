#!/bin/sh
set -e

WORKDIR=$(pwd)

# 如果存在旧的目录和文件，就清理掉
# 仅清理工作目录，不清理系统目录，因为默认用户每次使用新的容器进行构建（仓库中的构建指南是这么指导的）
rm -rf *.tar.gz \
    deps \
    ruby-4.0.1 \
    ruby-4.0.1-ohos-arm64

# 下载一些命令行工具，并将它们软链接到 bin 目录中
cd /opt
echo "coreutils 9.10
busybox 1.37.0
grep 3.12
gawk 5.3.2
make 4.4.1
tar 1.35
gzip 1.14
m4 1.4.20
perl 5.42.0
autoconf 2.72" >/tmp/tools.txt
while read -r name ver; do
    curl -fLO https://github.com/Harmonybrew/ohos-$name/releases/download/$ver/$name-$ver-ohos-arm64.tar.gz
done </tmp/tools.txt
ls | grep tar.gz$ | xargs -n 1 tar -zxf
rm -rf *.tar.gz
ln -sf $(pwd)/*-ohos-arm64/bin/* /bin/

# 准备 ohos-sdk
echo "192.168.0.119 cidownload.openharmony.cn" > /etc/hosts
curl -fL -o ohos-sdk-full_6.1-Release.tar.gz http://cidownload.openharmony.cn/version/Master_Version/OpenHarmony_6.1.0.31/20260311_020435/version-Master_Version-OpenHarmony_6.1.0.31-20260311_020435-ohos-sdk-full_6.1-Release.tar.gz
tar -zxf ohos-sdk-full_6.1-Release.tar.gz
rm -rf ohos-sdk-full_6.1-Release.tar.gz ohos-sdk/windows ohos-sdk/linux
cd ohos-sdk/ohos
busybox unzip -q native-*.zip
busybox unzip -q toolchains-*.zip
rm -rf *.zip
cd $WORKDIR

# 把 llvm 里面的命令封装一份放到 /bin 目录下，只封装必要的工具。
# 为了照顾 clang （clang 软链接到其他目录使用会找不到 sysroot），
# 对所有命令统一用这种封装的方案，而非软链接。
essential_tools="clang
clang++
clang-cpp
ld.lld
lldb
llvm-addr2line
llvm-ar
llvm-cxxfilt
llvm-nm
llvm-objcopy
llvm-objdump
llvm-ranlib
llvm-readelf
llvm-size
llvm-strings
llvm-strip"
for executable in $essential_tools; do
    cat <<EOF > /bin/$executable
#!/bin/sh
exec /opt/ohos-sdk/ohos/native/llvm/bin/$executable "\$@"
EOF
    chmod 0755 /bin/$executable
done

# 把 llvm 软链接成 cc、gcc 等命令
cd /bin
ln -s clang cc
ln -s clang gcc
ln -s clang++ c++
ln -s clang++ g++
ln -s ld.lld ld
ln -s llvm-addr2line addr2line
ln -s llvm-ar ar
ln -s llvm-cxxfilt c++filt
ln -s llvm-nm nm
ln -s llvm-objcopy objcopy
ln -s llvm-objdump objdump
ln -s llvm-ranlib ranlib
ln -s llvm-readelf readelf
ln -s llvm-size size
ln -s llvm-strip strip

mkdir $WORKDIR/deps
cd $WORKDIR/deps

# 编译 openssl
curl -fLO https://github.com/openssl/openssl/releases/download/openssl-3.6.1/openssl-3.6.1.tar.gz
tar zxf openssl-3.6.1.tar.gz
cd openssl-3.6.1
# 修改证书目录和聚合文件路径，让它能在 OpenHarmony 平台上正确地找到证书
sed -i 's|OPENSSLDIR "/certs"|"/etc/ssl/certs"|' include/internal/common.h
sed -i 's|OPENSSLDIR "/cert.pem"|"/etc/ssl/certs/cacert.pem"|' include/internal/common.h
./Configure --prefix=/opt/deps --openssldir=/etc/ssl no-legacy no-module no-shared no-engine linux-aarch64
make -j$(nproc)
make install_dev
cd ..

# 编译 yaml
curl -fLO https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz
tar zxf yaml-0.2.5.tar.gz
cd yaml-0.2.5
./configure --prefix=/opt/deps --disable-dependency-tracking --enable-static --disable-shared
make -j$(nproc)
make install
cd ..

# 编译 zlib
curl -fLO https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
tar zxf zlib-1.3.1.tar.gz
cd zlib-1.3.1
./configure --prefix=/opt/deps --static
make -j$(nproc)
make install
cd ..

# 编译 libffi
curl -fLO https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz
tar zxf libffi-3.5.2.tar.gz
cd libffi-3.5.2
./configure --prefix=/opt/deps --enable-static --disable-shared --disable-docs
make -j$(nproc)
make install
cd ..

cd $WORKDIR

# 编译 ruby
#
# 注意：以下两个编译参数对于 OHOS (AArch64/musl) 环境下的稳定性至关重要：
# 1. --with-coroutine=pthread
#    显式使用 pthread 实现协程切换。
#    原因：默认的 AArch64 汇编实现（context.S）在 OHOS 的 musl libc 环境下
#    可能无法正确处理 PAC (Pointer Authentication Code) 机制或 BTI 保护，
#    且容易因手动操作栈指针而产生非对齐访问。使用 pthread 可由 libc 保证上下文切换的安全性。
#
# 2. ac_cv_func_sigaltstack=no
#    禁用备用信号栈 (sigaltstack)，强制 Ruby 使用主栈处理信号。
#    原因：Ruby 的保守式 GC (Conservative GC) 会扫描栈空间。在 OHOS 的 musl libc 环境下，
#    Ruby 默认通过 malloc 分配的信号栈可能仅满足 8 字节对齐，而 AArch64 信号帧 (ucontext_t)
#    在压栈时要求严格的 16 字节对齐。这种偏差（4 字节错位）会导致 GC 在扫描栈时
#    将非指针数据误认为有效地址并解引用，从而引发段错误。
#    由于 OHOS 线程主栈通常为 8MB，足以承载信号处理，禁用 sigaltstack 可消除此类对齐歧义。
curl -fLO https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.1.tar.gz
tar -zxf ruby-4.0.1.tar.gz
cd ruby-4.0.1
patch -p1 < ../0001-add-target-os.patch
patch -p1 < ../0002-implement-pthread_cancel-stub.patch
autoconf
./configure \
  --prefix=/opt/ruby-4.0.1-ohos-arm64 \
  --host=aarch64-linux \
  --enable-load-relative \
  --with-static-linked-ext \
  --disable-install-doc \
  --disable-install-rdoc \
  --disable-install-capi \
  --with-coroutine=pthread \
  --with-opt-dir=/opt/deps \
  ac_cv_func_sigaltstack=no
make -j$(nproc)
make install
cd ..

# 进行代码签名
cd /opt/ruby-4.0.1-ohos-arm64
find . -type f \( -perm -0111 -o -name "*.so*" \) | while read FILE; do
    if file -b "$FILE" | grep -iqE "elf|sharedlib|ELF|shared object"; then
        echo "Signing binary file $FILE"
        ORIG_PERM=$(stat -c %a "$FILE")
        /opt/ohos-sdk/ohos/toolchains/lib/binary-sign-tool sign -inFile "$FILE" -outFile "$FILE" -selfSign 1
        chmod "$ORIG_PERM" "$FILE"
    fi
done
cd $WORKDIR

# 履行开源义务，把使用的开源软件的 license 全部聚合起来放到制品中
cat <<EOF > /opt/ruby-4.0.1-ohos-arm64/licenses.txt
This document describes the licenses of all software distributed with the
bundled application.
==========================================================================

ruby
=============
$(cat ruby-4.0.1/COPYING)

openssl
=============
$(cat deps/openssl-3.6.1/LICENSE.txt)
$(cat deps/openssl-3.6.1/AUTHORS.md)

LibYAML
=============
$(cat deps/yaml-0.2.5/License)

zlib
=============
$(cat deps/zlib-1.3.1/LICENSE)

libffi
=============
$(cat deps/libffi-3.5.2/LICENSE)
EOF

# 打包最终产物
cp -r /opt/ruby-4.0.1-ohos-arm64 ./
tar -zcf ruby-4.0.1-ohos-arm64.tar.gz ruby-4.0.1-ohos-arm64

# 这一步是针对手动构建场景做优化。
# 在 docker run --rm -it 的用法下，有可能文件还没落盘，容器就已经退出并被删除，从而导致压缩文件损坏。
# 使用 sync 命令强制让文件落盘，可以避免那种情况的发生。
sync
