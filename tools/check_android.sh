#!/usr/bin/env bash
# Android export check: builds the "Android" preset with tools/export_android.sh and checks the APK's manifest
# (package, landscape, INTERNET, arm64-v8a + armeabi-v7a). Skips cleanly (exit 0) when this machine has no Android
# toolchain set up (export templates, JDK 17, SDK build-tools), because export_android.sh would try to download them.
# Usage: tools/check_android.sh [--setup]   (--setup lets export_android.sh fetch what is missing first)
# Quiet: errors plus one line "ANDROID ok|skipped|FAIL <detail>".
set -uo pipefail
cd "$(dirname "$0")/.."
SDK="${ANDROID_SDK_ROOT:-${HOME}/android-sdk}"
JDK="${JAVA_HOME_17:-${HOME}/jdk-17}"
TPL="${HOME}/.local/share/godot/export_templates/4.7.2.stable"
AAPT="${SDK}/build-tools/35.0.1/aapt"
APK="build/Sandblood-android.apk"

missing=()
[[ -f "${TPL}/android_debug.apk" ]] || missing+=("export templates")
[[ -x "${JDK}/bin/keytool" ]] || missing+=("JDK 17")
[[ -x "${SDK}/build-tools/35.0.1/apksigner" ]] || missing+=("SDK build-tools")
if (( ${#missing[@]} )) && [[ "${1:-}" != "--setup" ]]; then
  echo "ANDROID skipped (missing: ${missing[*]}; run tools/check_android.sh --setup or see docs/android.md)"
  exit 0
fi
if ! out=$(tools/export_android.sh 2>&1); then
  echo "$out"
  echo "ANDROID FAIL export"
  exit 1
fi
badging=$("${AAPT}" dump badging "${APK}" 2>&1)
tree=$("${AAPT}" dump xmltree "${APK}" AndroidManifest.xml 2>&1)
bad=()
grep -q "package: name='com.proximo.sandblood'" <<<"$badging" || bad+=("package")
grep -q "uses-permission: name='android.permission.INTERNET'" <<<"$badging" || bad+=("INTERNET")
grep -q "native-code: 'arm64-v8a' 'armeabi-v7a'" <<<"$badging" || bad+=("abis")
# screenOrientation 0 landscape, 6 sensorLandscape, 8 reverseLandscape, 11 userLandscape: any landscape is fine.
grep -qE "screenOrientation\(0x0101001e\)=\(type 0x10\)0x(0|6|8|b)$" <<<"$tree" || bad+=("orientation")
size=$(du -h "${APK}" | cut -f1)
if (( ${#bad[@]} )); then
  echo "ANDROID FAIL manifest: ${bad[*]}"
  exit 1
fi
echo "ANDROID ok ${APK} (${size}, landscape, arm64-v8a+armeabi-v7a)"
