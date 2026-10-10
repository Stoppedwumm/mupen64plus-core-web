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
| `mupen64plus-jspi.js/.wasm` | Core + plugins, JSPI build (Chrome, Edge, ...) |
| `mupen64plus.js/.wasm`      | Core + plugins, Asyncify build (other browsers) |
| `game.*`           | ROM loaded by "Start" (`.zip`, `.z64`, `.n64`, `.v64`) |
| `.htaccess`        | MIME type/compression settings for Apache            |

Copy the contents of `dist/` to the web server. The page does not work when
opened from `file://`.

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
* **Main loop:** the core runs its emulation loop inside `CoreDoCommand(M64CMD_EXECUTE)`,
  and `apply_speed_limiter()` in `src/main/main.c` suspends it to let the
  browser present frames and handle input and audio: while ahead of schedule
  it waits on `requestAnimationFrame`, so frames are produced in step with the
  display, and when running behind it yields at least every 8 ms through a
  `MessageChannel` round trip, since `setTimeout(0)` is clamped to 4 ms.
  Suspension uses JSPI where the browser supports it and Asyncify otherwise
  (add `?asyncify` to the URL to force the fallback); the page picks the build.
* **CPU:** the cached interpreter is used, since there is no JIT for WebAssembly.
* **Video:** video-rice renders through its GLES2 path on WebGL.
* **Saves:** in-game saves and save states are written to `/m64p/save`,
  which is backed by IndexedDB, so they persist in the browser.
* **Gamplo:** the page loads the [Gamplo](https://gamplo.com) SDK. For a
  signed-in player, in-game saves (`.eep`, `.sra`, `.fla`, `.mpk`) are gzipped
  and mirrored to cloud save slot 0, uploaded when they change (at most every
  7 s, within Gamplo's 10 saves/minute) and restored before the game boots
  when the cloud copy is newer. Save states (~1 MB compressed) do not fit a
  100 KB cloud slot and stay in the browser. Outside Gamplo or as a guest,
  everything stays local.
* **Plugin patches:** `patches/<plugin>.patch` is applied on top of the pinned
  plugin sources (audio-sdl: avoid dividing by a zero sample rate when the
  audio device failed to open; video-rice: swap red/blue when uploading
  textures, since WebGL has no BGRA texture format).

## The page

`shell/index.html` is a self-contained player page for the bundled game: the
game fills the window (or the Gamplo iframe) at 4:3, behind a click-to-play
splash that shows the controls and download progress. There is no other UI:
mute and fullscreen buttons appear in the corner while the mouse moves, and
the game pauses when the page loses focus ("Click to keep playing"), the way
Flash games did. Only `game.zip` is loaded; there is no way to pick another
ROM. Add `?debug` to the URL to log emulator output to the console.

## Controls

Keyboard (`frontend/InputAutoCfg-web.ini`): arrows = analog stick,
Space = A (jump), X = B (punch), Z = Z (crouch), W/A/S/D = C buttons (camera),
E = R (camera mode), Q = L, Enter = Start. F5/F7 = quick save/load, P = pause,
M = mute; the core's other hotkeys (Esc, fast forward, save slots, ...) are
disabled. Gamepads that the browser reports with the standard layout
(`... STANDARD GAMEPAD ...` in Chromium) are mapped automatically.
