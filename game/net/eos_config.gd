class_name EosConfig
extends RefCounted
## The Epic Online Services credentials the game reads at start (docs/eos_setup.md). They come from a file the owner
## writes and git ignores, never from the source:
##
##   [eos]
##   product_id="..."
##   sandbox_id="..."
##   deployment_id="..."
##   client_id="..."
##   client_secret="..."
##   ; optional: product_name, product_version, encryption_key (64 hex characters)
##
## Search order (the first file that exists wins): res://config/eos_credentials.cfg (in the project and, with the
## export include filter, inside the pack), then eos_credentials.cfg next to the executable (tools/export_windows.sh
## copies it there), then user://eos_credentials.cfg. The client secret is not a secret on a client build: it only
## identifies the game's client policy, which is why that policy must allow nothing dangerous.

const SECTION: String = "eos"
const RES_PATH: String = "res://config/eos_credentials.cfg"
const FILE_NAME: String = "eos_credentials.cfg"
const USER_PATH: String = "user://eos_credentials.cfg"
const REQUIRED: PackedStringArray = ["product_id", "sandbox_id", "deployment_id", "client_id", "client_secret"]
const DEFAULT_PRODUCT_NAME: String = "Sandblood"
const MAX_PRODUCT_NAME: int = 64  ## EOS_PLATFORM: product name and version, at most 64 characters each

var product_id: String = ""
var sandbox_id: String = ""
var deployment_id: String = ""
var client_id: String = ""
var client_secret: String = ""
var encryption_key: String = ""
var product_name: String = DEFAULT_PRODUCT_NAME
var product_version: String = ""
var source: String = ""  ## the file it came from ("" = none found)
var error: String = ""  ## why it is not usable ("" when complete)


## Parses the text of a credentials file. Never fails: check is_complete() / error. Values may be quoted or not
## (`client_id = "abc"` and `client_id=abc` both work); `;` and `#` start comments.
static func parse(text: String, from: String = "") -> EosConfig:
	var c := EosConfig.new()
	c.source = from
	var kv: Dictionary = read_section(text, SECTION)
	if kv.is_empty():
		c.error = "no [%s] section with values in %s" % [SECTION, from if from != "" else "the credentials"]
		return c
	c.product_id = str(kv.get("product_id", ""))
	c.sandbox_id = str(kv.get("sandbox_id", ""))
	c.deployment_id = str(kv.get("deployment_id", ""))
	c.client_id = str(kv.get("client_id", ""))
	c.client_secret = str(kv.get("client_secret", ""))
	c.encryption_key = str(kv.get("encryption_key", ""))
	var pn: String = str(kv.get("product_name", ""))
	if pn != "":
		c.product_name = pn.left(MAX_PRODUCT_NAME)
	c.product_version = str(kv.get("product_version", "")).left(MAX_PRODUCT_NAME)
	var missing: PackedStringArray = c.missing()
	if not missing.is_empty():
		c.error = "missing or placeholder: %s" % ", ".join(missing)
	elif c.encryption_key != "" and not _is_hex64(c.encryption_key):
		c.error = "encryption_key must be 64 hex characters (or left out)"
	return c


## key -> value of one [section] of an ini-style text. Keys are lower-cased; surrounding quotes are dropped.
static func read_section(text: String, section: String) -> Dictionary:
	var out: Dictionary = {}
	var current: String = ""
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			current = line.substr(1, line.length() - 2).strip_edges().to_lower()
			continue
		var eq: int = line.find("=")
		if current != section or eq <= 0:
			continue
		out[line.left(eq).strip_edges().to_lower()] = _unquote(line.substr(eq + 1).strip_edges())
	return out


static func _unquote(v: String) -> String:
	if v.length() >= 2 and ((v.begins_with("\"") and v.ends_with("\"")) or (v.begins_with("'") and v.ends_with("'"))):
		return v.substr(1, v.length() - 2).strip_edges()
	# Unquoted: a trailing comment ends the value.
	for mark: String in [" ;", " #"]:
		var at: int = v.find(mark)
		if at >= 0:
			v = v.left(at)
	return v.strip_edges()


## The first credentials file that exists, parsed. With none, error says so.
static func find() -> EosConfig:
	for path: String in search_paths():
		if FileAccess.file_exists(path):
			return parse(FileAccess.get_file_as_string(path), path)
	var c := EosConfig.new()
	c.error = "no %s (see docs/eos_setup.md)" % FILE_NAME
	return c


static func search_paths() -> PackedStringArray:
	var out := PackedStringArray([RES_PATH])
	if not OS.has_feature("editor"):
		out.append(OS.get_executable_path().get_base_dir().path_join(FILE_NAME))
	out.append(USER_PATH)
	return out


func is_complete() -> bool:
	return error == "" and missing().is_empty()


## The required keys that are empty or still a template placeholder.
func missing() -> PackedStringArray:
	var out := PackedStringArray()
	var values: Dictionary = {"product_id": product_id, "sandbox_id": sandbox_id, "deployment_id": deployment_id,
		"client_id": client_id, "client_secret": client_secret}
	for k: String in REQUIRED:
		if is_placeholder(str(values[k])):
			out.append(k)
	return out


## Empty, or the text a template ships with ("<product id>", "YOUR_CLIENT_ID", "xxxx", "changeme").
static func is_placeholder(v: String) -> bool:
	var t: String = v.strip_edges()
	if t == "" or t.begins_with("<") or t.to_upper().begins_with("YOUR") or t.to_lower() == "changeme":
		return true
	return t.replace("x", "").replace("X", "").replace("-", "") == ""


## The version EOS is told: the file's product_version, else the project's application/config/version, else "dev".
func version_or(project_version: String) -> String:
	if product_version != "":
		return product_version
	return project_version.left(MAX_PRODUCT_NAME) if project_version != "" else "dev"


## For logs: which values are set, with the secret hidden.
func describe() -> String:
	return "product=%s sandbox=%s deployment=%s client=%s secret=%s (%s)" % [product_id, sandbox_id, deployment_id,
		client_id, "set" if client_secret != "" else "missing", source if source != "" else "no file"]


static func _is_hex64(s: String) -> bool:
	return s.length() == 64 and s.is_valid_hex_number(false)
