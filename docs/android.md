# Android build

`tools/export_android.sh` exports the "Android" preset to `build/Sandblood-android.apk`: a debug-signed APK
(arm64-v8a and armeabi-v7a, Godot's non-Gradle path, `com.proximo.sandblood`, landscape, immersive, INTERNET only).
It is quiet: errors plus one `export_android: ok <path> (<size>)` line. Safe to re-run.

## Build
```
tools/export_android.sh
```
First run sets up, under `$HOME` only (nothing system-wide):
- Godot 4.7.2 Android export templates in `~/.local/share/godot/export_templates/4.7.2.stable` (the tpz is cached in
  `~/.cache/godot-templates`).
- JDK 17 in `~/jdk-17` and an SDK in `~/android-sdk` (`build-tools/35.0.1`: apksigner, aapt, aapt2, zipalign;
  `platform-tools/adb`). `dl.google.com` is blocked in the cloud sandbox, so on Debian/Ubuntu these are unpacked from
  distro packages with `apt-get download` (cached in `~/.cache/android-debs`; run `apt-get update` once if the fetch
  fails). On a machine with the real Android SDK (cmdline-tools, build-tools 35.0.1, platform android-35), set
  `ANDROID_SDK_ROOT` and the script uses it instead. Gradle builds are not used, so no NDK or platform is needed.
- `~/.android/debug.keystore` (alias `androiddebugkey`, password `android`), made with keytool if missing.
- Godot editor settings (`~/.config/godot/editor_settings-4.7.tres`): SDK path, JDK path, debug keystore.

Project settings the export needs (in `project.godot`, owned by the lead):
- `[rendering] textures/vram_compression/import_etc2_astc=true` (export refuses without it).
- `[display] window/handheld/orientation=4` (sensor landscape).
- Already present: `renderer/rendering_method.mobile="gl_compatibility"`.

## Check
`tools/check_android.sh` builds the APK and checks its manifest (package, landscape, INTERNET, both ABIs), printing
`ANDROID ok|skipped|FAIL`. Without the toolchain above it prints `ANDROID skipped (...)` and exits 0; `--setup` lets it
fetch what is missing first. Touch is proven without a phone by `tests/sim/sim_touch.gd` (synthetic touch events into
the real controls) and pictured by `tests/render/touch_capture.tscn` (`--safe-insets=L,T,R,B` fakes a notch).

## Install on a phone
- USB: enable Developer options and USB debugging, then `~/android-sdk/platform-tools/adb install -r build/Sandblood-android.apk`.
- Without adb: copy the APK to the phone (cable, cloud drive, `adb push`), open it in a file manager and allow
  "Install unknown apps" for that app when asked.
- Debug builds are signed with the shared debug key; a build signed with another key must be uninstalled first.

## Not done yet
- Play Store: release signing with an upload keystore, `--export-release`, and an AAB (needs the Gradle build
  template, the full Android SDK with NDK, and target SDK per current Play policy).
- Touch controls are a game matter (game/input/touch_controls.gd, sim-tested); the APK itself only guarantees the
  window, orientation and renderer. Nobody has played them on a real phone yet.
- Performance tuning on real devices (physics fighters on phones are untested).
