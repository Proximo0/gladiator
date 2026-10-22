extends TestCase


func test_every_transition_is_under_a_quarter_second() -> void:
	assert_true(MenuFx.IN_S < MenuFx.MAX_S)
	assert_true(MenuFx.VEIL_S < MenuFx.MAX_S)
	assert_true(MenuFx.staggered_length(1) <= MenuFx.MAX_S)
	assert_true(MenuFx.staggered_length(10) <= MenuFx.MAX_S, "a long menu column too")
	assert_true(MenuFx.staggered_length(100) <= MenuFx.MAX_S)
	assert_near(MenuFx.staggered_length(0), MenuFx.IN_S)
