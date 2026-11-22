#!/usr/bin/env bash
set -euo pipefail

# Run from an x64 Visual Studio Developer Command Prompt through Bash.
# The working directory must contain the three unpacked upstream source trees.
if [[ ! -f ffmpeg-9.1/configure || ! -f libwebp-1.6.0/CMakeLists.txt || ! -f zlib-1.4/CMakeLists.txt ]]; then
    echo "Unpack FFmpeg 9.1, libwebp 1.6.0 and zlib 1.4 in the working directory." >&2
    exit 1
fi
jobs=${BUILD_JOBS:-4}
export LC_ALL=C.UTF-8
sdk="$(cygpath -m "$PWD/deps")"
cmake_options=(
    -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
    "-DCMAKE_INSTALL_PREFIX=$sdk"
)

cmake -S zlib-1.4 -B zlib-build "${cmake_options[@]}" \
    -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON -DZLIB_BUILD_TESTING=OFF
cmake --build zlib-build --parallel "$jobs"
cmake --install zlib-build
cp deps/lib/libzs.lib deps/lib/z.lib

webp_options=()
for tool in ANIM_UTILS CWEBP DWEBP GIF2WEBP IMG2WEBP VWEBP WEBPINFO LIBWEBPMUX WEBPMUX EXTRAS; do
    webp_options+=("-DWEBP_BUILD_${tool}=OFF")
done
cmake -S libwebp-1.6.0 -B webp-build "${cmake_options[@]}" -DBUILD_SHARED_LIBS=OFF "${webp_options[@]}"
cmake --build webp-build --parallel "$jobs"
cmake --install webp-build
cp deps/lib/libwebp.lib deps/lib/webp.lib
cp deps/lib/libsharpyuv.lib deps/lib/sharpyuv.lib

mkdir -p ffmpeg-build
cd ffmpeg-build
export PKG_CONFIG_PATH="$(cygpath -m "$PWD/../deps/lib/pkgconfig")"
../ffmpeg-9.1/configure \
    --toolchain=msvc --cc=clang-cl --cxx=clang-cl --host-cc=clang-cl --ld=lld-link --ar=llvm-lib \
    --x86asmexe=nasm --pkg-config=pkg-config \
    --prefix=../portable --enable-shared --disable-static \
    --disable-gpl --disable-version3 --disable-nonfree --disable-autodetect \
    --disable-network --disable-doc --disable-ffplay --disable-avdevice --disable-hwaccels \
    --disable-encoders --enable-encoder=rawvideo,libwebp \
    --disable-muxers --enable-muxer=rawvideo,webp \
    --disable-filters \
    --enable-filter=abuffer,abuffersink,buffer,buffersink,format,hflip,null,rotate,scale,select,setsar,showinfo,transpose,trim,vflip \
    --enable-zlib --enable-libwebp --pkg-config-flags=--static \
    --extra-cflags="-MT -I../deps/include" --extra-ldflags="-libpath:../deps/lib" \
    --extra-libs=sharpyuv.lib
make -j"$jobs" install

mkdir -p ../portable/licenses
cp ../ffmpeg-9.1/COPYING.LGPLv2.1 ../portable/licenses/FFmpeg-LGPL-2.1.txt
cp ../ffmpeg-9.1/LICENSE.md ../portable/licenses/FFmpeg-LICENSE.md
cp ../libwebp-1.6.0/COPYING ../portable/licenses/libwebp-COPYING.txt
cp ../libwebp-1.6.0/PATENTS ../portable/licenses/libwebp-PATENTS.txt
cp ../zlib-1.4/LICENSE ../portable/licenses/zlib-LICENSE.txt
