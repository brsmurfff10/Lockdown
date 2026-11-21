extends RefCounted
## Cage: the original small, fast map. T west, CT east.


static func data() -> Dictionary:
	return {
		"name": "Cage",
		"size": Vector2i(56, 34),
		"round_time": 115.0,
		"tempo": 1.0,
		"floors": [
			Rect2i(2, 12, 8, 10), Rect2i(4, 4, 4, 8), Rect2i(4, 3, 30, 4), Rect2i(34, 2, 14, 11),
			Rect2i(4, 22, 4, 7), Rect2i(4, 26, 28, 4), Rect2i(32, 21, 14, 11), Rect2i(10, 15, 30, 4),
			Rect2i(38, 15, 8, 4), Rect2i(46, 13, 8, 8), Rect2i(46, 7, 6, 6), Rect2i(46, 21, 6, 5),
			Rect2i(26, 7, 3, 8), Rect2i(22, 19, 3, 7), Rect2i(33, 12, 3, 3), Rect2i(33, 19, 3, 2),
		],
		"cover": [
			Rect2i(18, 3, 2, 2), Rect2i(38, 5, 2, 2), Rect2i(43, 9, 2, 2), Rect2i(36, 10, 1, 2),
			Rect2i(36, 24, 2, 2), Rect2i(41, 28, 2, 2), Rect2i(40, 22, 1, 2),
			Rect2i(20, 15, 2, 2), Rect2i(36, 17, 1, 2), Rect2i(16, 26, 2, 2),
		],
		"sites": {"A": Rect2i(36, 3, 10, 9), "B": Rect2i(34, 22, 10, 9)},
		"spawns": [
			[Vector2i(4, 13), Vector2i(4, 16), Vector2i(4, 19), Vector2i(7, 14), Vector2i(7, 18)],
			[Vector2i(48, 14), Vector2i(48, 17), Vector2i(48, 19), Vector2i(51, 15), Vector2i(51, 18)],
		],
		"points": {
			"t_north": Vector2i(5, 9), "t_south": Vector2i(5, 24), "long_mid": Vector2i(15, 5),
			"long_stage": Vector2i(29, 4), "a_long_entry": Vector2i(34, 4), "cat_bottom": Vector2i(27, 14),
			"cat_top": Vector2i(27, 7), "mid_entry": Vector2i(12, 16), "mid_center": Vector2i(25, 17),
			"shortA_stage": Vector2i(31, 15), "a_short_entry": Vector2i(34, 13), "shortB_stage": Vector2i(31, 18),
			"b_short_entry": Vector2i(34, 20), "lower_top": Vector2i(23, 19), "lower_bottom": Vector2i(23, 25),
			"tunnels_mid": Vector2i(12, 28), "tunnels_stage": Vector2i(28, 28), "b_tunnel_entry": Vector2i(32, 28),
			"ct_spawn": Vector2i(49, 16), "ct_a": Vector2i(48, 11), "ct_b": Vector2i(48, 22),
			"ct_mid": Vector2i(42, 16), "mid_hold": Vector2i(38, 16), "ct_a_stage": Vector2i(49, 12),
			"mid_a_stage": Vector2i(37, 15), "ct_b_stage": Vector2i(49, 21), "mid_b_stage": Vector2i(37, 18),
		},
		"routes": {
			"A.main": {"site": "A", "via": ["t_north", "long_mid"], "stage": "long_stage", "entry": "a_long_entry"},
			"A.alt": {"site": "A", "via": ["mid_entry", "cat_bottom", "cat_top"], "stage": "long_stage", "entry": "a_long_entry"},
			"A.short": {"site": "A", "via": ["mid_entry", "mid_center"], "stage": "shortA_stage", "entry": "a_short_entry"},
			"B.main": {"site": "B", "via": ["t_south", "tunnels_mid"], "stage": "tunnels_stage", "entry": "b_tunnel_entry"},
			"B.alt": {"site": "B", "via": ["mid_entry", "lower_top", "lower_bottom"], "stage": "tunnels_stage", "entry": "b_tunnel_entry"},
			"B.short": {"site": "B", "via": ["mid_entry", "mid_center"], "stage": "shortB_stage", "entry": "b_short_entry"},
			"lurk": {"site": "", "via": ["mid_entry"], "stage": "mid_center", "entry": ""},
		},
		"site_info": {
			"A": {
				"plant": [Vector2i(39, 7), Vector2i(41, 10), Vector2i(37, 4)],
				"ct_holds": [[Vector2i(45, 4), "a_long_entry"], [Vector2i(41, 11), "a_short_entry"], [Vector2i(46, 6), "a_long_entry"]],
				"t_cover": [[Vector2i(44, 7), "ct_a"], [Vector2i(37, 8), "a_short_entry"], [Vector2i(41, 4), "ct_a"], [Vector2i(35, 6), "ct_a"]],
				"retake": ["ct_a_stage", "mid_a_stage"],
				"flank": ["mid_center", "cat_bottom", "cat_top", "long_stage"],
				"main_route": "A.main", "alt_route": "A.alt", "short_route": "A.short",
			},
			"B": {
				"plant": [Vector2i(38, 26), Vector2i(40, 28), Vector2i(35, 23)],
				"ct_holds": [[Vector2i(44, 26), "b_tunnel_entry"], [Vector2i(43, 22), "b_short_entry"], [Vector2i(45, 24), "b_short_entry"]],
				"t_cover": [[Vector2i(42, 25), "ct_b"], [Vector2i(36, 22), "b_short_entry"], [Vector2i(39, 30), "ct_b"], [Vector2i(34, 27), "ct_b"]],
				"retake": ["ct_b_stage", "mid_b_stage"],
				"flank": ["mid_center", "lower_top", "lower_bottom", "tunnels_stage"],
				"main_route": "B.main", "alt_route": "B.alt", "short_route": "B.short",
			},
		},
	}
