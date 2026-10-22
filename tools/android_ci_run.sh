#!/usr/bin/env bash
# Install the CI APK on a running emulator/device, launch it and wait for its ANDROID_CI result line
# (game/debug/android_ci.gd). Writes <out>/logcat.txt, <out>/fight.png (at the "shot" line) and <out>/end.png.
# Usage: tools/android_ci_run.sh <apk> [out_dir] [timeout_s]. Quiet: the ANDROID_CI result line, then one summary.
# Exit 1 on a missing PASS, a FAIL line, a script error or a crash. See docs/android.md.
set -uo pipefail
APK="$1"; OUT="${2:-out/android}"; LIMIT="${3:-1200}"
PKG="com.proximo.sandblood"
mkdir -p "${OUT}"
exec > >(tee "${OUT}/result.txt") 2>&1
fail() { echo "android_ci: FAIL $1"; exit 1; }

adb wait-for-device
adb install -r -g "${APK}" >"${OUT}/install.txt" 2>&1 || { cat "${OUT}/install.txt"; fail "adb install"; }
adb logcat -c
adb logcat -v time >"${OUT}/logcat.txt" 2>&1 &
LOGPID=$!
trap 'kill ${LOGPID} 2>/dev/null' EXIT
adb shell monkey -p "${PKG}" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || fail "launch"

shot=0; seen_pid=0; t=0
while (( t < LIMIT )); do
	sleep 2; t=$((t + 2))
	if (( shot == 0 )) && grep -q "ANDROID_CI shot" "${OUT}/logcat.txt"; then
		adb exec-out screencap -p >"${OUT}/fight.png" 2>/dev/null; shot=1
	fi
	grep -qE "ANDROID_CI (PASS|FAIL) " "${OUT}/logcat.txt" && break
	if adb shell pidof "${PKG}" >/dev/null 2>&1; then
		seen_pid=1
	elif (( seen_pid == 1 )); then
		sleep 3; grep -qE "ANDROID_CI (PASS|FAIL) " "${OUT}/logcat.txt" && break
		adb exec-out screencap -p >"${OUT}/end.png" 2>/dev/null
		grep -E "ANDROID_CI|FATAL|SIGSEGV|SCRIPT ERROR" "${OUT}/logcat.txt" | tail -n 20
		fail "app exited without a result line after ${t}s"
	fi
done
sleep 2
[[ -s "${OUT}/end.png" ]] || adb exec-out screencap -p >"${OUT}/end.png" 2>/dev/null
kill "${LOGPID}" 2>/dev/null
grep -E "ANDROID_CI (start|progress|hitch)" "${OUT}/logcat.txt" | sed 's/^.*ANDROID_CI/ANDROID_CI/' >"${OUT}/progress.txt"
grep -E "[A-Z]/godot" "${OUT}/logcat.txt" >"${OUT}/godot.txt"
line="$(grep -E "ANDROID_CI (PASS|FAIL) " "${OUT}/logcat.txt" | tail -n 1 | sed 's/^.*ANDROID_CI/ANDROID_CI/')"
errs="$(grep -cE "SCRIPT ERROR|USER SCRIPT ERROR|Parse Error" "${OUT}/logcat.txt")"
[[ -n "${line}" ]] && echo "${line}"
[[ "${errs}" == 0 ]] || { grep -E -A2 "SCRIPT ERROR|Parse Error" "${OUT}/logcat.txt" | head -n 30; fail "${errs} script errors"; }
[[ -n "${line}" ]] || { tail -n 40 "${OUT}/logcat.txt"; fail "no result line after ${t}s"; }
[[ "${line}" == "ANDROID_CI PASS "* ]] || fail "fight failed"
(( shot == 1 )) || echo "android_ci: warning: no mid-fight screenshot (shot line not seen)"
echo "android_ci: ok in ${t}s"
