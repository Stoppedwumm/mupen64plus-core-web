#!/usr/bin/env bash
#
# Build mupen64plus (core + rsp-hle, video-rice, audio-sdl, input-sdl) for
# the web with Emscripten, producing a static site in projects/web/dist that
# can be served by any web server (e.g. Apache).
#
# Requirements: an activated emsdk (emcc, emar and llvm-nm in PATH), git,
# python3 and zip.
#
# Usage: projects/web/build.sh [path/to/rom.(z64|n64|v64|zip)]
#   The optional ROM is copied into dist/ as the game loaded by default.
#
# Environment:
#   JOBS     parallel compile jobs (default: nproc)
#   OPTFLAGS optimisation flags (default: -O3)

set -euo pipefail

WEBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COREDIR="$(cd "$WEBDIR/../.." && pwd)"
BUILDDIR="$WEBDIR/build"
DISTDIR="$WEBDIR/dist"
JOBS="${JOBS:-$(nproc)}"
OPTFLAGS="${OPTFLAGS:--O3}"

# plugin repositories and the commits this build was tested with
PLUGINS="rsp-hle video-rice audio-sdl input-sdl"
declare -A PLUGIN_REV=(
    [rsp-hle]=8a7a472a7172eb2c8725b305eae26818ed7b51a2
    [video-rice]=f0a7b9f391b0e9bc14962b114f7da1ba553060be
    [audio-sdl]=2faed1c7e62c5f292948e7cd2398c184970cf794
    [input-sdl]=842c39e89749aa3a8d02202b2afddd20b29cdfdb
)
# symbol prefix used to keep each plugin's globals apart in the single module
declare -A PLUGIN_PREFIX=(
    [rsp-hle]=rsphle_
    [video-rice]=rice_
    [audio-sdl]=audiosdl_
    [input-sdl]=inputsdl_
)

for tool in emcc emar git python3; do
    command -v "$tool" >/dev/null || { echo "error: $tool not found (activate emsdk first)" >&2; exit 1; }
done
NM="$(dirname "$(command -v emcc)")/../bin/llvm-nm"
[ -x "$NM" ] || NM="$(command -v llvm-nm || true)"
if [ -z "$NM" ] || [ ! -x "$NM" ]; then
    NM="$(em-config LLVM_ROOT)/llvm-nm"
fi

PORTS="-sUSE_SDL=2 -sUSE_ZLIB=1 -sUSE_LIBPNG=1"
COMMON_CFLAGS="$OPTFLAGS -DNDEBUG -DNO_ASM -ffast-math -fno-strict-aliasing -Wno-everything $PORTS"

mkdir -p "$BUILDDIR/src" "$BUILDDIR/obj"

# compile <src> <obj> <flags...>; skipped when the object is up to date
compile() {
    local src="$1" obj="$2"; shift 2
    if [ "$obj" -nt "$src" ] && [ -z "${FORCE:-}" ]; then return 0; fi
    mkdir -p "$(dirname "$obj")"
    case "$src" in
        *.cpp) em++ -std=gnu++14 "$@" -c "$src" -o "$obj" ;;
        *)     emcc -std=gnu11 "$@" -c "$src" -o "$obj" ;;
    esac
}
export -f compile

# compile_all <objdir> <srcroot> <flags> <sources...>
compile_all() {
    local objdir="$1" srcroot="$2" flags="$3"; shift 3
    local s
    # rebuild everything in objdir when the flags change
    if [ "$(cat "$objdir/.flags" 2>/dev/null)" != "$flags" ]; then
        rm -rf "$objdir" && mkdir -p "$objdir" && printf '%s' "$flags" > "$objdir/.flags"
    fi
    for s in "$@"; do
        printf '%s\0%s\0' "$srcroot/$s" "$objdir/${s%.*}.o"
    done | xargs -0 -n 2 -P "$JOBS" bash -c 'FORCE="'"${FORCE:-}"'" compile "$0" "$1" '"$flags"
}

###########################################################################
# plugin sources
###########################################################################
for p in $PLUGINS; do
    dir="$BUILDDIR/src/$p"
    if [ ! -d "$dir/.git" ]; then
        git clone -q "https://github.com/mupen64plus/mupen64plus-$p.git" "$dir"
    fi
    if [ "$(git -C "$dir" rev-parse HEAD)" != "${PLUGIN_REV[$p]}" ]; then
        git -C "$dir" fetch -q origin "${PLUGIN_REV[$p]}" 2>/dev/null || git -C "$dir" fetch -q origin
        git -C "$dir" checkout -q "${PLUGIN_REV[$p]}"
    fi
    # small web-specific fixes, kept in projects/web/patches/<plugin>.patch
    patch="$WEBDIR/patches/$p.patch"
    if [ -f "$patch" ] && ! git -C "$dir" apply --reverse --check "$patch" 2>/dev/null; then
        git -C "$dir" apply "$patch"
    fi
done

###########################################################################
# core
###########################################################################
CORE_SOURCES="
    src/api/callbacks.c src/api/common.c src/api/config.c src/api/debugger.c
    src/api/frontend.c src/api/vidext.c
    src/backends/api/video_capture_backend.c
    src/backends/plugins_compat/audio_plugin_compat.c
    src/backends/plugins_compat/input_plugin_compat.c
    src/backends/clock_ctime_plus_delta.c src/backends/dummy_video_capture.c
    src/backends/file_storage.c
    src/device/cart/cart.c src/device/cart/af_rtc.c src/device/cart/cart_rom.c
    src/device/cart/eeprom.c src/device/cart/flashram.c src/device/cart/is_viewer.c
    src/device/cart/sram.c
    src/device/controllers/game_controller.c src/device/controllers/vru_controller.c
    src/device/controllers/paks/biopak.c src/device/controllers/paks/mempak.c
    src/device/controllers/paks/rumblepak.c src/device/controllers/paks/transferpak.c
    src/device/dd/dd_controller.c src/device/dd/disk.c src/device/device.c
    src/device/gb/gb_cart.c src/device/gb/mbc3_rtc.c src/device/gb/m64282fp.c
    src/device/memory/memory.c
    src/device/pif/bootrom_hle.c src/device/pif/cic.c src/device/pif/n64_cic_nus_6105.c
    src/device/pif/pif.c
    src/device/r4300/cached_interp.c src/device/r4300/cp0.c src/device/r4300/cp1.c
    src/device/r4300/cp2.c src/device/r4300/idec.c src/device/r4300/interrupt.c
    src/device/r4300/pure_interp.c src/device/r4300/r4300_core.c src/device/r4300/tlb.c
    src/device/rcp/ai/ai_controller.c src/device/rcp/mi/mi_controller.c
    src/device/rcp/pi/pi_controller.c src/device/rcp/rdp/fb.c
    src/device/rcp/rdp/rdp_core.c src/device/rcp/ri/ri_controller.c
    src/device/rcp/rsp/rsp_core.c src/device/rcp/si/si_controller.c
    src/device/rcp/vi/vi_controller.c src/device/rdram/rdram.c
    src/main/main.c src/main/util.c src/main/cheat.c src/main/eventloop.c
    src/main/rom.c src/main/savestates.c src/main/screenshot.c
    src/main/sdl_key_converter.c
    src/plugin/plugin.c src/plugin/dummy_video.c src/plugin/dummy_audio.c
    src/plugin/dummy_input.c src/plugin/dummy_rsp.c
    src/osal/dynamiclib_emscripten.c src/osal/files_unix.c
    subprojects/minizip/ioapi.c subprojects/minizip/zip.c subprojects/minizip/unzip.c
    subprojects/md5/md5.c
"
CORE_CFLAGS="$COMMON_CFLAGS -DUSE_GLES -DNO_ASM -DNOCRYPT -DNOUNCRYPT -I$COREDIR/src -I$COREDIR/src/asm_defines \
    -I$COREDIR/subprojects -I$COREDIR/subprojects/md5 -I$COREDIR/subprojects/xxhash"

echo "==> core"
compile_all "$BUILDDIR/obj/core" "$COREDIR" "$CORE_CFLAGS" $CORE_SOURCES
CORE_OBJS=""
for s in $CORE_SOURCES; do CORE_OBJS="$CORE_OBJS $BUILDDIR/obj/core/${s%.*}.o"; done

###########################################################################
# plugins
###########################################################################
plugin_sources() {
    case "$1" in
        rsp-hle) echo "src/alist.c src/alist_audio.c src/alist_naudio.c src/alist_nead.c
                       src/audio.c src/cicx105.c src/hle.c src/hvqm.c src/jpeg.c src/memory.c
                       src/mp3.c src/musyx.c src/re2.c src/plugin.c" ;;
        video-rice) echo "src/liblinux/BMGImage.c src/liblinux/BMGUtils.c src/liblinux/bmp.c
                       src/liblinux/pngrw.c src/Blender.cpp src/Combiner.cpp src/Config.cpp
                       src/ConvertImage.cpp src/ConvertImage16.cpp src/Debugger.cpp
                       src/DeviceBuilder.cpp src/FrameBuffer.cpp src/GraphicsContext.cpp
                       src/OGLCombiner.cpp src/OGLExtensions.cpp src/OGLGraphicsContext.cpp
                       src/OGLRender.cpp src/OGLRenderExt.cpp src/OGLTexture.cpp src/Render.cpp
                       src/RenderBase.cpp src/RenderExt.cpp src/RenderTexture.cpp
                       src/RSP_Parser.cpp src/RSP_S2DEX.cpp src/Texture.cpp src/TextureFilters.cpp
                       src/TextureFilters_2xsai.cpp src/TextureFilters_hq2x.cpp
                       src/TextureFilters_hq4x.cpp src/TextureManager.cpp src/VectorMath.cpp
                       src/Video.cpp src/osal_files_unix.c" ;;
        audio-sdl) echo "src/circular_buffer.c src/main.c src/sdl_backend.c src/resamplers/resamplers.c
                       src/resamplers/trivial.c" ;;
        input-sdl) echo "src/plugin.c src/autoconfig.c src/config.c src/sdl_key_converter.c" ;;
    esac
}
plugin_cflags() {
    case "$1" in
        video-rice) echo "-DUSE_GLES -fno-strict-aliasing" ;;
        input-sdl)  echo "-D_GNU_SOURCE=1" ;;
    esac
}

PLUGIN_OBJS=""
for p in $PLUGINS; do
    echo "==> $p"
    dir="$BUILDDIR/src/$p"
    srcs="$(plugin_sources "$p")"
    flags="$COMMON_CFLAGS -I$dir/src -I$COREDIR/src/api $(plugin_cflags "$p")"
    rename="$BUILDDIR/obj/$p/rename.h"

    # Pass 1: find every global symbol the plugin defines. All plugins
    # export the same entry points (PluginStartup, RomOpen, ...) and often
    # the same helper globals, so they are renamed with a per-plugin prefix
    # in pass 2. osal_dynlib_getproc is left alone so the plugins share the
    # core's static symbol lookup instead of dlsym().
    compile_all "$BUILDDIR/obj/$p/pass1" "$dir" "$flags" $srcs
    objs=""
    for s in $srcs; do objs="$objs $BUILDDIR/obj/$p/pass1/${s%.*}.o"; done
    "$NM" --defined-only --extern-only --format=just-symbols $objs \
        | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | grep -v -E '^(_Z|__|osal_dynlib_getproc$)' \
        | sort -u | sed "s/.*/#define & ${PLUGIN_PREFIX[$p]}&/" > "$rename.tmp"
    if ! cmp -s "$rename.tmp" "$rename"; then
        mv "$rename.tmp" "$rename"
        rm -rf "$BUILDDIR/obj/$p/pass2"
    fi
    rm -f "$rename.tmp"
    compile_all "$BUILDDIR/obj/$p/pass2" "$dir" "$flags -include $rename" $srcs
    for s in $srcs; do PLUGIN_OBJS="$PLUGIN_OBJS $BUILDDIR/obj/$p/pass2/${s%.*}.o"; done
done

###########################################################################
# frontend
###########################################################################
echo "==> frontend"
python3 "$WEBDIR/gen_plugin_tables.py" "$COREDIR/src/api" "$BUILDDIR/obj/plugin_tables.c" \
    $(for p in $PLUGINS; do echo "$p:${PLUGIN_PREFIX[$p]}:$BUILDDIR/obj/$p/rename.h"; done)
FRONTEND_CFLAGS="$COMMON_CFLAGS -I$COREDIR/src -I$COREDIR/src/api -I$COREDIR/subprojects -DNOCRYPT -DNOUNCRYPT"
compile "$BUILDDIR/obj/plugin_tables.c" "$BUILDDIR/obj/plugin_tables.o" $FRONTEND_CFLAGS
FORCE=1 compile "$WEBDIR/frontend/main.c" "$BUILDDIR/obj/frontend/main.o" $FRONTEND_CFLAGS

###########################################################################
# data files and link
###########################################################################
rm -rf "$BUILDDIR/data" && mkdir -p "$BUILDDIR/data"
cp "$COREDIR/data/mupen64plus.ini" "$BUILDDIR/data/"
cp "$BUILDDIR/src/video-rice/data/RiceVideoLinux.ini" "$BUILDDIR/data/"
# our sections ([Keyboard] layout, standard gamepads) replace the stock ones
{
    cat "$WEBDIR/frontend/InputAutoCfg-web.ini"
    awk '/^\[/ { skip = ($0 == "[Keyboard]") } !skip' "$BUILDDIR/src/input-sdl/data/InputAutoCfg.ini"
} > "$BUILDDIR/data/InputAutoCfg.ini"

# link <output.js> <flags...>
link() {
    local out="$1"; shift
    em++ $OPTFLAGS $PORTS \
        $CORE_OBJS $PLUGIN_OBJS "$BUILDDIR/obj/plugin_tables.o" "$BUILDDIR/obj/frontend/main.o" \
        -o "$out" --profiling-funcs ${LDFLAGS:-} "$@" \
        -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=134217728 -sSTACK_SIZE=1048576 \
        -sMODULARIZE=1 -sEXPORT_NAME=createMupen64Plus \
        -sMIN_WEBGL_VERSION=1 -sMAX_WEBGL_VERSION=2 -sFULL_ES2=1 \
        -sEXPORTED_RUNTIME_METHODS=FS,IDBFS,callMain -sINVOKE_RUN=0 -sEXIT_RUNTIME=0 \
        -sEXPORTED_FUNCTIONS=_main,_web_save_state,_web_load_state,_web_toggle_pause,_web_set_paused,_web_set_muted,_web_reset,_web_stop,_web_frame_count,_web_set_speed_limiter \
        -lidbfs.js \
        --embed-file "$BUILDDIR/data@/m64p/data"
}

# The core's main loop never returns, so it has to be suspended to give the
# browser a chance to run. JSPI (WebAssembly JavaScript Promise Integration)
# does that natively at no cost to the emulation code; Asyncify instruments
# every function and is much slower, so it is only the fallback for browsers
# without JSPI. The page picks the right one.
echo "==> link (JSPI)"
mkdir -p "$DISTDIR"
link "$DISTDIR/mupen64plus-jspi.js" -sJSPI=1
echo "==> link (Asyncify)"
link "$DISTDIR/mupen64plus.js" -sASYNCIFY=1 -sASYNCIFY_STACK_SIZE=262144

cp "$WEBDIR/shell/index.html" "$WEBDIR/shell/.htaccess" "$DISTDIR/"
if [ $# -ge 1 ]; then
    ext="$(echo "${1##*.}" | tr 'A-Z' 'a-z')"
    case "$ext" in
        zip|z64|n64|v64|rom) ;;
        *) ext=rom ;;
    esac
    rm -f "$DISTDIR"/game.*
    cp "$1" "$DISTDIR/game.$ext"
fi

echo "==> done: $DISTDIR"
ls -la "$DISTDIR"
