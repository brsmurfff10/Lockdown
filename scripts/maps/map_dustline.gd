extends RefCounted
## Dustline: big classic layout. T west, CT east.
##   A (north-east): Long A along the top with doors at the end, Short A up
##   the catwalk from the mid hall, and the "connector" between long and mid.
##   B (south-east): tunnels with an upper tunnel room, and B short from the
##   mid hall; lower-mid links mid to the tunnel room.


static func data() -> Dictionary:
	return {
		"name": "Dustline",
		"size": Vector2i(100, 64),
		"round_time": 140.0,
		"tempo": 1.6,
		"floors": [
			Rect2i(3, 26, 12, 14), # T spawn
			Rect2i(84, 26, 12, 12), # CT spawn
			Rect2i(66, 4, 20, 16), # A site
			Rect2i(64, 44, 20, 16), # B site
			Rect2i(7, 11, 5, 15), # T north exit (up into Long A)
			Rect2i(7, 6, 59, 5), # Long A (to the doors / site)
			Rect2i(15, 30, 30, 5), # Mid corridor
			Rect2i(45, 26, 12, 13), # Mid hall
			Rect2i(57, 30, 27, 5), # Mid -> CT
			Rect2i(50, 14, 5, 12), # Short A catwalk (up from mid hall)
			Rect2i(50, 14, 16, 4), # Short A into site
			Rect2i(36, 11, 5, 19), # Connector: long <-> mid
			Rect2i(7, 40, 5, 12), # T south exit
			Rect2i(7, 52, 30, 5), # Tunnels
			Rect2i(28, 44, 9, 8), # Upper tunnel room
			Rect2i(37, 50, 27, 5), # Tunnels -> B
			Rect2i(50, 39, 5, 8), # B short (down from mid hall)
			Rect2i(50, 44, 14, 4), # B short into site
			Rect2i(32, 35, 5, 9), # Lower mid: mid corridor <-> tunnel room
			Rect2i(84, 12, 6, 14), # CT -> A
			Rect2i(84, 38, 6, 12), # CT -> B
		],
		"cover": [
			Rect2i(22, 6, 3, 2), Rect2i(44, 9, 2, 2), Rect2i(58, 6, 2, 1), Rect2i(58, 10, 2, 1), # Long + doors
			Rect2i(71, 11, 3, 3), Rect2i(77, 12, 2, 4), Rect2i(80, 6, 3, 2), Rect2i(69, 17, 2, 2), # A site
			Rect2i(48, 28, 2, 2), Rect2i(53, 35, 2, 2), Rect2i(66, 30, 2, 2), # Mid
			Rect2i(18, 52, 2, 2), Rect2i(31, 47, 2, 2), # Tunnels
			Rect2i(68, 48, 3, 3), Rect2i(76, 53, 2, 3), Rect2i(79, 46, 3, 2), Rect2i(71, 57, 3, 2), # B site
		],
		## Walk-through buildings (see Arena.buildings): doors, rooms, furniture, glass.
		## Mid gates: two staggered metal gates so nobody shoots straight out of T spawn down mid (walk the zig-zag).
		"gates": [Rect2i(24, 30, 1, 3), Rect2i(27, 32, 1, 3)],
		"buildings": [
			{ # T north -> connector / long: rooms and a hall, windows onto the connector
				"name": "Hotel", "floor": "wood", "rect": Rect2i(12, 12, 24, 14),
				"doors": [Rect2i(12, 16, 1, 2), Rect2i(35, 20, 1, 2), Rect2i(24, 11, 2, 2), Rect2i(23, 15, 1, 2), Rect2i(23, 21, 1, 2), Rect2i(29, 19, 2, 1), Rect2i(17, 18, 2, 1)],
				"walls": [Rect2i(13, 18, 10, 1), Rect2i(23, 13, 1, 12), Rect2i(24, 19, 11, 1)],
				"windows": [Rect2i(35, 14, 1, 3), Rect2i(12, 21, 1, 3)],
				"props": [Rect2i(14, 14, 2, 1), Rect2i(19, 15, 2, 2), Rect2i(14, 22, 1, 2), Rect2i(18, 21, 2, 1), Rect2i(26, 15, 2, 1), Rect2i(31, 14, 1, 2), Rect2i(26, 22, 2, 2), Rect2i(32, 22, 2, 1)],
			},
			{ # T spawn -> mid corridor, windows onto mid
				"name": "Garage", "floor": "tiles", "rect": Rect2i(15, 25, 21, 5),
				"doors": [Rect2i(15, 27, 1, 1), Rect2i(28, 29, 2, 1)],
				"walls": [],
				"windows": [Rect2i(20, 29, 4, 1)],
				"props": [Rect2i(18, 26, 2, 1), Rect2i(24, 27, 3, 1), Rect2i(32, 26, 2, 1)],
			},
			{ # T spawn -> mid corridor / lower mid
				"name": "Shop", "floor": "tiles", "rect": Rect2i(15, 35, 17, 6),
				"doors": [Rect2i(15, 37, 1, 2), Rect2i(20, 35, 2, 1), Rect2i(31, 37, 1, 2)],
				"walls": [Rect2i(23, 36, 1, 2)],
				"windows": [Rect2i(25, 35, 3, 1)],
				"props": [Rect2i(17, 36, 2, 1), Rect2i(26, 38, 3, 1)],
			},
			{ # T south exit -> tunnels / tunnel room
				"name": "Corner House", "floor": "wood", "rect": Rect2i(12, 40, 16, 12),
				"doors": [Rect2i(12, 44, 1, 2), Rect2i(18, 51, 2, 1), Rect2i(27, 47, 1, 2), Rect2i(16, 45, 2, 1), Rect2i(21, 42, 1, 2), Rect2i(21, 48, 1, 2)],
				"walls": [Rect2i(13, 45, 8, 1), Rect2i(21, 41, 1, 10)],
				"windows": [Rect2i(22, 51, 3, 1), Rect2i(27, 43, 1, 2)],
				"props": [Rect2i(14, 42, 2, 1), Rect2i(18, 42, 1, 2), Rect2i(14, 48, 2, 2), Rect2i(18, 49, 2, 1), Rect2i(23, 42, 2, 1), Rect2i(24, 46, 1, 2), Rect2i(23, 49, 2, 1)],
			},
			{ # Mid -> A: the covered market between the mid road and A, CT door at the back
				"name": "Market", "floor": "tiles", "rect": Rect2i(57, 20, 26, 10),
				"doors": [Rect2i(62, 29, 2, 1), Rect2i(69, 20, 2, 1), Rect2i(82, 23, 2, 2), Rect2i(72, 25, 1, 2)],
				"walls": [Rect2i(72, 21, 1, 8)],
				"windows": [Rect2i(75, 20, 5, 1), Rect2i(66, 29, 3, 1)],
				"props": [Rect2i(59, 22, 2, 1), Rect2i(64, 25, 2, 2), Rect2i(76, 23, 3, 1), Rect2i(79, 26, 1, 2)],
			},
			{ # Mid road -> B: flats with windows over B
				"name": "Apartments", "floor": "wood", "rect": Rect2i(57, 35, 26, 9),
				"doors": [Rect2i(60, 35, 2, 1), Rect2i(77, 35, 2, 1), Rect2i(68, 43, 2, 1), Rect2i(66, 40, 1, 2)],
				"walls": [Rect2i(66, 36, 1, 7), Rect2i(74, 36, 1, 4)],
				"windows": [Rect2i(72, 43, 4, 1), Rect2i(78, 43, 3, 1)],
				"props": [Rect2i(59, 40, 2, 1), Rect2i(63, 37, 2, 1), Rect2i(69, 37, 2, 1), Rect2i(80, 38, 1, 2), Rect2i(77, 41, 2, 1)],
			},
			{ # Lower mid -> B short, window onto the tunnels
				"name": "Tunnel House", "floor": "wood", "rect": Rect2i(37, 39, 13, 11),
				"doors": [Rect2i(37, 42, 1, 2), Rect2i(49, 46, 1, 2)],
				"walls": [Rect2i(43, 40, 1, 5)],
				"windows": [Rect2i(41, 49, 4, 1)],
				"props": [Rect2i(39, 46, 2, 2), Rect2i(46, 41, 2, 1)],
			},
		],
		"sites": {"A": Rect2i(68, 5, 16, 13), "B": Rect2i(66, 45, 16, 13)},
		"spawns": [
			[Vector2i(6, 29), Vector2i(6, 33), Vector2i(6, 37), Vector2i(10, 31), Vector2i(10, 35)],
			[Vector2i(88, 28), Vector2i(88, 31), Vector2i(88, 34), Vector2i(92, 29), Vector2i(92, 33)],
		],
		"points": {
			"ct_spawn": Vector2i(89, 31), "ct_mid": Vector2i(78, 32), "mid_hold": Vector2i(70, 32),
			"mid_center": Vector2i(51, 32), "mid_entry": Vector2i(17, 32),
			"t_north": Vector2i(9, 18), "long_mid": Vector2i(30, 8), "long_cat_top": Vector2i(38, 8),
			"cat_mid": Vector2i(38, 20), "a_long_stage": Vector2i(52, 8), "a_long_entry": Vector2i(66, 8),
			"a_short_stage": Vector2i(52, 20), "a_short_entry": Vector2i(66, 15),
			"t_south": Vector2i(9, 46), "tunnels_mid": Vector2i(22, 54), "tunnel_room": Vector2i(34, 48),
			"lower_top": Vector2i(34, 37), "b_tunnel_stage": Vector2i(58, 52), "b_tunnel_entry": Vector2i(64, 52),
			"b_short_stage": Vector2i(52, 42), "b_short_entry": Vector2i(64, 45),
			"ct_a": Vector2i(86, 22), "ct_b": Vector2i(86, 42), "ct_a_stage": Vector2i(86, 24),
			"mid_a_stage": Vector2i(52, 23), "ct_b_stage": Vector2i(86, 40), "mid_b_stage": Vector2i(52, 41),
			"market": Vector2i(66, 24), "market_stage": Vector2i(69, 22), "a_market_entry": Vector2i(68, 18),
			"apts_hall": Vector2i(61, 38), "apts_stage": Vector2i(69, 41), "b_apts_entry": Vector2i(69, 45),
			"house": Vector2i(45, 44),
			"hotel": Vector2i(25, 17), "garage": Vector2i(28, 27), "shop": Vector2i(21, 38), "corner_house": Vector2i(19, 47),
		},
		"routes": {
			"A.main": {"site": "A", "via": ["t_north", "long_mid"], "stage": "a_long_stage", "entry": "a_long_entry"},
			"A.alt": {"site": "A", "via": ["mid_entry", "cat_mid", "long_cat_top"], "stage": "a_long_stage", "entry": "a_long_entry"},
			"A.short": {"site": "A", "via": ["mid_entry", "mid_center"], "stage": "a_short_stage", "entry": "a_short_entry"},
			"B.main": {"site": "B", "via": ["t_south", "tunnels_mid", "tunnel_room"], "stage": "b_tunnel_stage", "entry": "b_tunnel_entry"},
			"B.alt": {"site": "B", "via": ["mid_entry", "lower_top", "tunnel_room"], "stage": "b_tunnel_stage", "entry": "b_tunnel_entry"},
			"B.short": {"site": "B", "via": ["mid_entry", "mid_center"], "stage": "b_short_stage", "entry": "b_short_entry"},
			"lurk": {"site": "", "via": ["mid_entry"], "stage": "mid_center", "entry": ""},
			"A.market": {"site": "A", "via": ["mid_entry", "mid_center", "market"], "stage": "market_stage", "entry": "a_market_entry"},
			"B.apts": {"site": "B", "via": ["mid_entry", "mid_center", "apts_hall"], "stage": "apts_stage", "entry": "b_apts_entry"},
			"B.house": {"site": "B", "via": ["mid_entry", "lower_top", "house"], "stage": "b_short_stage", "entry": "b_short_entry"},
			"A.hotel": {"site": "A", "via": ["t_north", "hotel", "cat_mid", "long_cat_top"], "stage": "a_long_stage", "entry": "a_long_entry"},
			"B.garage": {"site": "B", "via": ["garage", "mid_center"], "stage": "b_short_stage", "entry": "b_short_entry"},
			"B.shop": {"site": "B", "via": ["shop", "lower_top", "tunnel_room"], "stage": "b_tunnel_stage", "entry": "b_tunnel_entry"},
			"B.corner": {"site": "B", "via": ["t_south", "corner_house", "tunnel_room"], "stage": "b_tunnel_stage", "entry": "b_tunnel_entry"},
		},
		"site_info": {
			"A": {
				"plant": [Vector2i(74, 10), Vector2i(79, 15), Vector2i(70, 6)],
				"ct_holds": [[Vector2i(82, 9), "a_long_entry"], [Vector2i(75, 17), "a_short_entry"], [Vector2i(83, 18), "a_short_entry"]],
				"t_cover": [[Vector2i(81, 11), "ct_a"], [Vector2i(73, 6), "ct_a"], [Vector2i(69, 16), "a_short_entry"], [Vector2i(76, 17), "ct_a"]],
				"retake": ["ct_a_stage", "mid_a_stage"],
				"flank": ["mid_center", "cat_mid", "long_cat_top", "a_long_stage", "market"],
				"main_route": "A.main", "alt_route": "A.alt", "short_route": "A.short", "building_routes": ["A.market", "A.hotel"],
			},
			"B": {
				"plant": [Vector2i(73, 51), Vector2i(79, 54), Vector2i(67, 47)],
				"ct_holds": [[Vector2i(81, 51), "b_tunnel_entry"], [Vector2i(77, 45), "b_short_entry"], [Vector2i(80, 49), "b_short_entry"]],
				"t_cover": [[Vector2i(82, 48), "ct_b"], [Vector2i(72, 52), "ct_b"], [Vector2i(67, 55), "b_short_entry"], [Vector2i(78, 57), "ct_b"]],
				"retake": ["ct_b_stage", "mid_b_stage"],
				"flank": ["mid_center", "lower_top", "tunnel_room", "b_tunnel_stage", "house", "apts_hall"],
				"main_route": "B.main", "alt_route": "B.alt", "short_route": "B.short", "building_routes": ["B.apts", "B.house", "B.garage", "B.shop", "B.corner"],
			},
		},
	}
