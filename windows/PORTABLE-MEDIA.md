# Corresponding source for the Windows media tools

ShotMap invokes the bundled FFmpeg and ffprobe as separate programs. They use shared FFmpeg libraries under LGPL 2.1 or later. The media tools contain libwebp and zlib. Their notices are included beside the app and in the original source archives.

The [Windows preview release](https://github.com/ixiehao/ShotMap/releases/tag/windows-v0.1.0-preview.2) provides the exact source archives, build script and FFmpeg configuration alongside the binary ZIP.

| Component | Source archive |
| --- | --- |
| FFmpeg 9.1 | [ffmpeg-9.1.tar.xz](https://ffmpeg.org/releases/ffmpeg-9.1.tar.xz) |
| libwebp 1.6.0 | [libwebp-1.6.0.tar.gz](https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz) |
| zlib 1.4 | [zlib-1.4.tar.gz](https://zlib.net/zlib-1.4.tar.gz) |

To rebuild, install Visual Studio Build Tools with the x64 C++ tools, Windows SDK and LLVM. Start an x64 Developer Command Prompt and make Bash, GNU Make, CMake, Ninja, NASM, pkg-config, clang-cl, llvm-lib and LLD available on PATH. Extract the three source archives into one directory, run Bash in that directory, and execute `bash /path/to/Build-PortableMedia.sh`. The script builds the source trees and places the media executables and DLLs in `portable/bin`. Copy the rebuilt files to the application's `ffmpeg/bin` directory to replace the matching media build.

The bundled media tools are built for ShotMap. They provide the file readers, video decoders, frame filters and WebP encoder that ShotMap uses.
