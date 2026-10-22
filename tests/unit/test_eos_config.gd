extends TestCase
## EosConfig: parsing the owner's credentials file (quoted or not), placeholders, the optional keys.

const GOOD: String = """; Sandblood EOS credentials (dev sandbox)
[eos]
product_id = "4f1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e"
sandbox_id="p-abcdefghijklmnopqrstuvwxyz12"
deployment_id = 0a1b2c3d4e5f60718293a4b5c6d7e8f9  ; the dev deployment
client_id = 'xyza7891AbCdEfGhIjKlMnOpQrStUv'
client_secret = "s3cr3t+/=value"
"""


func test_parses_quoted_and_unquoted_values() -> void:
	var c: EosConfig = EosConfig.parse(GOOD, "test.cfg")
	assert_true(c.is_complete(), c.error)
	assert_eq(c.product_id, "4f1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e")
	assert_eq(c.sandbox_id, "p-abcdefghijklmnopqrstuvwxyz12")
	assert_eq(c.deployment_id, "0a1b2c3d4e5f60718293a4b5c6d7e8f9", "trailing comment dropped")
	assert_eq(c.client_id, "xyza7891AbCdEfGhIjKlMnOpQrStUv")
	assert_eq(c.client_secret, "s3cr3t+/=value", "'=' inside a value is kept")
	assert_eq(c.product_name, EosConfig.DEFAULT_PRODUCT_NAME)
	assert_eq(c.encryption_key, "")
	assert_eq(c.source, "test.cfg")


func test_missing_and_placeholder_values_are_named() -> void:
	var text: String = GOOD.replace("'xyza7891AbCdEfGhIjKlMnOpQrStUv'", "\"<client id>\"").replace("client_secret = \"s3cr3t+/=value\"", "")
	var c: EosConfig = EosConfig.parse(text)
	assert_false(c.is_complete())
	assert_eq(c.missing(), PackedStringArray(["client_id", "client_secret"]))
	assert_true(c.error.contains("client_id") and c.error.contains("client_secret"), c.error)


func test_placeholders() -> void:
	for v: String in ["", "  ", "<product id>", "YOUR_CLIENT_ID", "your-secret", "changeme", "xxxxxxxx", "xxxx-xxxx"]:
		assert_true(EosConfig.is_placeholder(v), "'%s' is a placeholder" % v)
	for v2: String in ["4f1c2d3e", "p-abc", "0x12"]:
		assert_false(EosConfig.is_placeholder(v2), "'%s' is real" % v2)


func test_no_section_or_garbage() -> void:
	assert_false(EosConfig.parse("").is_complete())
	assert_false(EosConfig.parse("[other]\nproduct_id=1\n").is_complete())
	var c: EosConfig = EosConfig.parse("product_id = 1\n[eos\n")
	assert_false(c.is_complete())
	assert_true(c.error != "")


func test_section_and_keys_ignore_case_and_other_sections() -> void:
	var text: String = "[other]\nclient_id=wrong\n[EOS]\n" + GOOD.substr(GOOD.find("[eos]") + 6).replace("client_id", "Client_ID")
	var c: EosConfig = EosConfig.parse(text)
	assert_true(c.is_complete(), c.error)
	assert_eq(c.client_id, "xyza7891AbCdEfGhIjKlMnOpQrStUv")


func test_optional_keys() -> void:
	var key: String = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	var c: EosConfig = EosConfig.parse(GOOD + "encryption_key=%s\nproduct_name=Sandblood Dev\nproduct_version=0.3.1\n" % key)
	assert_true(c.is_complete(), c.error)
	assert_eq(c.encryption_key, key)
	assert_eq(c.product_name, "Sandblood Dev")
	assert_eq(c.version_or("9.9"), "0.3.1")
	var bad: EosConfig = EosConfig.parse(GOOD + "encryption_key=1234\n")
	assert_false(bad.is_complete(), "short encryption key")
	assert_eq(EosConfig.parse(GOOD).version_or("0.2.0"), "0.2.0")
	assert_eq(EosConfig.parse(GOOD).version_or(""), "dev")


func test_windows_line_endings() -> void:
	var c: EosConfig = EosConfig.parse(GOOD.replace("\n", "\r\n"))
	assert_true(c.is_complete(), c.error)
	assert_eq(c.client_secret, "s3cr3t+/=value")


func test_describe_hides_the_secret() -> void:
	var d: String = EosConfig.parse(GOOD).describe()
	assert_false(d.contains("s3cr3t"), d)
	assert_true(d.contains("secret=set"), d)


func test_search_paths_start_in_the_project() -> void:
	var paths: PackedStringArray = EosConfig.search_paths()
	assert_eq(paths[0], EosConfig.RES_PATH)
	assert_eq(paths[paths.size() - 1], EosConfig.USER_PATH)
