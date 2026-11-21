extends RefCounted
## Cage: the training yard. T west, CT east (scaled up 1.5x from the original small map).


static func data() -> Dictionary:
	return {
		"name": "Cage",
		"size": Vector2i(84, 51),
		"round_time": 130.0,
		"tempo": 1.35,
		"floors": [
			Rect2i(3, 18, 12, 15), Rect2i(6, 6, 6, 12), Rect2i(6, 4, 45, 6), Rect2i(51, 3, 21, 17),
			Rect2i(6, 33, 6, 11), Rect2i(6, 39, 42, 6), Rect2i(48, 32, 21, 16), Rect2i(15, 22, 45, 6),
			Rect2i(57, 22, 12, 6), Rect2i(69, 20, 12, 12), Rect2i(69, 10, 9, 10), Rect2i(69, 32, 9, 7),
			Rect2i(39, 10, 5, 12), Rect2i(33, 28, 5, 11), Rect2i(50, 18, 4, 4), Rect2i(50, 28, 4, 4),
		],
		"cover": [
			Rect2i(28, 5, 2, 2), Rect2i(58, 8, 2, 2), Rect2i(65, 14, 2, 2), Rect2i(54, 16, 1, 2),
			Rect2i(54, 36, 2, 2), Rect2i(62, 42, 2, 2), Rect2i(60, 34, 1, 2),
			Rect2i(30, 23, 2, 2), Rect2i(54, 26, 1, 2), Rect2i(24, 40, 2, 2),
			Rect2i(26, 25, 1, 3), Rect2i(40, 23, 3, 3), Rect2i(57, 22, 1, 3), # Mid: T-side barrier low, crate stack under cat, CT-side barrier high (no spawn-to-spawn shots)
		],
		## Walk-through buildings (see Arena.buildings): doors, rooms, furniture, glass.
		"buildings": [
			{ # T spawn -> tunnels / lower mid, windows onto mid and the tunnels
				"name": "Yard Office", "floor": "tiles", "rect": Rect2i(15, 28, 18, 11),
				"doors": [Rect2i(15, 30, 1, 2), Rect2i(20, 38, 2, 1), Rect2i(32, 34, 1, 2), Rect2i(23, 30, 1, 2), Rect2i(23, 35, 1, 2), Rect2i(27, 33, 2, 1)],
				"walls": [Rect2i(23, 29, 1, 9), Rect2i(24, 33, 8, 1)],
				"windows": [Rect2i(18, 28, 3, 1), Rect2i(27, 38, 3, 1)],
				"props": [Rect2i(17, 31, 2, 1), Rect2i(19, 35, 1, 2), Rect2i(25, 30, 2, 1), Rect2i(29, 35, 2, 1), Rect2i(17, 36, 2, 1)],
			},
			{ # Lower mid / tunnels -> B, windows onto mid
				"name": "Armory", "floor": "tiles", "rect": Rect2i(38, 28, 10, 11),
				"doors": [Rect2i(38, 32, 1, 2), Rect2i(47, 35, 1, 2), Rect2i(42, 38, 2, 1)],
				"walls": [Rect2i(43, 29, 1, 4)],
				"windows": [Rect2i(40, 28, 3, 1)],
				"props": [Rect2i(40, 30, 2, 1), Rect2i(45, 30, 1, 2), Rect2i(40, 35, 1, 2), Rect2i(44, 36, 2, 1)],
			},
			{ # Catwalk -> A, window over A
				"name": "Gatehouse", "floor": "wood", "rect": Rect2i(44, 10, 7, 9),
				"doors": [Rect2i(44, 13, 1, 2), Rect2i(50, 15, 1, 2)],
				"walls": [],
				"windows": [Rect2i(50, 11, 1, 2)],
				"props": [Rect2i(46, 12, 1, 1), Rect2i(48, 16, 1, 1)],
			},
			{ # T north -> catwalk / long, glass onto long
				"name": "Barracks", "floor": "wood", "rect": Rect2i(15, 10, 24, 11),
				"doors": [Rect2i(12, 15, 4, 1), Rect2i(24, 10, 3, 1), Rect2i(38, 15, 1, 3)],
				"walls": [Rect2i(27, 12, 1, 4)],
				"windows": [Rect2i(30, 10, 4, 1)],
				"props": [Rect2i(18, 12, 2, 1), Rect2i(32, 17, 2, 1), Rect2i(21, 18, 1, 1)],
			},
		],
		"sites": {"A": Rect2i(54, 4, 15, 14), "B": Rect2i(51, 33, 15, 13)},
		"spawns": [
			[Vector2i(6, 20), Vector2i(6, 24), Vector2i(6, 29), Vector2i(11, 21), Vector2i(11, 27)],
			[Vector2i(72, 21), Vector2i(72, 26), Vector2i(72, 29), Vector2i(77, 23), Vector2i(77, 27)],
		],
		"points": {
			"t_north": Vector2i(8, 14), "t_south": Vector2i(8, 36), "long_mid": Vector2i(23, 8),
			"long_stage": Vector2i(44, 6), "a_long_entry": Vector2i(51, 6), "cat_bottom": Vector2i(41, 21),
			"cat_top": Vector2i(41, 11), "mid_entry": Vector2i(18, 24), "mid_center": Vector2i(38, 26),
			"shortA_stage": Vector2i(47, 23), "a_short_entry": Vector2i(51, 20), "shortB_stage": Vector2i(47, 27),
			"b_short_entry": Vector2i(51, 30), "lower_top": Vector2i(35, 29), "lower_bottom": Vector2i(35, 38),
			"tunnels_mid": Vector2i(18, 42), "tunnels_stage": Vector2i(42, 42), "b_tunnel_entry": Vector2i(48, 42),
			"ct_spawn": Vector2i(74, 24), "ct_a": Vector2i(72, 17), "ct_b": Vector2i(72, 33),
			"ct_mid": Vector2i(63, 24), "mid_hold": Vector2i(59, 24), "ct_a_stage": Vector2i(74, 18),
			"mid_a_stage": Vector2i(56, 23), "ct_b_stage": Vector2i(74, 32), "mid_b_stage": Vector2i(56, 27),
			"barracks": Vector2i(23, 15),
			"yard_office": Vector2i(25, 35), "armory": Vector2i(43, 34), "armory_exit": Vector2i(49, 35), "gatehouse": Vector2i(47, 14), "gate_exit": Vector2i(52, 15),
		},
		"routes": {
			"A.main": {"site": "A", "via": ["t_north", "long_mid"], "stage": "long_stage", "entry": "a_long_entry"},
			"A.alt": {"site": "A", "via": ["mid_entry", "cat_bottom", "cat_top"], "stage": "long_stage", "entry": "a_long_entry"},
			"A.short": {"site": "A", "via": ["mid_entry", "mid_center"], "stage": "shortA_stage", "entry": "a_short_entry"},
			"B.main": {"site": "B", "via": ["t_south", "tunnels_mid"], "stage": "tunnels_stage", "entry": "b_tunnel_entry"},
			"B.alt": {"site": "B", "via": ["mid_entry", "lower_top", "lower_bottom"], "stage": "tunnels_stage", "entry": "b_tunnel_entry"},
			"B.short": {"site": "B", "via": ["mid_entry", "mid_center"], "stage": "shortB_stage", "entry": "b_short_entry"},
			"lurk": {"site": "", "via": ["mid_entry"], "stage": "mid_center", "entry": ""},
			"A.barracks": {"site": "A", "via": ["t_north", "barracks", "cat_top"], "stage": "long_stage", "entry": "a_long_entry"},
			"B.yard": {"site": "B", "via": ["yard_office", "lower_bottom"], "stage": "tunnels_stage", "entry": "b_tunnel_entry"},
			"B.armory": {"site": "B", "via": ["mid_entry", "lower_top"], "stage": "armory", "entry": "armory_exit"},
			"A.gate": {"site": "A", "via": ["mid_entry", "cat_bottom"], "stage": "gatehouse", "entry": "gate_exit"},
		},
		"site_info": {
			"A": {
				"plant": [Vector2i(59, 11), Vector2i(62, 15), Vector2i(56, 6)],
				"ct_holds": [[Vector2i(68, 6), "a_long_entry"], [Vector2i(62, 17), "a_short_entry"], [Vector2i(69, 9), "a_long_entry"]],
				"t_cover": [[Vector2i(66, 11), "ct_a"], [Vector2i(56, 12), "a_short_entry"], [Vector2i(62, 6), "ct_a"], [Vector2i(53, 9), "ct_a"]],
				"retake": ["ct_a_stage", "mid_a_stage"],
				"flank": ["mid_center", "cat_bottom", "cat_top", "long_stage", "barracks"],
				"main_route": "A.main", "alt_route": "A.alt", "short_route": "A.short", "building_routes": ["A.barracks", "A.gate"],
			},
			"B": {
				"plant": [Vector2i(57, 39), Vector2i(60, 42), Vector2i(53, 35)],
				"ct_holds": [[Vector2i(66, 39), "b_tunnel_entry"], [Vector2i(64, 42), "b_short_entry"], [Vector2i(60, 36), "b_short_entry"]],
				"t_cover": [[Vector2i(63, 38), "ct_b"], [Vector2i(54, 33), "b_short_entry"], [Vector2i(59, 45), "ct_b"], [Vector2i(51, 41), "ct_b"]],
				"retake": ["ct_b_stage", "mid_b_stage"],
				"flank": ["mid_center", "lower_top", "lower_bottom", "tunnels_stage"],
				"main_route": "B.main", "alt_route": "B.alt", "short_route": "B.short", "building_routes": ["B.yard", "B.armory"],
			},
		},
	}
