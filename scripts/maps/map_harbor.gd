extends RefCounted
## Harbor: T west, CT east.
##   A "Warehouse" (north-east): reached along the north Dock lane, by the
##   alley from the courtyard up to the dock, or Short A from the courtyard.
##   Mid is a big open container courtyard.
##   B "Pier" (south-east): the South Road, the south alley from the
##   courtyard down to the road, or Short B from the courtyard.


static func data() -> Dictionary:
	return {
		"name": "Harbor",
		"size": Vector2i(104, 68),
		"round_time": 140.0,
		"tempo": 1.6,
		"floors": [
			Rect2i(3, 28, 12, 12), # T spawn
			Rect2i(88, 28, 12, 12), # CT spawn
			Rect2i(58, 6, 22, 16), # A warehouse
			Rect2i(60, 46, 22, 16), # B pier
			Rect2i(7, 14, 5, 14), # T north exit
			Rect2i(7, 8, 51, 5), # Dock lane
			Rect2i(15, 31, 14, 6), # T -> courtyard
			Rect2i(29, 24, 26, 20), # Courtyard
			Rect2i(55, 24, 8, 5), # Short A corridor
			Rect2i(58, 22, 5, 3), # Short A into warehouse
			Rect2i(32, 13, 5, 11), # North alley: courtyard <-> dock
			Rect2i(7, 40, 5, 16), # T south exit
			Rect2i(7, 56, 53, 5), # South road
			Rect2i(55, 40, 8, 5), # Short B corridor
			Rect2i(60, 44, 5, 2), # Short B onto pier
			Rect2i(36, 44, 5, 12), # South alley: courtyard <-> road
			Rect2i(55, 32, 33, 5), # Courtyard -> CT
			Rect2i(80, 12, 8, 6), # CT -> A (upper)
			Rect2i(82, 18, 6, 14), # CT -> A (opens straight out of spawn)
			Rect2i(82, 37, 6, 15), # CT -> B (opens straight out of spawn)
			Rect2i(70, 22, 4, 10), # CT mid -> A (second CT door into the site)
			Rect2i(70, 37, 4, 9), # CT mid -> B (second CT door into the site)
		],
		"cover": [
			Rect2i(34, 28, 4, 2), Rect2i(44, 30, 2, 4), Rect2i(38, 36, 4, 2), Rect2i(48, 39, 3, 2), Rect2i(31, 40, 2, 2), # Containers
			Rect2i(20, 8, 2, 2), Rect2i(40, 11, 3, 2), Rect2i(50, 8, 2, 2), # Dock
			Rect2i(63, 10, 3, 3), Rect2i(70, 14, 2, 3), Rect2i(75, 9, 3, 2), Rect2i(64, 18, 2, 2), # Warehouse
			Rect2i(66, 50, 2, 6), Rect2i(75, 49, 2, 6), Rect2i(70, 57, 3, 2), # Pier
			Rect2i(25, 58, 2, 2), Rect2i(46, 56, 2, 2), # Road
			Rect2i(77, 33, 2, 2), # CT mid lane (clear of the site doors)
		],
		"sites": {"A": Rect2i(60, 7, 18, 13), "B": Rect2i(62, 47, 18, 13)},
		"spawns": [
			[Vector2i(6, 31), Vector2i(6, 34), Vector2i(6, 37), Vector2i(10, 32), Vector2i(10, 36)],
			[Vector2i(91, 31), Vector2i(91, 34), Vector2i(91, 37), Vector2i(95, 32), Vector2i(95, 36)],
		],
		"points": {
			"ct_spawn": Vector2i(93, 34), "ct_mid": Vector2i(80, 34), "mid_hold": Vector2i(73, 34),
			"mid_center": Vector2i(41, 33), "mid_entry": Vector2i(18, 33),
			"north_t": Vector2i(9, 20), "dock_mid": Vector2i(28, 10), "alt_mid": Vector2i(34, 18),
			"alt_top": Vector2i(34, 11), "a_long_stage": Vector2i(54, 10), "a_long_entry": Vector2i(58, 10),
			"a_short_stage": Vector2i(57, 26), "a_short_entry": Vector2i(60, 21),
			"road_south": Vector2i(9, 48), "road_mid": Vector2i(30, 58), "b_alt_mid": Vector2i(38, 50),
			"b_main_stage": Vector2i(56, 58), "b_main_entry": Vector2i(60, 58),
			"b_short_stage": Vector2i(58, 42), "b_short_entry": Vector2i(62, 46),
			"ct_a": Vector2i(84, 16), "ct_b": Vector2i(84, 46), "ct_a_stage": Vector2i(85, 22),
			"mid_a_stage": Vector2i(58, 26), "a_door_stage": Vector2i(71, 28), "b_door_stage": Vector2i(71, 40), "ct_b_stage": Vector2i(85, 42), "mid_b_stage": Vector2i(58, 42),
		},
		"routes": {
			"A.main": {"site": "A", "via": ["north_t", "dock_mid"], "stage": "a_long_stage", "entry": "a_long_entry"},
			"A.alt": {"site": "A", "via": ["mid_entry", "alt_mid", "alt_top"], "stage": "a_long_stage", "entry": "a_long_entry"},
			"A.short": {"site": "A", "via": ["mid_entry", "mid_center"], "stage": "a_short_stage", "entry": "a_short_entry"},
			"B.main": {"site": "B", "via": ["road_south", "road_mid"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"B.alt": {"site": "B", "via": ["mid_entry", "b_alt_mid"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"B.short": {"site": "B", "via": ["mid_entry", "mid_center"], "stage": "b_short_stage", "entry": "b_short_entry"},
			"lurk": {"site": "", "via": ["mid_entry"], "stage": "mid_center", "entry": ""},
		},
		"site_info": {
			"A": {
				"plant": [Vector2i(68, 12), Vector2i(73, 17), Vector2i(61, 8)],
				"ct_holds": [[Vector2i(77, 7), "a_long_entry"], [Vector2i(74, 19), "a_short_entry"], [Vector2i(68, 8), "a_long_entry"]],
				"t_cover": [[Vector2i(76, 13), "ct_a"], [Vector2i(66, 15), "a_short_entry"], [Vector2i(72, 7), "ct_a"], [Vector2i(62, 19), "a_short_entry"]],
				"retake": ["ct_a_stage", "a_door_stage", "mid_a_stage"],
				"flank": ["mid_center", "alt_mid", "alt_top", "a_long_stage"],
				"main_route": "A.main", "alt_route": "A.alt", "short_route": "A.short",
			},
			"B": {
				"plant": [Vector2i(70, 52), Vector2i(78, 56), Vector2i(64, 48)],
				"ct_holds": [[Vector2i(79, 60), "b_main_entry"], [Vector2i(79, 47), "b_short_entry"], [Vector2i(72, 50), "b_short_entry"]],
				"t_cover": [[Vector2i(79, 51), "ct_b"], [Vector2i(68, 48), "b_short_entry"], [Vector2i(73, 60), "ct_b"], [Vector2i(63, 55), "b_short_entry"]],
				"retake": ["ct_b_stage", "b_door_stage", "mid_b_stage"],
				"flank": ["mid_center", "b_alt_mid", "b_main_stage"],
				"main_route": "B.main", "alt_route": "B.alt", "short_route": "B.short",
			},
		},
	}
