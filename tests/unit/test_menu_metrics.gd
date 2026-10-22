extends TestCase


func test_touch_target_is_millimetres_on_the_glass_with_a_pixel_floor() -> void:
	assert_near(MenuMetrics.touch_px(0.0), MenuMetrics.TOUCH_MIN_PX)
	assert_near(MenuMetrics.touch_px(96.0), MenuMetrics.TOUCH_MIN_PX, 0.001, "a desktop dpi stays at the floor")
	assert_near(MenuMetrics.touch_px(420.0), 8.0 * 420.0 / 25.4, 0.01)
	assert_near(MenuMetrics.touch_units(420.0, 0.5), 2.0 * 8.0 * 420.0 / 25.4, 0.01)


func test_title_grid_one_column_when_it_fits() -> void:
	var g: Dictionary = MenuMetrics.title_grid(10, 800.0, 62.0, 74.0, 8.0)
	assert_eq(int(g["columns"]), 1)
	assert_eq(int(g["rows"]), 10)
	assert_true(float(g["item_h"]) >= 62.0 and float(g["item_h"]) <= 74.0)


func test_title_grid_goes_two_wide_under_the_first_item() -> void:
	var g: Dictionary = MenuMetrics.title_grid(10, 700.0, 110.0, 160.0, 14.0)
	assert_eq(int(g["columns"]), 2)
	assert_eq(int(g["rows"]), 6, "one full-width row then 9 items two to a row")
	assert_true(float(g["item_h"]) >= 110.0)
	assert_eq(int(MenuMetrics.title_grid(9, 500.0, 110.0, 160.0, 14.0)["rows"]), 5)
	assert_eq(int(MenuMetrics.title_grid(0, 500.0, 110.0, 160.0, 14.0)["rows"]), 0)
