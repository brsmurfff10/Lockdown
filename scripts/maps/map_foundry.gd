extends RefCounted
## Foundry: T spawn west, CT spawn east, sites top and bottom.
##   A (north wing): the long North Lane, the low connector from the mid
##   corridor to the North Lane, or Short A from the mid hall.
##   B (south wing): mirror of A.
##   Mid: a long corridor across the middle into the mid hall in front of CT.


static func data() -> Dictionary:
	return {
		"name": "Foundry",
		"size": Vector2i(90, 96),
		"round_time": 140.0,
		"tempo": 1.6,
		"floors": [
			Rect2i(3, 40, 9, 16), # T spawn
			Rect2i(77, 40, 9, 16), # CT spawn
			Rect2i(58, 6, 18, 20), # A site (west)
			Rect2i(58, 70, 18, 20), # B site (east)
			Rect2i(12, 45, 38, 6), # Mid corridor
			Rect2i(50, 38, 12, 20), # Mid hall
			Rect2i(62, 45, 15, 6), # Mid hall -> CT
			Rect2i(5, 20, 5, 20), # T west exit
			Rect2i(5, 14, 53, 6), # West lane (A main)
			Rect2i(55, 26, 5, 12), # Short A
			Rect2i(27, 20, 5, 25), # West connector (A alt)
			Rect2i(5, 56, 5, 20), # T east exit
			Rect2i(5, 76, 53, 6), # East lane (B main)
			Rect2i(55, 58, 5, 12), # Short B
			Rect2i(27, 51, 5, 25), # East connector (B alt)
			Rect2i(79, 26, 5, 14), Rect2i(76, 20, 8, 6), # CT -> A
			Rect2i(79, 56, 5, 14), Rect2i(76, 70, 8, 6), # CT -> B
		],
		"cover": [
			Rect2i(22, 47, 2, 2), Rect2i(38, 45, 2, 2), # Mid corridor
			Rect2i(55, 42, 3, 2), Rect2i(55, 52, 3, 2), Rect2i(55, 47, 2, 2), # Mid hall
			Rect2i(18, 16, 2, 2), Rect2i(40, 14, 2, 2), # West lane
			Rect2i(18, 78, 2, 2), Rect2i(40, 80, 2, 2), # East lane
			Rect2i(69, 10, 3, 3), Rect2i(64, 17, 4, 2), Rect2i(72, 21, 2, 3), Rect2i(61, 9, 2, 3), # A site
			Rect2i(69, 83, 3, 3), Rect2i(64, 77, 4, 2), Rect2i(72, 72, 2, 3), Rect2i(61, 84, 2, 3), # B site
		],
		## Walk-through buildings (see Arena.buildings): doors, rooms, furniture, glass.
		"buildings": [
			{ # Mid hall -> A site, windows over A
				"name": "A Control Room", "floor": "plate", "rect": Rect2i(62, 26, 15, 19),
				"doors": [Rect2i(67, 26, 2, 1), Rect2i(71, 44, 2, 1), Rect2i(62, 40, 1, 2), Rect2i(70, 30, 1, 2), Rect2i(72, 35, 2, 1), Rect2i(65, 35, 2, 1)],
				"walls": [Rect2i(70, 27, 1, 8), Rect2i(63, 35, 13, 1)],
				"windows": [Rect2i(72, 26, 2, 1), Rect2i(64, 26, 2, 1)],
				"props": [Rect2i(74, 28, 1, 2), Rect2i(72, 32, 2, 1), Rect2i(64, 28, 1, 2), Rect2i(65, 32, 1, 2), Rect2i(74, 38, 1, 2), Rect2i(68, 41, 2, 1), Rect2i(64, 38, 2, 2)],
			},
			{ # Mirror of the A Control Room
				"name": "B Control Room", "floor": "plate", "rect": Rect2i(62, 51, 15, 19),
				"doors": [Rect2i(67, 69, 2, 1), Rect2i(71, 51, 2, 1), Rect2i(62, 54, 1, 2), Rect2i(70, 64, 1, 2), Rect2i(72, 60, 2, 1), Rect2i(65, 60, 2, 1)],
				"walls": [Rect2i(70, 61, 1, 8), Rect2i(63, 60, 13, 1)],
				"windows": [Rect2i(72, 69, 2, 1), Rect2i(64, 69, 2, 1)],
				"props": [Rect2i(74, 66, 1, 2), Rect2i(72, 63, 2, 1), Rect2i(64, 66, 1, 2), Rect2i(65, 62, 1, 2), Rect2i(74, 56, 1, 2), Rect2i(68, 54, 2, 1), Rect2i(64, 56, 2, 2)],
			},
			{ # West lane / connector -> mid corridor
				"name": "West Workshop", "floor": "plate", "rect": Rect2i(12, 20, 15, 25),
				"doors": [Rect2i(18, 20, 2, 1), Rect2i(22, 44, 2, 1), Rect2i(26, 30, 1, 2), Rect2i(20, 24, 1, 2), Rect2i(22, 31, 2, 1), Rect2i(15, 31, 2, 1), Rect2i(18, 37, 1, 2)],
				"walls": [Rect2i(20, 21, 1, 10), Rect2i(13, 31, 13, 1), Rect2i(18, 32, 1, 12)],
				"windows": [Rect2i(15, 44, 3, 1), Rect2i(23, 20, 2, 1)],
				"props": [Rect2i(24, 22, 1, 2), Rect2i(23, 27, 2, 1), Rect2i(15, 22, 2, 2), Rect2i(15, 27, 1, 2), Rect2i(24, 34, 1, 2), Rect2i(21, 40, 2, 1), Rect2i(15, 34, 1, 2), Rect2i(15, 40, 2, 1)],
			},
			{ # Mirror of the West Workshop
				"name": "East Workshop", "floor": "plate", "rect": Rect2i(12, 51, 15, 25),
				"doors": [Rect2i(18, 75, 2, 1), Rect2i(22, 51, 2, 1), Rect2i(26, 64, 1, 2), Rect2i(20, 70, 1, 2), Rect2i(22, 64, 2, 1), Rect2i(15, 64, 2, 1), Rect2i(18, 57, 1, 2)],
				"walls": [Rect2i(20, 65, 1, 10), Rect2i(13, 64, 13, 1), Rect2i(18, 52, 1, 12)],
				"windows": [Rect2i(15, 51, 3, 1), Rect2i(23, 75, 2, 1)],
				"props": [Rect2i(24, 72, 1, 2), Rect2i(23, 68, 2, 1), Rect2i(15, 72, 2, 2), Rect2i(15, 67, 1, 2), Rect2i(24, 60, 1, 2), Rect2i(21, 55, 2, 1), Rect2i(15, 60, 1, 2), Rect2i(15, 55, 2, 1)],
			},
			{ # Mid corridor / mid hall -> West Lane: casting hall, glass onto both
				"name": "West Hall", "floor": "plate", "rect": Rect2i(32, 20, 18, 25),
				"doors": [Rect2i(32, 30, 1, 2), Rect2i(44, 20, 2, 1), Rect2i(36, 44, 2, 1), Rect2i(49, 40, 1, 2), Rect2i(42, 32, 2, 1)],
				"walls": [Rect2i(41, 21, 1, 12), Rect2i(42, 32, 7, 1)],
				"windows": [Rect2i(42, 44, 4, 1), Rect2i(37, 20, 3, 1)],
				"props": [Rect2i(45, 24, 2, 3), Rect2i(44, 36, 2, 2), Rect2i(36, 26, 2, 3), Rect2i(36, 37, 1, 3), Rect2i(41, 40, 2, 1)],
			},
			{ # Mirror of the West Hall
				"name": "East Hall", "floor": "plate", "rect": Rect2i(32, 51, 18, 25),
				"doors": [Rect2i(32, 64, 1, 2), Rect2i(44, 75, 2, 1), Rect2i(36, 51, 2, 1), Rect2i(49, 54, 1, 2), Rect2i(42, 63, 2, 1)],
				"walls": [Rect2i(41, 63, 1, 12), Rect2i(42, 63, 7, 1)],
				"windows": [Rect2i(42, 51, 4, 1), Rect2i(37, 75, 3, 1)],
				"props": [Rect2i(45, 69, 2, 3), Rect2i(44, 58, 2, 2), Rect2i(36, 67, 2, 3), Rect2i(36, 56, 1, 3), Rect2i(41, 55, 2, 1)],
			},
		],
		"sites": {"A": Rect2i(59, 7, 16, 18), "B": Rect2i(59, 71, 16, 18)},
		"spawns": [
			[Vector2i(8, 43), Vector2i(8, 47), Vector2i(8, 51), Vector2i(5, 45), Vector2i(5, 49)],
			[Vector2i(82, 43), Vector2i(82, 47), Vector2i(82, 51), Vector2i(79, 45), Vector2i(79, 49)],
		],
		"points": {
			"ct_spawn": Vector2i(81, 48), "ct_mid": Vector2i(71, 48), "mid_hold": Vector2i(64, 46),
			"mid_center": Vector2i(52, 44), "mid_entry": Vector2i(17, 48), "mid_low": Vector2i(29, 48),
			"west_t": Vector2i(7, 30), "a_lane_mid": Vector2i(29, 17), "alt_conn_a": Vector2i(29, 30),
			"a_main_stage": Vector2i(51, 17), "a_main_entry": Vector2i(58, 16),
			"a_short_stage": Vector2i(58, 40), "a_short_entry": Vector2i(59, 24),
			"east_t": Vector2i(7, 66), "b_lane_mid": Vector2i(29, 79), "alt_conn_b": Vector2i(29, 64),
			"b_main_stage": Vector2i(51, 79), "b_main_entry": Vector2i(58, 79),
			"b_short_stage": Vector2i(58, 56), "b_short_entry": Vector2i(59, 71),
			"ct_a": Vector2i(79, 24), "ct_b": Vector2i(79, 72), "ct_a_stage": Vector2i(77, 23),
			"mid_a_stage": Vector2i(57, 36), "ct_b_stage": Vector2i(77, 72), "mid_b_stage": Vector2i(57, 60),
			"w_hall": Vector2i(44, 28), "e_hall": Vector2i(44, 67),
			"w_workshop": Vector2i(20, 33), "e_workshop": Vector2i(20, 62), "a_control": Vector2i(69, 37), "b_control": Vector2i(68, 62), "a_control_exit": Vector2i(67, 24), "b_control_exit": Vector2i(67, 71),
		},
		"routes": {
			"A.main": {"site": "A", "via": ["west_t", "a_lane_mid"], "stage": "a_main_stage", "entry": "a_main_entry"},
			"A.alt": {"site": "A", "via": ["mid_entry", "alt_conn_a", "a_lane_mid"], "stage": "a_main_stage", "entry": "a_main_entry"},
			"A.short": {"site": "A", "via": ["mid_entry", "mid_low", "mid_center"], "stage": "a_short_stage", "entry": "a_short_entry"},
			"B.main": {"site": "B", "via": ["east_t", "b_lane_mid"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"B.alt": {"site": "B", "via": ["mid_entry", "alt_conn_b", "b_lane_mid"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"B.short": {"site": "B", "via": ["mid_entry", "mid_low", "mid_center"], "stage": "b_short_stage", "entry": "b_short_entry"},
			"lurk": {"site": "", "via": ["mid_entry"], "stage": "mid_low", "entry": ""},
			"A.hall": {"site": "A", "via": ["mid_entry", "mid_low", "w_hall"], "stage": "a_main_stage", "entry": "a_main_entry"},
			"B.hall": {"site": "B", "via": ["mid_entry", "mid_low", "e_hall"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"A.workshop": {"site": "A", "via": ["west_t", "w_workshop", "a_lane_mid"], "stage": "a_main_stage", "entry": "a_main_entry"},
			"B.workshop": {"site": "B", "via": ["east_t", "e_workshop", "b_lane_mid"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"A.control": {"site": "A", "via": ["mid_entry", "mid_low", "mid_center"], "stage": "a_control", "entry": "a_control_exit"},
			"B.control": {"site": "B", "via": ["mid_entry", "mid_low", "mid_center"], "stage": "b_control", "entry": "b_control_exit"},
		},
		"site_info": {
			"A": {
				"plant": [Vector2i(69, 14), Vector2i(65, 20), Vector2i(73, 8)],
				"ct_holds": [[Vector2i(65, 12), "a_main_entry"], [Vector2i(63, 20), "a_short_entry"], [Vector2i(69, 8), "a_main_entry"]],
				"t_cover": [[Vector2i(67, 11), "ct_a"], [Vector2i(69, 20), "ct_a"], [Vector2i(60, 13), "a_short_entry"], [Vector2i(61, 22), "ct_a"]],
				"retake": ["ct_a_stage", "mid_a_stage", "a_control"],
				"flank": ["mid_center", "mid_low", "alt_conn_a", "a_lane_mid", "w_hall"],
				"main_route": "A.main", "alt_route": "A.alt", "short_route": "A.short", "building_routes": ["A.hall", "A.workshop", "A.control"],
			},
			"B": {
				"plant": [Vector2i(69, 81), Vector2i(65, 75), Vector2i(73, 87)],
				"ct_holds": [[Vector2i(65, 83), "b_main_entry"], [Vector2i(63, 75), "b_short_entry"], [Vector2i(69, 87), "b_main_entry"]],
				"t_cover": [[Vector2i(67, 84), "ct_b"], [Vector2i(69, 75), "ct_b"], [Vector2i(60, 82), "b_short_entry"], [Vector2i(61, 73), "ct_b"]],
				"retake": ["ct_b_stage", "mid_b_stage", "b_control"],
				"flank": ["mid_center", "mid_low", "alt_conn_b", "b_lane_mid", "e_hall"],
				"main_route": "B.main", "alt_route": "B.alt", "short_route": "B.short", "building_routes": ["B.hall", "B.workshop", "B.control"],
			},
		},
	}
