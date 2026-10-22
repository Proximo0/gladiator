extends TestCase


func test_count_up_eases_to_the_new_rating() -> void:
	assert_eq(RatingChangeView.shown_rating(1000, 1022, 0.0), 1000)
	assert_eq(RatingChangeView.shown_rating(1000, 1022, RatingChangeView.COUNT_S), 1022)
	assert_eq(RatingChangeView.shown_rating(1000, 1022, 99.0), 1022)
	var mid: int = RatingChangeView.shown_rating(1000, 1022, RatingChangeView.COUNT_S * 0.5)
	assert_true(mid > 1011 and mid < 1022, "eases out: past halfway at half time (%d)" % mid)
	assert_eq(RatingChangeView.shown_rating(1000, 980, RatingChangeView.COUNT_S), 980)


func test_tier_progress() -> void:
	assert_near(RatingChangeView.tier_progress(1100), 0.5)
	assert_near(RatingChangeView.tier_progress(1000), 0.0)
	assert_near(RatingChangeView.tier_progress(2500), 1.0)
	assert_true(RatingChangeView.tier_progress(900) > 0.0 and RatingChangeView.tier_progress(900) < 1.0)


func test_leaderboard_page_helpers() -> void:
	assert_eq(LeaderboardScreen.my_page_offset({"rank": 1}), 0)
	assert_eq(LeaderboardScreen.my_page_offset({"rank": 20}), 0)
	assert_eq(LeaderboardScreen.my_page_offset({"rank": 21}), 20)
	assert_eq(LeaderboardScreen.my_page_offset({"rank": 101}), -1, "below the pages: only the pinned row")
	assert_eq(LeaderboardScreen.my_page_offset({}), -1)
	assert_eq(LeaderboardScreen.page_text(20, 20, 57), "21-40 of 57")
	assert_eq(LeaderboardScreen.page_text(0, 0, 0), "")
	assert_true(LeaderboardScreen.tier_colour(500) != LeaderboardScreen.tier_colour(2500))
