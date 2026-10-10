# Mupen64Plus for the web

This directory builds mupen64plus-core together with the
[rsp-hle](https://github.com/mupen64plus/mupen64plus-rsp-hle),
[video-rice](https://github.com/mupen64plus/mupen64plus-video-rice),
[audio-sdl](https://github.com/mupen64plus/mupen64plus-audio-sdl) and
[input-sdl](https://github.com/mupen64plus/mupen64plus-input-sdl) plugins into a
single WebAssembly module with [Emscripten](https://emscripten.org/), plus a
small HTML page to run it. The result is a static site that any web server
(Apache, nginx, `python3 -m http.server`, ...) can host.

## Building

```sh
source /path/to/emsdk/emsdk_env.sh
projects/web/build.sh path/to/game.zip   # the ROM argument is optional
```

The script clones the plugins at pinned commits into `projects/web/build/`,
compiles everything and writes the site to `projects/web/dist/`:

| File               | Purpose                                              |
|--------------------|------------------------------------------------------|
| `index.html`       | Player page                                          |
| `mupen64plus.js`   | Emscripten loader                                    |
| `mupen64plus.wasm` | Core + plugins                                       |
| `game.*`           | ROM loaded by "Start" (`.zip`, `.z64`, `.n64`, `.v64`) |
| `.htaccess`        | MIME type/compression settings for Apache            |

Copy the contents of `dist/` to the web server. The page does not work when
opened from `file://`. Other ROMs can be loaded with "Load another ROM…".

Emscripten fetches its SDL2, zlib and libpng ports on first use. If
downloads are blocked, clone them into the ports cache instead (see
`tools/ports/*.py` in Emscripten for the versions and expected paths).

## How it works

* **Static plugins:** Emscripten has no usable `dlopen()` for this, so all
  plugins are linked into one module. Plugins define the same global names
  (`PluginStartup`, `ConfigOpenSection`, ...), so `build.sh` compiles each
  plugin twice: once to list its global symbols with `llvm-nm`, and again with
  a generated header that prefixes them (`rice_PluginStartup`, ...).
  `gen_plugin_tables.py` then emits a symbol table per plugin, and
  `src/osal/dynamiclib_emscripten.c` resolves `osal_dynlib_getproc()` against
  those tables, with the core's own API exposed the same way.
* **Main loop:** the core runs its emulation loop inside `CoreDoCommand(M64CMD_EXECUTE)`.
  It is built with Asyncify, and `apply_speed_limiter()` in `src/main/main.c`
  yields to the browser once per VI so that frames are presented and input
  and audio events are handled.
* **CPU:** the cached interpreter is used, since there is no JIT for WebAssembly.
* **Video:** video-rice renders through its GLES2 path on WebGL.
* **Saves:** in-game saves and save states are written to `/m64p/save`,
  which is backed by IndexedDB, so they persist in the browser.

## Controls

Keyboard (input-sdl defaults): arrows = analog stick, Left Shift = A,
Left Ctrl = B, Z = Z, X/C = L/R, Enter = Start, I/J/K/L = C buttons,
W/A/S/D = D-pad, F5/F7 = save/load state, P = pause.
Gamepads that the browser reports with the standard layout
(`... STANDARD GAMEPAD ...` in Chromium) are mapped automatically.
