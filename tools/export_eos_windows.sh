#!/usr/bin/env bash
# Windows build WITH Epic Online Services (docs/eos_setup.md). The committed project.godot stays plugin-free (headless
# Linux tests and CI have no plugin binaries), so this copies the repo to build/eos_src, adds the git-ignored EOSG addon
# and credentials there, enables the plugin's autoloads in that copy's project.godot, and exports the "Windows Desktop"
# preset (release) to build/SandbloodEOS-windows.zip. Quiet: errors and one summary line. Exit 1 on failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON="addons/epic-online-services-godot"
SRC="${ROOT}/build/eos_src"
OUT_DIR="${ROOT}/build/eos_windows"
EXE="${OUT_DIR}/Sandblood.exe"
ZIP="${ROOT}/build/SandbloodEOS-windows.zip"
LOG="${ROOT}/build/eos_export.log"
GODOT="${GODOT:-godot}"

fail() { echo "export_eos_windows: $1" >&2; exit 1; }

command -v "${GODOT}" >/dev/null 2>&1 || fail "godot not found on PATH"
command -v zip >/dev/null 2>&1 || fail "zip not found on PATH"
[[ -f "${ROOT}/${ADDON}/eosg.gdextension" ]] || fail "${ADDON} missing (docs/eos_setup.md, section 1)"
[[ -f "${ROOT}/${ADDON}/bin/windows/libeosg.windows.template_release.x86_64.dll" ]] || fail "EOSG Windows release dll missing"
[[ -f "${ROOT}/config/eos_credentials.cfg" ]] || echo "export_eos_windows: warning: no config/eos_credentials.cfg; the build will use the LAN backend" >&2

# The standard export (templates download, naming) is shared: make sure the Windows templates exist.
[[ -f "${HOME}/.local/share/godot/export_templates/4.7.2.stable/windows_release_x86_64.exe" ]] \
	|| fail "Windows export templates missing: run tools/export_windows.sh once"

mkdir -p "${ROOT}/build"
rm -rf "${SRC}" "${OUT_DIR}" "${ZIP}"
mkdir -p "${SRC}" "${OUT_DIR}"
# Copy the project without build output, caches, VCS, captures and the other platforms' leftovers.
(cd "${ROOT}" && tar --exclude=./build --exclude=./.godot --exclude=./out --exclude=./.git -cf - .) | (cd "${SRC}" && tar -xf -)
mkdir -p "${SRC}/config"
[[ -f "${ROOT}/config/eos_credentials.cfg" ]] && cp "${ROOT}/config/eos_credentials.cfg" "${SRC}/config/eos_credentials.cfg"

# Enable the plugin in the copy only: what EditorPlugin._enable_plugin() would write (addons/.../plugin.gd).
python3 -I - "${SRC}/project.godot" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
base = "res://addons/epic-online-services-godot/"
autos = [("EOSGRuntime", "runtime.gd"), ("HPlatform", "heos/hplatform.gd"), ("HAuth", "heos/hauth.gd"),
	("HAchievements", "heos/hachievements.gd"), ("HFriends", "heos/hfriends.gd"), ("HStats", "heos/hstats.gd"),
	("HLeaderboards", "heos/hleaderboards.gd"), ("HLobbies", "heos/hlobbies.gd"), ("HP2P", "heos/hp2p.gd"),
	("HSessions", "heos/hsessions.gd")]
lines = "".join('%s="*%s%s"\n' % (n, base, f) for n, f in autos)
if "[autoload]\n" not in text:
	sys.exit("project.godot has no [autoload] section")
text = text.replace("[autoload]\n", "[autoload]\n\n" + lines.rstrip("\n") + "\n", 1)
if "[editor_plugins]" in text:
	sys.exit("project.godot already has [editor_plugins]")
text += '\n[editor_plugins]\n\nenabled=PackedStringArray("%splugin.cfg")\n' % base
open(path, "w", encoding="utf-8").write(text)
PY

cd "${SRC}"
"${GODOT}" --headless --path . --import >"${LOG}" 2>&1 || { tail -20 "${LOG}" >&2; fail "import failed (see ${LOG})"; }
"${GODOT}" --headless --path . --export-release "Windows Desktop" "${EXE}" >>"${LOG}" 2>&1 || { tail -20 "${LOG}" >&2; fail "export failed (see ${LOG})"; }
[[ -f "${EXE}" ]] || fail "exe not produced"

cp "${ROOT}"/tools/windows/*.bat "${OUT_DIR}/"
# Credentials next to the exe too (EosConfig searches res:// first, then here); the pack already holds a copy.
[[ -f "${ROOT}/config/eos_credentials.cfg" ]] && cp "${ROOT}/config/eos_credentials.cfg" "${OUT_DIR}/eos_credentials.cfg"

# Every file the EOS build needs must be in the output.
for f in Sandblood.exe "Try all weapons (unlock all).bat" "Try outfits (test shop).bat"; do [[ -f "${OUT_DIR}/${f}" ]] || fail "missing ${f}"; done
(cd "${ROOT}/build" && rm -f "${ZIP}" && zip -q -r "$(basename "${ZIP}")" eos_windows) || fail "zip not produced"
echo "export_eos_windows: ok ${ZIP}"
