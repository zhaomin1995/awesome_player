#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_DIR/Vendor/ffmpeg"
BUILD_DIR="/tmp/ffmpeg-build-$$"
FFMPEG_VERSION="7.1.1"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

echo "=== Building FFmpeg ${FFMPEG_VERSION} for Awesome Player ==="
echo "Output: ${VENDOR_DIR}"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "--- Downloading FFmpeg source ---"
curl -L -o "ffmpeg-${FFMPEG_VERSION}.tar.xz" "$FFMPEG_URL"
tar xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"
cd "ffmpeg-${FFMPEG_VERSION}"

echo "--- Configuring FFmpeg (minimal build for Awesome Player) ---"
./configure \
    --prefix="$VENDOR_DIR" \
    --enable-shared \
    --disable-static \
    --disable-programs \
    --disable-doc \
    --enable-videotoolbox \
    --enable-audiotoolbox \
    --disable-network \
    --enable-protocol=file \
    --enable-protocol=pipe \
    --enable-muxer=mp4 \
    --enable-muxer=adts \
    --enable-muxer=matroska \
    --disable-debug \
    --disable-postproc \
    --extra-cflags="-mmacosx-version-min=14.0" \
    --extra-ldflags="-mmacosx-version-min=14.0"

echo "--- Building FFmpeg ---"
make -j$(sysctl -n hw.ncpu)

echo "--- Installing to ${VENDOR_DIR} ---"
rm -rf "$VENDOR_DIR"
make install

echo "--- Fixing dylib install names for @rpath ---"
cd "$VENDOR_DIR/lib"
for dylib in *.dylib; do
    if [ -f "$dylib" ] && [ ! -L "$dylib" ]; then
        install_name_tool -id "@rpath/$dylib" "$dylib" 2>/dev/null || true
        # Fix cross-references between dylibs
        for dep in *.dylib; do
            if [ -f "$dep" ] && [ ! -L "$dep" ]; then
                install_name_tool -change "$VENDOR_DIR/lib/$dep" "@rpath/$dep" "$dylib" 2>/dev/null || true
            fi
        done
    fi
done

echo "--- Cleanup ---"
rm -rf "$BUILD_DIR"

echo ""
echo "=== FFmpeg build complete ==="
echo "Headers: ${VENDOR_DIR}/include/"
echo "Libs:    ${VENDOR_DIR}/lib/"
ls -la "$VENDOR_DIR/lib/"*.dylib 2>/dev/null | grep -v "\.dylib\." || true
echo ""
echo "Add to Xcode project:"
echo "  HEADER_SEARCH_PATHS = \$(PROJECT_DIR)/Vendor/ffmpeg/include"
echo "  LIBRARY_SEARCH_PATHS = \$(PROJECT_DIR)/Vendor/ffmpeg/lib"
echo "  OTHER_LDFLAGS = -lavformat -lavcodec -lavutil -lswresample -lswscale"
