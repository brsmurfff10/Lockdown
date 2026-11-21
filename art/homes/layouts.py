"""Home layouts for My Player (walkable top-down homes).

Single source for the homes: writes data/homes/props.json (the furniture
catalog) and data/homes/<id>.json (one per property). Godot reads those at
runtime (scripts/home/), and art/blender/build_home.py renders them:
assets/homes/<id>.png (the shell: floors, walls, windows, doors) and
assets/homes/props/<kind>.png (one sprite per furniture kind).

    python art/homes/layouts.py            # write the JSON, validate, print ASCII previews

Grid legend (1 cell = 1 m = 32 game px; renders are 64 px per cell):
    #  wall                 W  wall with a window      E  front door (in a wall)
    .  wood floor           ,  bathroom/kitchen tile   ~  carpet
    _  concrete             m  marble                  d  wooden deck (outdoor)
    g  grass (outdoor)      s  stone patio (outdoor)   w  pool water (not walkable)
    D  interior doorway (walkable; a door frame is drawn)
    (space) outside the home: nothing is drawn, not walkable

Furniture rotation: at rot 0 a piece's "front" (the side you use it from, the
way a sofa faces, the foot of a bed) points DOWN (+y). rot is clockwise in
degrees: 90 = front points left (-x)... see rot_dims(). Footprints are given at
rot 0 as (w, h); at 90/270 they swap.
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "homes")

# kind: (w, h, solid, description for the artist)
PROPS = {
    # sleeping
    "mattress": (2, 3, True, "bare mattress on the floor with a crumpled duvet and one pillow at the top (rental)"),
    "bed_single": (2, 3, True, "single bed, wooden frame, headboard along the top edge, pillow at top"),
    "bed_double": (3, 3, True, "double bed, upholstered headboard along the top, two pillows, folded throw at the foot"),
    "bed_king": (4, 4, True, "luxury king bed, tall padded headboard along the top, four pillows, silk duvet"),
    "nightstand": (1, 1, True, "small bedside table with a lamp"),
    "wardrobe": (3, 1, True, "wardrobe, back against the top edge, doors facing down"),
    "dresser": (2, 1, True, "chest of drawers with a few items on top"),
    # living
    "sofa": (4, 2, True, "3-seat fabric sofa, backrest along the top, cushions, seats facing down"),
    "sofa_corner": (5, 3, True, "L-shaped corner sofa: long part along the top (5 wide), short leg down the left side, facing down/right"),
    "armchair": (2, 2, True, "armchair facing down"),
    "beanbag": (1, 1, True, "gamer beanbag"),
    "coffee_table": (2, 1, True, "low coffee table with a magazine and a mug"),
    "tv_stand": (4, 1, True, "low TV stand with a flat TV on it; the screen faces down"),
    "tv_big": (6, 1, True, "big wall TV over a long media console; screen faces down; soundbar"),
    "bookshelf": (3, 1, True, "bookshelf full of books, back against the top edge"),
    "lamp": (1, 1, True, "floor lamp (round shade seen from above)"),
    "plant": (1, 1, True, "potted plant (leafy, seen from above)"),
    "plant_big": (1, 1, True, "large potted plant / small indoor tree, bigger crown overhanging the cell"),
    "rug_small": (3, 2, False, "small rug (flat, patterned)"),
    "rug_big": (5, 4, False, "large living-room rug (flat)"),
    "rug_round": (3, 3, False, "round rug (flat)"),
    "piano": (3, 2, True, "black grand piano, keyboard along the bottom edge, bench below"),
    "aquarium": (3, 1, True, "long fish tank on a cabinet (blue water, fish, plants seen from above)"),
    "arcade": (1, 1, True, "retro arcade cabinet, screen/controls facing down"),
    "bar_counter": (4, 1, True, "home bar counter with bottles and stools on the bottom side"),
    "telescope": (1, 1, True, "telescope on a tripod"),
    # gaming / work
    "desk_pc_0": (3, 2, True, "cheap desk: laptop, folding chair in the bottom row (setup level 0)"),
    "desk_pc_1": (3, 2, True, "gaming desk: one monitor, keyboard, mouse pad, gaming chair in the bottom row (level 1)"),
    "desk_pc_2": (3, 2, True, "gaming desk: two monitors, RGB keyboard, mic arm, better chair in the bottom row (level 2)"),
    "desk_pc_3": (3, 2, True, "pro battlestation: three monitors / ultrawide, RGB strips, tower PC, premium chair (level 3)"),
    "studio_rig": (3, 2, True, "streaming studio corner: softbox lights, camera on a tripod, green screen roll along the top, mic"),
    "trophy_cabinet": (3, 1, True, "glass trophy cabinet, back against the top edge, gold cups and plaques on shelves"),
    "home_gym": (4, 3, True, "home gym: treadmill, bench with a barbell rack, dumbbells, rubber mat"),
    # kitchen / dining
    "kitchenette": (3, 1, True, "tiny kitchenette: two-ring hob, small sink, cupboard; back along the top edge"),
    "kitchen_line": (5, 1, True, "kitchen counter run: sink, hob, worktop, along the top edge"),
    "kitchen_island": (3, 2, True, "kitchen island with stools along the bottom"),
    "fridge": (1, 1, True, "fridge (steel)"),
    "dining_table": (4, 3, True, "dining table for six with chairs on all sides"),
    # bathroom
    "toilet": (1, 1, True, "toilet, cistern along the top"),
    "sink": (1, 1, True, "bathroom sink with a mirror edge at the top"),
    "shower": (2, 2, True, "shower tray with a glass screen"),
    "bathtub": (2, 3, True, "bathtub, taps at the top"),
    "washer": (1, 1, True, "washing machine"),
    # outdoor
    "tree": (2, 2, True, "garden tree (round leafy crown)"),
    "hot_tub": (3, 3, True, "hot tub (square, blue water, wooden surround)"),
    "lounger": (1, 2, True, "sun lounger, head end at the top"),
    "bbq": (2, 1, True, "barbecue grill"),
    "patio_set": (3, 3, True, "round patio table with four chairs and a parasol seen from above"),
    "doormat": (2, 1, False, "door mat (flat)"),
    # pets
    "pet_bed": (1, 1, False, "round pet bed with a cushion"),
    "dog": (1, 1, False, "a dog (golden retriever) lying/standing, nose pointing UP (-y), seen from above"),
    "cat": (1, 1, False, "a cat (ginger), nose pointing UP (-y), seen from above"),
    # cars (nose points UP at rot 0)
    "car_hatchback": (3, 5, True, "small hatchback, nose pointing up; dull blue"),
    "car_sports": (3, 5, True, "sports car, nose pointing up; red"),
    "car_suv": (3, 5, True, "electric SUV, nose pointing up; white with a glass roof"),
    "car_super": (3, 5, True, "supercar, nose pointing up; matte black with orange accents"),
}

# Where a piece can be used from (shown as "E  <label>" in the home). Keys are
# the "use" value of an item in a layout.
USES = {
    "bed": "Sleep", "pc": "Use the PC", "tv": "Watch TV", "kitchen": "Cook",
    "trophies": "Trophy cabinet", "gym": "Work out", "car": "Go for a drive",
    "sofa": "Sit down", "wardrobe": "Wardrobe", "pet": "Pet", "view": "Take in the view",
    "tub": "Hot tub", "piano": "Play the piano", "arcade": "Play", "aquarium": "Watch the fish",
    "bar": "Pour a drink",
}


def rot_dims(kind, rot):
    w, h = PROPS[kind][0], PROPS[kind][1]
    return (h, w) if rot in (90, 270) else (w, h)


def it(kind, x, y, rot=0, use="", need=""):
    """A furniture piece at cell (x, y) (top-left of its rotated footprint).
    use: what pressing E does (see USES). need: shop item that must be owned for
    the piece to appear ("studio", "trophy_case", "home_gym", "pet", "car", ...)."""
    d = {"k": kind, "x": x, "y": y, "rot": rot}
    if use:
        d["use"] = use
    if need:
        d["need"] = need
    return d


# --- Layouts -------------------------------------------------------------------
# Each: grid rows (all the same width), items, spawn cell (inside, by the front door).

HOMES = {}

HOMES["rented_room"] = {
    "name": "Rented room", "style": "rental", "walls": "plaster_worn",
    "grid": [
        "############",
        "#......#,,,#",
        "#......#,,,#",
        "#......#,,,W",
        "#......##D##",
        "W..........#",
        "#..........#",
        "#..........#",
        "######E#####",
    ],
    "spawn": [6, 7],
    "items": [
        it("mattress", 1, 1, use="bed"),
        it("lamp", 3, 1),
        it("desk_pc_0", 4, 1, use="pc"),
        it("trophy_cabinet", 4, 3, 0, use="trophies", need="trophy_case"),
        it("wardrobe", 1, 5, 270, use="wardrobe"),
        it("beanbag", 3, 5, use="sofa"),
        it("rug_small", 2, 5),
        it("tv_stand", 2, 7, 180, use="tv"),
        it("pet_bed", 9, 5, need="pet"),
        it("kitchenette", 8, 7, 180, use="kitchen"),
        it("fridge", 10, 6),
        it("shower", 8, 1),
        it("toilet", 10, 1),
        it("sink", 10, 2, 90),
        it("plant", 1, 4),
    ],
}

HOMES["apartment"] = {
    "name": "City apartment", "style": "modern", "walls": "plaster_white",
    "grid": [
        "####WWW####WWW##",
        "#........#~~~~~#",
        "#........#~~~~~#",
        "W........D~~~~~W",
        "#........#~~~~~#",
        "#........#~~~~~#",
        "#.........######",
        "W..........#,,,#",
        "#,,,,,.....D,,,#",
        "#,,,,,.....#,,,#",
        "#,,,,,.....#,,,W",
        "######E#########",
    ],
    "spawn": [6, 10],
    "items": [
        it("bed_double", 11, 1, use="bed"),
        it("nightstand", 10, 1), it("nightstand", 14, 1),
        it("wardrobe", 14, 2, 90, use="wardrobe"),
        it("rug_small", 11, 4),
        it("desk_pc_1", 1, 1, use="pc"),
        it("studio_rig", 4, 1, need="studio"),
        it("plant", 7, 1),
        it("tv_stand", 1, 3, 270, use="tv"),
        it("rug_small", 2, 4, 90),
        it("coffee_table", 3, 4, 90),
        it("sofa", 5, 4, 90, use="sofa"),
        it("trophy_cabinet", 8, 4, 90, use="trophies", need="trophy_case"),
        it("kitchen_island", 2, 7),
        it("fridge", 5, 8),
        it("kitchen_line", 1, 10, 180, use="kitchen"),
        it("pet_bed", 9, 7, need="pet"),
        it("plant_big", 10, 7),
        it("shower", 13, 7),
        it("sink", 14, 9, 90),
        it("toilet", 14, 10, 90),
        it("washer", 12, 10),
    ],
}

HOMES["loft"] = {
    "name": "Industrial loft", "style": "loft", "walls": "brick",
    "grid": [
        "##WWWW####WWWW####",
        "#_________.......#",
        "#_________.......#",
        "W_________.......W",
        "#_________.......#",
        "#_________.......#",
        "#____________#####",
        "#____________D,,,#",
        "#____________#,,,#",
        "W____________#,,,#",
        "#____________#,,,#",
        "########E#########",
    ],
    "spawn": [8, 10],
    "items": [
        it("bed_double", 12, 1, use="bed"),
        it("nightstand", 11, 1), it("nightstand", 15, 1),
        it("wardrobe", 16, 3, 90, use="wardrobe"),
        it("rug_round", 11, 3),
        it("desk_pc_1", 1, 1, use="pc"),
        it("studio_rig", 4, 1, need="studio"),
        it("arcade", 7, 1, use="arcade", need="arcade"),
        it("trophy_cabinet", 8, 1, use="trophies", need="trophy_case"),
        it("kitchen_line", 1, 5, 270, use="kitchen"),
        it("fridge", 1, 10),
        it("rug_big", 3, 5),
        it("sofa_corner", 3, 5, use="sofa"),
        it("coffee_table", 4, 8),
        it("tv_stand", 3, 10, 180, use="tv"),
        it("dining_table", 8, 7),
        it("plant_big", 12, 10),
        it("pet_bed", 8, 4, need="pet"),
        it("lamp", 10, 5),
        it("shower", 15, 7),
        it("toilet", 16, 10, 90),
        it("sink", 14, 10, 180),
        it("washer", 16, 9),
    ],
}

HOMES["seaside_flat"] = {
    "name": "Seaside flat", "style": "coastal", "walls": "plaster_blue",
    "grid": [
        "#####WWWW#######",
        "#~~~~~#........#",
        "#~~~~~#........#",
        "W~~~~~D........W",
        "#~~~~~#........#",
        "#~~~~~#........#",
        "###D###........E",
        "#,,,,,#...,,,,,#",
        "#,,,,,#...,,,,,#",
        "#######WDDWWWWW#",
        "      #dddddddd#",
        "      #dddddddd#",
        "      ##########",
    ],
    "spawn": [14, 6],
    "items": [
        it("bed_double", 2, 1, use="bed"),
        it("nightstand", 1, 1), it("nightstand", 5, 1),
        it("wardrobe", 1, 2, 270, use="wardrobe"),
        it("plant", 5, 5),
        it("shower", 1, 7),
        it("sink", 3, 8, 180),
        it("toilet", 5, 7, 90),
        it("desk_pc_1", 8, 1, use="pc"),
        it("studio_rig", 12, 1, need="studio"),
        it("plant", 7, 1),
        it("trophy_cabinet", 14, 3, 90, use="trophies", need="trophy_case"),
        it("tv_stand", 7, 4, 270, use="tv"),
        it("rug_small", 8, 4, 90),
        it("coffee_table", 9, 5, 90),
        it("sofa", 10, 4, 90, use="sofa"),
        it("kitchen_line", 10, 8, 180, use="kitchen"),
        it("fridge", 14, 7),
        it("pet_bed", 8, 7, need="pet"),
        it("plant_big", 7, 10),
        it("lounger", 11, 10, 90),
        it("telescope", 14, 10, use="view"),
    ],
}

HOMES["townhouse"] = {
    "name": "City townhouse", "style": "classic", "walls": "plaster_warm",
    "grid": [
        "####WWW#######",
        "#~~~~~~~#,,,,#",
        "#~~~~~~~#,,,,#",
        "W~~~~~~~#,,,,W",
        "#~~~~~~~##D###",
        "#~~~~~~~D....#",
        "#########....#",
        "W............W",
        "#............#",
        "E............#",
        "#............#",
        "W............W",
        "#............#",
        "#####D######D#",
        "#,,,,,,,,,,,,#",
        "#,,,,,,,,,,,,#",
        "W,,,,,,,,,,,,W",
        "#,,,,,,,,,,,,#",
        "######DD######",
        "#sssssggggggg#",
        "#sssssggggggg#",
        "#sssssggggggg#",
        "##############",
    ],
    "spawn": [1, 9],
    "items": [
        it("bed_double", 3, 1, use="bed"),
        it("nightstand", 2, 1), it("nightstand", 6, 1),
        it("wardrobe", 1, 3, 270, use="wardrobe"),
        it("dresser", 7, 3, 90),
        it("bathtub", 9, 1, 90),
        it("toilet", 9, 3, 270),
        it("sink", 12, 1, 90),
        it("plant", 12, 5),
        it("plant", 1, 7),
        it("tv_big", 3, 7, use="tv"),
        it("rug_big", 3, 8),
        it("coffee_table", 5, 9),
        it("sofa", 4, 10, 180, use="sofa"),
        it("studio_rig", 11, 7, 90, need="studio"),
        it("desk_pc_2", 10, 10, use="pc"),
        it("trophy_cabinet", 1, 10, 270, use="trophies", need="trophy_case"),
        it("kitchen_island", 2, 14),
        it("kitchen_line", 1, 17, 180, use="kitchen"),
        it("fridge", 1, 14),
        it("dining_table", 8, 14),
        it("pet_bed", 12, 17, need="pet"),
        it("patio_set", 1, 19),
        it("lounger", 9, 19),
        it("tree", 11, 19),
        it("plant", 5, 21),
    ],
}

HOMES["house"] = {
    "name": "Family house", "style": "suburban", "walls": "plaster_warm",
    "grid": [
        "########WWW###WWWW######",
        "#_____#.....#~~~~~~#,,,#",
        "#_____#.....#~~~~~~#,,,#",
        "#_____#.....#~~~~~~D,,,W",
        "#_____#.....#~~~~~~#,,,#",
        "#_____#.....#~~~~~~#####",
        "#_____###D#####D########",
        "#_____D................#",
        "#_____#................E",
        "######.................#",
        "#,,,,,,................#",
        "W,,,,,,................#",
        "#,,,,,,................W",
        "#,,,,,,................#",
        "##########DDD###########",
        "#sssssssssdddgggggggggg#",
        "#ssssssssgggggggggggggg#",
        "#wwwwwwssgggggggggggggg#",
        "#wwwwwwssgggggggggggggg#",
        "########################",
    ],
    "spawn": [22, 8],
    "items": [
        dict(it("car_sports", 2, 1, use="car", need="car"), slot=0),
        it("washer", 1, 7),
        it("desk_pc_2", 7, 1, use="pc"),
        it("studio_rig", 10, 1, 90, need="studio"),
        it("bookshelf", 7, 3, 270),
        it("plant", 11, 5),
        it("bed_king", 14, 1, use="bed"),
        it("nightstand", 13, 1), it("nightstand", 18, 1),
        it("wardrobe", 13, 2, 270, use="wardrobe"),
        it("bathtub", 21, 1),
        it("toilet", 20, 1),
        it("sink", 22, 4, 180),
        it("trophy_cabinet", 17, 7, use="trophies", need="trophy_case"),
        it("piano", 12, 7, use="piano", need="piano"),
        it("aquarium", 20, 7, use="aquarium", need="aquarium"),
        it("rug_big", 14, 9),
        it("sofa", 15, 10, use="sofa"),
        it("armchair", 19, 10),
        it("coffee_table", 16, 12),
        it("tv_big", 14, 13, 180, use="tv"),
        it("kitchen_island", 2, 10),
        it("fridge", 1, 10),
        it("kitchen_line", 1, 13, 180, use="kitchen"),
        it("dining_table", 7, 10),
        it("pet_bed", 21, 12, need="pet"),
        it("arcade", 22, 10, use="arcade", need="arcade"),
        it("bbq", 2, 15),
        it("lounger", 7, 17), it("lounger", 8, 17),
        it("hot_tub", 13, 16, use="tub", need="hot_tub"),
        it("home_gym", 17, 16, use="gym", need="home_gym"),
        it("plant_big", 22, 15),
    ],
}

HOMES["villa"] = {
    "name": "Modern villa", "style": "villa", "walls": "stone_white",
    "grid": [
        "##########WWWWW#WWWWWWWW#WWW##",
        "#________#.....#~~~~~~~~#mmmm#",
        "#________#.....#~~~~~~~~#mmmm#",
        "#________#.....#~~~~~~~~Dmmmm#",
        "#________#.....#~~~~~~~~#mmmm#",
        "#________#.....#~~~~~~~~#mmmm#",
        "#________#.....#~~~~~~~~######",
        "####D######D######D###########",
        "#" + "m" * 28 + "#",
        "#" + "m" * 28 + "E",
        "#" + "," * 7 + "m" * 21 + "#",
        "W" + "," * 7 + "m" * 21 + "#",
        "#" + "," * 7 + "m" * 21 + "W",
        "#" + "," * 7 + "m" * 21 + "#",
        "#" + "," * 7 + "m" * 21 + "#",
        "##########DDDD################",
        "#" + "s" * 8 + "d" * 6 + "g" * 14 + "#",
        "#" + "s" * 2 + "w" * 10 + "d" * 2 + "g" * 14 + "#",
        "#" + "s" * 2 + "w" * 10 + "d" * 2 + "g" * 14 + "#",
        "#" + "s" * 2 + "w" * 10 + "d" * 2 + "g" * 14 + "#",
        "#" + "s" * 12 + "d" * 2 + "g" * 14 + "#",
        "#" * 30,
    ],
    "spawn": [28, 9],
    "items": [
        dict(it("car_sports", 2, 1, use="car", need="car"), slot=0),
        dict(it("car_suv", 6, 1, use="car", need="car"), slot=1),
        it("desk_pc_3", 10, 1, use="pc"),
        it("studio_rig", 13, 1, 90, need="studio"),
        it("arcade", 10, 6, use="arcade", need="arcade"),
        it("beanbag", 14, 6),
        it("bed_king", 18, 1, use="bed"),
        it("nightstand", 17, 1), it("nightstand", 22, 1),
        it("wardrobe", 16, 4, 270, use="wardrobe"),
        it("dresser", 23, 5, 90),
        it("shower", 25, 1),
        it("bathtub", 27, 1),
        it("sink", 25, 5, 180), it("sink", 26, 5, 180),
        it("toilet", 28, 5, 90),
        it("kitchen_line", 1, 10, 270, use="kitchen"),
        it("kitchen_island", 3, 11, 90),
        it("fridge", 6, 10),
        it("dining_table", 9, 11),
        it("trophy_cabinet", 13, 8, use="trophies", need="trophy_case"),
        it("piano", 21, 8, use="piano", need="piano"),
        it("aquarium", 25, 8, use="aquarium", need="aquarium"),
        it("plant_big", 8, 8),
        it("rug_big", 18, 10),
        it("armchair", 17, 11),
        it("sofa", 19, 11, use="sofa"),
        it("coffee_table", 20, 13),
        it("tv_big", 18, 14, 180, use="tv"),
        it("bar_counter", 28, 10, 90, use="bar"),
        it("pet_bed", 14, 13, need="pet"),
        it("lounger", 1, 17), it("lounger", 2, 17),
        it("hot_tub", 15, 17, use="tub", need="hot_tub"),
        it("home_gym", 20, 16, use="gym", need="home_gym"),
        it("tree", 26, 16), it("tree", 26, 19),
        it("bbq", 1, 16),
    ],
}

HOMES["penthouse"] = {
    "name": "Skyline penthouse", "style": "penthouse", "walls": "marble_dark",
    "grid": [
        "#WWWWWWW#" + "W" * 18 + "#",
        "W~~~~~~~#" + "m" * 18 + "W",
        "W~~~~~~~#" + "m" * 18 + "W",
        "W~~~~~~~D" + "m" * 18 + "W",
        "W~~~~~~~#" + "m" * 18 + "W",
        "W~~~~~~~#" + "m" * 18 + "E",
        "W~~~~~~~#" + "m" * 18 + "W",
        "#~~~~~~~#" + "m" * 18 + "W",
        "####D####" + "m" * 18 + "#",
        "#mmmmmmm#" + "m" * 18 + "#",
        "#mmmmmmm#" + "m" * 18 + "#",
        "#mmmmmmm#" + "m" * 18 + "#",
        "#########WWWWWWWWWDDDDWWWWW#",
        "#" + "d" * 26 + "#",
        "#" + "d" * 26 + "#",
        "#" + "d" * 26 + "#",
        "#" + "d" * 26 + "#",
        "#" * 28,
    ],
    "spawn": [26, 5],
    "items": [
        it("bed_king", 2, 1, use="bed"),
        it("nightstand", 1, 1), it("nightstand", 6, 1),
        it("wardrobe", 5, 7, 180, use="wardrobe"),
        it("armchair", 1, 6),
        it("bathtub", 1, 9, 90),
        it("shower", 6, 9),
        it("sink", 6, 11, 180),
        it("toilet", 7, 11, 90),
        it("desk_pc_3", 9, 1, use="pc"),
        it("studio_rig", 12, 1, need="studio"),
        it("trophy_cabinet", 15, 1, use="trophies", need="trophy_case"),
        it("arcade", 18, 1, use="arcade", need="arcade"),
        it("kitchen_line", 20, 1, use="kitchen"),
        it("fridge", 25, 1),
        it("plant_big", 26, 1),
        it("kitchen_island", 21, 3),
        it("dining_table", 21, 7),
        it("aquarium", 9, 4, 270, use="aquarium", need="aquarium"),
        it("rug_big", 11, 6),
        it("sofa_corner", 11, 6, use="sofa"),
        it("coffee_table", 13, 9),
        it("tv_big", 10, 11, 180, use="tv"),
        it("piano", 16, 4, use="piano", need="piano"),
        it("bar_counter", 17, 8, use="bar"),
        it("pet_bed", 25, 10, need="pet"),
        it("plant_big", 26, 11),
        it("hot_tub", 2, 13, use="tub", need="hot_tub"),
        it("lounger", 7, 13), it("lounger", 9, 13), it("lounger", 11, 13),
        it("patio_set", 14, 13),
        it("home_gym", 20, 14, use="gym", need="home_gym"),
        it("telescope", 25, 13, use="view"),
        it("plant", 26, 16),
    ],
}

HOMES["sky_duplex"] = {
    "name": "Sky duplex", "style": "penthouse", "walls": "marble_dark",
    "grid": [
        "#" + "W" * 9 + "#" + "W" * 9 + "#" + "W" * 10 + "#",
        "#" + "_" * 9 + "#" + "." * 9 + "#" + "~" * 6 + "#" + "m" * 3 + "#",
        "#" + "_" * 9 + "#" + "." * 9 + "#" + "~" * 6 + "#" + "m" * 3 + "#",
        "#" + "_" * 9 + "#" + "." * 9 + "#" + "~" * 6 + "D" + "m" * 3 + "W",
        "#" + "_" * 9 + "#" + "." * 9 + "#" + "~" * 6 + "#" + "m" * 3 + "#",
        "#" + "_" * 9 + "#" + "." * 9 + "#" + "~" * 6 + "#" + "m" * 3 + "#",
        "#" + "_" * 9 + "#" + "." * 9 + "#" + "~" * 6 + "#" * 5,
        "#" + "_" * 9 + "#" + "." * 9 + "#" + "~" * 6 + "#" * 5,
        "#" * 5 + "D" + "#" * 9 + "D" + "#" * 7 + "D" + "#" * 8,
        "#" + "m" * 30 + "#",
        "#" + "m" * 30 + "E",
        "W" + "m" * 30 + "#",
        "#" + "m" * 30 + "W",
        "#" + "m" * 30 + "#",
        "#" + "m" * 30 + "#",
        "#" * 14 + "DDDD" + "#" * 14,
        "#" + "d" * 30 + "#",
        "#" + "d" * 8 + "w" * 12 + "d" * 10 + "#",
        "#" + "d" * 8 + "w" * 12 + "d" * 10 + "#",
        "#" + "d" * 8 + "w" * 12 + "d" * 10 + "#",
        "#" + "d" * 30 + "#",
        "#" * 32,
    ],
    "spawn": [30, 10],
    "items": [
        dict(it("car_super", 2, 1, use="car", need="car"), slot=0),
        dict(it("car_sports", 6, 1, use="car", need="car"), slot=1),
        it("desk_pc_3", 11, 1, use="pc"),
        it("studio_rig", 15, 1, need="studio"),
        it("arcade", 19, 1, use="arcade", need="arcade"),
        it("beanbag", 12, 5),
        it("home_gym", 16, 5, use="gym", need="home_gym"),
        it("bed_king", 22, 1, use="bed"),
        it("nightstand", 21, 1), it("nightstand", 26, 1),
        it("wardrobe", 24, 7, 180, use="wardrobe"),
        it("armchair", 21, 6),
        it("toilet", 28, 1),
        it("bathtub", 29, 1),
        it("sink", 28, 5, 180),
        it("trophy_cabinet", 8, 9, use="trophies", need="trophy_case"),
        it("kitchen_line", 1, 9, 270, use="kitchen"),
        it("kitchen_island", 3, 10, 90),
        it("fridge", 1, 14),
        it("dining_table", 7, 11),
        it("piano", 12, 9, use="piano", need="piano"),
        it("plant_big", 11, 14),
        it("rug_big", 18, 10),
        it("sofa_corner", 18, 10, use="sofa"),
        it("coffee_table", 20, 13),
        it("tv_big", 18, 14, 180, use="tv"),
        it("aquarium", 25, 9, use="aquarium", need="aquarium"),
        it("plant_big", 29, 9),
        it("bar_counter", 30, 11, 90, use="bar"),
        it("pet_bed", 28, 14, need="pet"),
        it("lounger", 2, 17), it("lounger", 4, 17), it("lounger", 6, 17),
        it("hot_tub", 26, 16, use="tub", need="hot_tub"),
        it("patio_set", 22, 18),
        it("telescope", 30, 20, use="view"),
        it("plant", 1, 20),
        it("bbq", 9, 20),
    ],
}


def check(hid, h):
    grid = h["grid"]
    H = len(grid)
    W = len(grid[0])
    errs = []
    for y, row in enumerate(grid):
        if len(row) != W:
            errs.append("row %d is %d wide, expected %d" % (y, len(row), W))
    walk = lambda x, y: 0 <= x < W and 0 <= y < H and grid[y][x] in ".,~_mdgsD"
    occ = {}
    for i, d in enumerate(h["items"]):
        k = d["k"]
        if k not in PROPS:
            errs.append("unknown kind %s" % k)
            continue
        w, hh = rot_dims(k, d["rot"])
        for yy in range(d["y"], d["y"] + hh):
            for xx in range(d["x"], d["x"] + w):
                if not walk(xx, yy):
                    errs.append("%s #%d at (%d,%d) covers non-floor (%d,%d)" % (k, i, d["x"], d["y"], xx, yy))
                elif grid[yy][xx] == "D":
                    errs.append("%s #%d blocks a doorway (%d,%d)" % (k, i, xx, yy))
                if PROPS[k][2]:
                    if (xx, yy) in occ:
                        errs.append("%s #%d overlaps %s at (%d,%d)" % (k, i, occ[(xx, yy)], xx, yy))
                    occ[(xx, yy)] = k
        if d.get("use") and d["use"] not in USES:
            errs.append("unknown use %s" % d["use"])
    # Reachability from the spawn (ignoring pieces that need a purchase, then with them all).
    for with_all in (False, True):
        block = set()
        for d in h["items"]:
            if PROPS[d["k"]][2] and (with_all or not d.get("need")):
                w, hh = rot_dims(d["k"], d["rot"])
                for yy in range(d["y"], d["y"] + hh):
                    for xx in range(d["x"], d["x"] + w):
                        block.add((xx, yy))
        sx, sy = h["spawn"]
        if (sx, sy) in block or not walk(sx, sy):
            errs.append("spawn blocked")
            break
        seen = {(sx, sy)}
        todo = [(sx, sy)]
        while todo:
            x, y = todo.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy)
                if n not in seen and walk(*n) and grid[n[1]][n[0]] != "w" and n not in block:
                    seen.add(n)
                    todo.append(n)
        for i, d in enumerate(h["items"]):
            if not d.get("use") or (d.get("need") and not with_all):
                continue
            w, hh = rot_dims(d["k"], d["rot"])
            ok = False
            for yy in range(d["y"] - 1, d["y"] + hh + 1):
                for xx in range(d["x"] - 1, d["x"] + w + 1):
                    if (xx, yy) in seen:
                        ok = True
            if not ok:
                errs.append("%s #%d (use %s) can't be reached%s" % (d["k"], i, d["use"], " with everything bought" if with_all else ""))
        floor_cells = [(x, y) for y in range(H) for x in range(W) if walk(x, y) and grid[y][x] != "w" and (x, y) not in block]
        lost = [c for c in floor_cells if c not in seen]
        h.setdefault("_lost", lost if not with_all else h.get("_lost", []))
        if lost:
            errs.append("unreachable floor%s: %s" % (" (all bought)" if with_all else "", lost[:8]))
    if "E" not in "".join(grid):
        errs.append("no front door E")
    return errs


def preview(h):
    grid = [list(r) for r in h["grid"]]
    for i, d in enumerate(h["items"]):
        w, hh = rot_dims(d["k"], d["rot"])
        ch = chr(ord("a") + i % 26) if PROPS[d["k"]][2] else None
        for yy in range(d["y"], d["y"] + hh):
            for xx in range(d["x"], d["x"] + w):
                if ch and 0 <= yy < len(grid) and 0 <= xx < len(grid[0]):
                    grid[yy][xx] = ch
    sx, sy = h["spawn"]
    grid[sy][sx] = "@"
    for (x, y) in h.get("_lost", []):
        grid[y][x] = "!"
    lines = ["".join(r) for r in grid]
    legend = ["%s=%s%s" % (chr(ord("a") + i % 26), d["k"], "(" + d["use"] + ")" if d.get("use") else "") for i, d in enumerate(h["items"]) if PROPS[d["k"]][2]]
    return "\n".join(lines) + "\n" + "  ".join(legend)


def main():
    os.makedirs(OUT, exist_ok=True)
    props = {k: {"w": v[0], "h": v[1], "solid": v[2], "desc": v[3]} for k, v in PROPS.items()}
    json.dump({"px_per_cell": 64, "props": props, "uses": USES}, open(os.path.join(OUT, "props.json"), "w"), indent=1)
    only = sys.argv[1:]
    bad = 0
    for hid, h in HOMES.items():
        if only and hid not in only:
            continue
        errs = check(hid, h)
        print("== %s (%dx%d)" % (hid, len(h["grid"][0]), len(h["grid"])))
        print(preview(h))
        for e in errs:
            print("  !! " + e)
        bad += len(errs)
        d = dict(h)
        d.pop("_lost", None)
        d["id"] = hid
        d["size"] = [len(h["grid"][0]), len(h["grid"])]
        json.dump(d, open(os.path.join(OUT, hid + ".json"), "w"), indent=1)
    print("errors:", bad)
    return bad


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
