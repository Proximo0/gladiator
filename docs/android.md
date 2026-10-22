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

## Install on a phone
- USB: enable Developer options and USB debugging, then `~/android-sdk/platform-tools/adb install -r build/Sandblood-android.apk`.
- Without adb: copy the APK to the phone (cable, cloud drive, `adb push`), open it in a file manager and allow
  "Install unknown apps" for that app when asked.
- Debug builds are signed with the shared debug key; a build signed with another key must be uninstalled first.

## Not done yet
- Play Store: release signing with an upload keystore, `--export-release`, and an AAB (needs the Gradle build
  template, the full Android SDK with NDK, and target SDK per current Play policy).
- Touch controls are a game matter; the APK itself only guarantees the window, orientation and renderer.
- Performance tuning on real devices (physics fighters on phones are untested; the emulator CI below only proves it boots and plays).

## Emulator CI (`.github/workflows/android.yml`)
The owner has no Android phone, so every push to `main` (and `ramp/android-ci`, or a manual dispatch) runs the APK
on an emulator on a GitHub-hosted runner (never the self-hosted gpu runner):
1. Godot 4.7.2 (setup-godot action) and the Android export templates (cached by version).
2. The runner's preinstalled SDK plus `build-tools;35.0.1` via sdkmanager; JDK 17 from `JAVA_HOME_17_X64`. No NDK:
   the non-Gradle export only repacks Godot's prebuilt template APK.
3. The job patches its own copy of `export_presets.cfg` (never committed): Android preset x86_64 only and
   `custom_features="android_ci"`. `tools/export_android.sh` generates the debug keystore in the job. No EOS
   credentials exist on the runner, so online falls back to the LAN stub.
4. reactivecircus/android-emulator-runner boots API 30 `google_apis` x86_64 (KVM via a udev rule, SwiftShader GPU),
   then `tools/android_ci_run.sh` installs, launches, screenshots and judges.

Game side: `OS.has_feature("android_ci")` makes `Flags` add `--mode=bot_vs_bot --android_ci --scripted`, so
`main.gd` starts one presented bot fight and attaches `AndroidCi` (`game/debug/android_ci.gd`). It logs (logcat tag
`godot`) `ANDROID_CI start`, `ANDROID_CI shot` at tick 600 (the runner takes `fight.png` then), progress every 10 s,
and one `ANDROID_CI PASS|FAIL ... fps= frame_ms_avg/p50/p95/p99/max= ticks_per_s= why=` line, then quits.
FAIL when `match_over` never fires (time limit + 600 ticks, or 900 wall seconds), no hits, or physics explosions.
The job fails on a FAIL line, a missing result line, any `SCRIPT ERROR`, or the app exiting early.
Artifact `android-emulator`: `logcat.txt`, `progress.txt`, `result.txt`, `install.txt`, `fight.png`, `end.png`.

Run the same judge against a real device: export with the patched preset, plug in, then
`tools/android_ci_run.sh build/Sandblood-android.apk out/android`. On desktop the hook is reachable with
`godot --path . -- --mode=bot_vs_bot --android_ci`.

Emulator frame times are NOT phone numbers: rendering is software (SwiftShader on the runner's CPU) and physics runs
on x86_64 cores under KVM, so the GPU side is far slower and the CPU side far faster than a mid-range ARM phone.
Use the numbers only as a regression signal between runs (same runner type), never as a performance budget.
