extends RefCounted
## Foundry: vertical layout. T spawn south, CT spawn north, sites on the wings.
##   A (west wing): the long West Lane, the low connector from the mid
##   corridor to the West Lane, or Short A from the mid hall.
##   B (east wing): mirror of A.
##   Mid: a long corridor up the middle into the mid hall below CT.


static func data() -> Dictionary:
	return {
		"name": "Foundry",
		"size": Vector2i(96, 90),
		"round_time": 140.0,
		"tempo": 1.6,
		"floors": [
			Rect2i(40, 78, 16, 9), # T spawn
			Rect2i(40, 4, 16, 9), # CT spawn
			Rect2i(6, 14, 20, 18), # A site (west)
			Rect2i(70, 14, 20, 18), # B site (east)
			Rect2i(45, 40, 6, 38), # Mid corridor
			Rect2i(38, 28, 20, 12), # Mid hall
			Rect2i(45, 13, 6, 15), # Mid hall -> CT
			Rect2i(20, 80, 20, 5), # T west exit
			Rect2i(14, 32, 6, 53), # West lane (A main)
			Rect2i(26, 30, 12, 5), # Short A
			Rect2i(20, 58, 25, 5), # West connector (A alt)
			Rect2i(56, 80, 20, 5), # T east exit
			Rect2i(76, 32, 6, 53), # East lane (B main)
			Rect2i(58, 30, 12, 5), # Short B
			Rect2i(51, 58, 25, 5), # East connector (B alt)
			Rect2i(26, 6, 14, 5), Rect2i(20, 6, 6, 8), # CT -> A
			Rect2i(56, 6, 14, 5), Rect2i(70, 6, 6, 8), # CT -> B
		],
		"cover": [
			Rect2i(47, 66, 2, 2), Rect2i(45, 50, 2, 2), # Mid corridor
			Rect2i(42, 32, 2, 3), Rect2i(52, 32, 2, 3), Rect2i(47, 33, 2, 2), # Mid hall
			Rect2i(16, 70, 2, 2), Rect2i(14, 48, 2, 2), # West lane
			Rect2i(78, 70, 2, 2), Rect2i(80, 48, 2, 2), # East lane
			Rect2i(10, 18, 3, 3), Rect2i(17, 22, 2, 4), Rect2i(21, 16, 3, 2), Rect2i(9, 27, 3, 2), # A site
			Rect2i(83, 18, 3, 3), Rect2i(77, 22, 2, 4), Rect2i(72, 16, 3, 2), Rect2i(84, 27, 3, 2), # B site
		],
		"sites": {"A": Rect2i(7, 15, 18, 16), "B": Rect2i(71, 15, 18, 16)},
		"spawns": [
			[Vector2i(43, 81), Vector2i(47, 81), Vector2i(51, 81), Vector2i(45, 84), Vector2i(49, 84)],
			[Vector2i(43, 7), Vector2i(47, 7), Vector2i(51, 7), Vector2i(45, 10), Vector2i(49, 10)],
		],
		"points": {
			"ct_spawn": Vector2i(48, 8), "ct_mid": Vector2i(48, 18), "mid_hold": Vector2i(46, 25),
			"mid_center": Vector2i(44, 37), "mid_entry": Vector2i(48, 72), "mid_low": Vector2i(48, 60),
			"west_t": Vector2i(30, 82), "a_lane_mid": Vector2i(17, 60), "alt_conn_a": Vector2i(30, 60),
			"a_main_stage": Vector2i(17, 38), "a_main_entry": Vector2i(16, 31),
			"a_short_stage": Vector2i(40, 31), "a_short_entry": Vector2i(24, 30),
			"east_t": Vector2i(66, 82), "b_lane_mid": Vector2i(79, 60), "alt_conn_b": Vector2i(64, 60),
			"b_main_stage": Vector2i(79, 38), "b_main_entry": Vector2i(79, 31),
			"b_short_stage": Vector2i(56, 31), "b_short_entry": Vector2i(71, 30),
			"ct_a": Vector2i(24, 10), "ct_b": Vector2i(72, 10), "ct_a_stage": Vector2i(23, 12),
			"mid_a_stage": Vector2i(36, 32), "ct_b_stage": Vector2i(72, 12), "mid_b_stage": Vector2i(60, 32),
		},
		"routes": {
			"A.main": {"site": "A", "via": ["west_t", "a_lane_mid"], "stage": "a_main_stage", "entry": "a_main_entry"},
			"A.alt": {"site": "A", "via": ["mid_entry", "alt_conn_a", "a_lane_mid"], "stage": "a_main_stage", "entry": "a_main_entry"},
			"A.short": {"site": "A", "via": ["mid_entry", "mid_low", "mid_center"], "stage": "a_short_stage", "entry": "a_short_entry"},
			"B.main": {"site": "B", "via": ["east_t", "b_lane_mid"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"B.alt": {"site": "B", "via": ["mid_entry", "alt_conn_b", "b_lane_mid"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"B.short": {"site": "B", "via": ["mid_entry", "mid_low", "mid_center"], "stage": "b_short_stage", "entry": "b_short_entry"},
			"lurk": {"site": "", "via": ["mid_entry"], "stage": "mid_low", "entry": ""},
		},
		"site_info": {
			"A": {
				"plant": [Vector2i(14, 20), Vector2i(20, 24), Vector2i(8, 16)],
				"ct_holds": [[Vector2i(12, 24), "a_main_entry"], [Vector2i(20, 26), "a_short_entry"], [Vector2i(8, 20), "a_main_entry"]],
				"t_cover": [[Vector2i(11, 22), "ct_a"], [Vector2i(20, 20), "ct_a"], [Vector2i(13, 29), "a_short_entry"], [Vector2i(22, 28), "ct_a"]],
				"retake": ["ct_a_stage", "mid_a_stage"],
				"flank": ["mid_center", "mid_low", "alt_conn_a", "a_lane_mid"],
				"main_route": "A.main", "alt_route": "A.alt", "short_route": "A.short",
			},
			"B": {
				"plant": [Vector2i(81, 20), Vector2i(75, 24), Vector2i(87, 16)],
				"ct_holds": [[Vector2i(83, 24), "b_main_entry"], [Vector2i(75, 26), "b_short_entry"], [Vector2i(87, 20), "b_main_entry"]],
				"t_cover": [[Vector2i(84, 22), "ct_b"], [Vector2i(75, 20), "ct_b"], [Vector2i(82, 29), "b_short_entry"], [Vector2i(73, 28), "ct_b"]],
				"retake": ["ct_b_stage", "mid_b_stage"],
				"flank": ["mid_center", "mid_low", "alt_conn_b", "b_lane_mid"],
				"main_route": "B.main", "alt_route": "B.alt", "short_route": "B.short",
			},
		},
	}
