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
			Rect2i(7, 13, 5, 15), # T north exit (up onto the dock lane)
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
		## Walk-through buildings (see Arena.buildings): doors, rooms, furniture, glass.
		## The T lane is blocked off with wrecked cars: Ts go through the buildings
		## (Harbor Office, Cold Store, Boat Shed) to get onto the courtyard.
		"barricades": [Rect2i(23, 31, 2, 3), Rect2i(23, 34, 2, 3)],
		"buildings": [
			{ # CT side by A: in from the CT lanes, window over the A warehouse
				"name": "Harbormaster", "floor": "tiles", "rect": Rect2i(74, 22, 8, 10),
				"doors": [Rect2i(74, 27, 1, 2), Rect2i(77, 31, 2, 1)],
				"walls": [],
				"windows": [Rect2i(76, 22, 3, 1)],
				"props": [Rect2i(75, 24, 1, 2), Rect2i(79, 28, 1, 2)],
			},
			{ # CT side by B: in from the CT lanes, window over the pier
				"name": "Pump House", "floor": "tiles", "rect": Rect2i(74, 37, 8, 9),
				"doors": [Rect2i(74, 40, 1, 2), Rect2i(77, 37, 2, 1)],
				"walls": [],
				"windows": [Rect2i(76, 45, 3, 1)],
				"props": [Rect2i(75, 42, 1, 2), Rect2i(79, 39, 1, 2)],
			},
			{ # T north -> dock lane / courtyard
				"name": "Cold Store", "floor": "tiles", "rect": Rect2i(12, 13, 17, 15),
				"doors": [Rect2i(12, 18, 1, 2), Rect2i(20, 13, 2, 1), Rect2i(28, 25, 1, 2), Rect2i(17, 20, 2, 1), Rect2i(22, 16, 1, 2), Rect2i(22, 23, 1, 2)],
				"walls": [Rect2i(13, 20, 9, 1), Rect2i(22, 14, 1, 13)],
				"windows": [Rect2i(15, 13, 3, 1), Rect2i(24, 13, 3, 1)],
				"props": [Rect2i(14, 15, 2, 2), Rect2i(18, 16, 2, 1), Rect2i(14, 23, 1, 2), Rect2i(18, 24, 2, 1), Rect2i(24, 15, 2, 1), Rect2i(25, 19, 1, 3), Rect2i(24, 23, 2, 1)],
			},
			{ # T -> courtyard lane / courtyard
				"name": "Harbor Office", "floor": "wood", "rect": Rect2i(15, 37, 14, 8),
				"doors": [Rect2i(20, 37, 2, 1), Rect2i(28, 40, 1, 2)],
				"walls": [Rect2i(22, 38, 1, 3)],
				"windows": [Rect2i(28, 38, 1, 2)],
				"props": [Rect2i(17, 39, 2, 1), Rect2i(24, 41, 2, 1)],
			},
			{ # T south -> south road / south alley / courtyard: a boat hall, office in one corner, storeroom in the other
				"name": "Boat Shed", "floor": "wood", "rect": Rect2i(12, 44, 24, 12),
				"doors": [Rect2i(12, 46, 1, 2), Rect2i(31, 44, 2, 1), Rect2i(20, 55, 2, 1), Rect2i(35, 47, 1, 2), Rect2i(20, 46, 1, 2), Rect2i(31, 50, 2, 1), Rect2i(27, 52, 1, 1)],
				"walls": [Rect2i(13, 49, 7, 1), Rect2i(20, 45, 1, 5), Rect2i(28, 50, 7, 1), Rect2i(27, 50, 1, 5)],
				"windows": [Rect2i(14, 55, 3, 1), Rect2i(35, 51, 1, 2)],
				"props": [Rect2i(17, 51, 6, 2), Rect2i(24, 46, 2, 2), Rect2i(30, 46, 1, 2), Rect2i(14, 46, 2, 1), Rect2i(18, 48, 1, 1), Rect2i(30, 53, 3, 1), Rect2i(33, 51, 1, 1)],
			},
			{ # Courtyard / north alley -> dock lane, glass onto the A warehouse
				"name": "Fish Market", "floor": "tiles", "rect": Rect2i(37, 13, 21, 11),
				"doors": [Rect2i(37, 17, 2, 2), Rect2i(45, 23, 2, 1), Rect2i(53, 13, 2, 1), Rect2i(48, 20, 1, 3)],
				"walls": [Rect2i(48, 14, 1, 9)],
				"windows": [Rect2i(57, 15, 1, 4), Rect2i(42, 13, 3, 1)],
				"props": [Rect2i(40, 15, 2, 2), Rect2i(43, 20, 3, 1), Rect2i(51, 16, 2, 1), Rect2i(54, 20, 1, 2)],
			},
			{ # Courtyard / south alley -> south road, glass onto the pier
				"name": "Net Shed", "floor": "wood", "rect": Rect2i(41, 45, 19, 11),
				"doors": [Rect2i(41, 48, 1, 2), Rect2i(45, 44, 2, 2), Rect2i(53, 55, 2, 1), Rect2i(50, 46, 1, 3)],
				"walls": [Rect2i(50, 46, 1, 9)],
				"windows": [Rect2i(59, 49, 1, 4), Rect2i(44, 55, 3, 1)],
				"props": [Rect2i(43, 51, 2, 2), Rect2i(47, 47, 2, 1), Rect2i(53, 48, 2, 1), Rect2i(56, 52, 1, 2)],
			},
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
			"fish": Vector2i(44, 17), "shed": Vector2i(46, 50),
			"cold_store": Vector2i(20, 22), "office": Vector2i(22, 42), "boat_shed": Vector2i(24, 50), "harbormaster": Vector2i(78, 26), "pump_house": Vector2i(78, 42),
		},
		"routes": {
			"A.main": {"site": "A", "via": ["north_t", "dock_mid"], "stage": "a_long_stage", "entry": "a_long_entry"},
			"A.alt": {"site": "A", "via": ["mid_entry", "alt_mid", "alt_top"], "stage": "a_long_stage", "entry": "a_long_entry"},
			"A.short": {"site": "A", "via": ["mid_entry", "mid_center"], "stage": "a_short_stage", "entry": "a_short_entry"},
			"B.main": {"site": "B", "via": ["road_south", "road_mid"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"B.alt": {"site": "B", "via": ["mid_entry", "b_alt_mid"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"B.short": {"site": "B", "via": ["mid_entry", "mid_center"], "stage": "b_short_stage", "entry": "b_short_entry"},
			"lurk": {"site": "", "via": ["mid_entry"], "stage": "mid_center", "entry": ""},
			"A.fish": {"site": "A", "via": ["mid_entry", "mid_center", "fish"], "stage": "a_long_stage", "entry": "a_long_entry"},
			"B.shed": {"site": "B", "via": ["mid_entry", "mid_center", "shed"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"A.cold": {"site": "A", "via": ["north_t", "cold_store"], "stage": "a_long_stage", "entry": "a_long_entry"},
			"A.office": {"site": "A", "via": ["mid_entry", "office", "mid_center"], "stage": "a_short_stage", "entry": "a_short_entry"},
			"B.boat": {"site": "B", "via": ["road_south", "boat_shed", "b_alt_mid"], "stage": "b_main_stage", "entry": "b_main_entry"},
			"B.office": {"site": "B", "via": ["mid_entry", "office", "mid_center"], "stage": "b_short_stage", "entry": "b_short_entry"},
		},
		"site_info": {
			"A": {
				"plant": [Vector2i(68, 12), Vector2i(73, 17), Vector2i(61, 8)],
				"ct_holds": [[Vector2i(77, 7), "a_long_entry"], [Vector2i(74, 19), "a_short_entry"], [Vector2i(68, 8), "a_long_entry"]],
				"t_cover": [[Vector2i(76, 13), "ct_a"], [Vector2i(66, 15), "a_short_entry"], [Vector2i(72, 7), "ct_a"], [Vector2i(62, 19), "a_short_entry"]],
				"retake": ["ct_a_stage", "a_door_stage", "mid_a_stage", "harbormaster"],
				"flank": ["mid_center", "alt_mid", "alt_top", "a_long_stage", "fish"],
				"main_route": "A.main", "alt_route": "A.alt", "short_route": "A.short", "building_routes": ["A.fish", "A.cold", "A.office"],
			},
			"B": {
				"plant": [Vector2i(70, 52), Vector2i(78, 56), Vector2i(64, 48)],
				"ct_holds": [[Vector2i(79, 60), "b_main_entry"], [Vector2i(79, 47), "b_short_entry"], [Vector2i(72, 50), "b_short_entry"]],
				"t_cover": [[Vector2i(79, 51), "ct_b"], [Vector2i(68, 48), "b_short_entry"], [Vector2i(73, 60), "ct_b"], [Vector2i(63, 55), "b_short_entry"]],
				"retake": ["ct_b_stage", "b_door_stage", "mid_b_stage", "pump_house"],
				"flank": ["mid_center", "b_alt_mid", "b_main_stage", "shed"],
				"main_route": "B.main", "alt_route": "B.alt", "short_route": "B.short", "building_routes": ["B.shed", "B.boat", "B.office"],
			},
		},
	}
