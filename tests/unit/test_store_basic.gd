extends TestCase

const SAM: String = "sandblood.outfit.samurai"
const ALI: String = "sandblood.outfit.alien"


func test_products_and_fallback_price() -> void:
	var s := StoreStub.new()
	assert_eq(s.products(), [SAM, ALI])
	assert_eq(s.price_label(SAM), "$4.99")
	s.set_price(SAM, "5,00 EUR")
	assert_eq(s.price_label(SAM), "5,00 EUR")
	assert_eq(s.price_label(ALI), "$4.99")


func test_purchase_grants_and_signals() -> void:
	var s := StoreStub.new()
	var got: Array = []
	s.purchase_finished.connect(func(p: String, ok: bool, m: String) -> void: got.append([p, ok, m]))
	s.purchase(SAM)
	assert_eq(got, [[SAM, true, ""]])
	assert_true(s.owns(SAM))
	assert_false(s.owns(ALI))
	assert_eq(s.owned(), [SAM])


func test_failed_purchase_grants_nothing() -> void:
	var s := StoreStub.new()
	s.result_ok = false
	s.result_message = "cancelled"
	var got: Array = []
	s.purchase_finished.connect(func(p: String, ok: bool, m: String) -> void: got.append([p, ok, m]))
	s.purchase(ALI)
	assert_eq(got, [[ALI, false, "cancelled"]])
	assert_eq(s.owned(), [])


func test_unknown_product_and_unavailable() -> void:
	var s := StoreStub.new()
	s.purchase("sandblood.outfit.nope")
	assert_eq(s.owned(), [])
	s.available = false
	s.purchase(SAM)
	assert_false(s.owns(SAM))


func test_pending_purchase() -> void:
	var s := StoreStub.new()
	s.hold = true
	var got: Array = []
	s.purchase_finished.connect(func(p: String, ok: bool, _m: String) -> void: got.append([p, ok]))
	s.purchase(SAM)
	assert_eq(got, [])
	assert_false(s.owns(SAM))
	s.complete_pending()
	assert_eq(got, [[SAM, true]])
	assert_true(s.owns(SAM))


func test_restore() -> void:
	var s := StoreStub.new()
	s.restore_grants = [ALI, "junk"]
	var res: Array = []
	s.restore_finished.connect(func(ok: bool, _m: String) -> void: res.append(ok))
	s.restore_purchases()
	assert_eq(res, [true])
	assert_eq(s.owned(), [ALI])
	s.restore_ok = false
	s.restore_purchases()
	assert_eq(res, [true, false])


func test_base_store_is_closed() -> void:
	for st: Store in [Store.new(), StoreEpic.new(), StoreGooglePlay.new()]:
		assert_false(st.is_available())
		var got: Array = []
		st.purchase_finished.connect(func(_p: String, ok: bool, _m: String) -> void: got.append(ok))
		st.purchase(SAM)
		assert_eq(got, [false], st.backend_name())
		assert_eq(st.owned(), [])
		var r: Array = []
		st.restore_finished.connect(func(ok: bool, _m: String) -> void: r.append(ok))
		st.restore_purchases()
		assert_eq(r, [false])


func test_local_store_in_memory() -> void:
	var s := StoreLocal.new(false)
	assert_true(s.is_available())
	s.purchase(SAM)
	assert_true(s.owns(SAM))
	s.purchase("bogus")
	assert_eq(s.owned(), [SAM])
	s.clear()
	assert_eq(s.owned(), [])


func test_local_store_never_writes_when_not_persisting() -> void:
	var path: String = "user://test_store_should_not_exist.json"
	var s := StoreLocal.new(false, path)
	s.purchase(SAM)
	assert_false(FileAccess.file_exists(path))


func test_owned_serialization() -> void:
	var text: String = StoreLocal.serialize_owned([ALI, SAM])
	assert_eq(StoreLocal.parse_owned(text).keys(), [ALI, SAM])
	assert_eq(StoreLocal.parse_owned("garbage").size(), 0)
	assert_eq(StoreLocal.parse_owned("").size(), 0)
	assert_eq(StoreLocal.parse_owned('{"owned": ["x", "%s"]}' % ALI).keys(), [ALI], "unknown ids dropped")
	assert_eq(StoreLocal.parse_owned('{"owned": 3}').size(), 0)
