class_name Maps
extends RefCounted
## Map registry. Each map is a script with `static func data() -> Dictionary`.

const LIST := ["Dustline", "Harbor", "Foundry", "Cage"]
const SCRIPTS := {
	"Dustline": preload("res://scripts/maps/map_dustline.gd"),
	"Harbor": preload("res://scripts/maps/map_harbor.gd"),
	"Foundry": preload("res://scripts/maps/map_foundry.gd"),
	"Cage": preload("res://scripts/maps/map_cage.gd"),
}


static func get_map(map_name: String) -> Dictionary:
	if not SCRIPTS.has(map_name):
		map_name = "Dustline"
	return SCRIPTS[map_name].data()


static func random_name(rng: RandomNumberGenerator) -> String:
	return LIST[rng.randi() % LIST.size()]
