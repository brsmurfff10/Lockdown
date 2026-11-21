class_name WeaponData
extends Resource
## Weapon definition. Each Unit owns its own instances, so `ammo` is per-unit.
##
## Two kinds of numbers live here:
##  - categories (`cat`): PISTOL, SMG, SHOTGUN, RIFLE, SNIPER, HEAVY. Behaviour
##    (bot range, bursts, sounds, draw length) keys off the category.
##  - weapon ids (`id`, 100+): one per gun in the arsenal (`ALL`), each with
##    its own stats, price, side restriction and kill reward.

enum { PISTOL, SMG, SHOTGUN, RIFLE, SNIPER, HEAVY }

# --- Weapon ids. Starting at 100 so a category is never mistaken for a gun. ---
const PK9 := 100 ## T starter pistol.
const SENTRY := 101 ## CT starter pistol.
const DUSTER := 102
const VIPER := 103 ## T machine pistol.
const FALCON := 104 ## CT.
const MAGNUM := 105
const HORNET := 110 ## T SMG.
const KESTREL := 111 ## CT SMG.
const BULLDOG := 112
const SWARM := 113
const BREACHER := 120 ## Pump shotgun.
const TEMPEST := 121 ## Semi-auto shotgun.
const HAMMER := 130 ## Machine gun.
const KODIAK := 140 ## Cheap T rifle.
const LANCER := 141 ## Cheap CT rifle.
const RAPTOR := 142 ## Main T rifle.
const GUARDIAN := 143 ## Main CT rifle.
const TALON := 144 ## T scoped rifle.
const OVERWATCH := 145 ## CT scoped rifle.
const PATHFINDER := 150 ## Light bolt-action sniper.
const LONGBOW := 151 ## The big one-shot sniper.

const ANY := -1
const STARTER := [PK9, SENTRY] ## Default pistol per side (T, CT).

## Buy-menu layout: category columns in order, items in number-key order.
const MENU := [
	["Pistols", [PK9, SENTRY, DUSTER, VIPER, FALCON, MAGNUM]],
	["SMGs", [HORNET, KESTREL, BULLDOG, SWARM]],
	["Rifles", [KODIAK, LANCER, RAPTOR, GUARDIAN, TALON, OVERWATCH, PATHFINDER, LONGBOW]],
	["Heavy", [BREACHER, TEMPEST, HAMMER]],
]
const ALL := [PK9, SENTRY, DUSTER, VIPER, FALCON, MAGNUM, HORNET, KESTREL, BULLDOG, SWARM,
	BREACHER, TEMPEST, HAMMER, KODIAK, LANCER, RAPTOR, GUARDIAN, TALON, OVERWATCH, PATHFINDER, LONGBOW]

## Stats per gun. Anything missing keeps the field default below.
const TABLE := {
	PK9: {"name": "PK-9", "cat": PISTOL, "sound": "pk9", "side": 0, "price": 200, "damage": 23.0, "fire_rate": 6.0,
		"mag_size": 20, "reload_time": 2.2, "spread_mult": 1.3, "base_spread": 0.6, "recoil": 1.0,
		"max_bloom": 6.0, "recoil_recovery": 10.0, "moving_inaccuracy": 6.0, "armor_pen": 0.1,
		"range_mod": 0.85, "automatic": false, "ideal_range": 280.0, "tier": 0.0},
	SENTRY: {"name": "Sentry .45", "cat": PISTOL, "sound": "sentry", "side": 1, "price": 200, "damage": 27.0, "fire_rate": 4.5,
		"mag_size": 12, "reload_time": 2.2, "spread_mult": 1.1, "base_spread": 0.3, "recoil": 1.2,
		"max_bloom": 6.0, "recoil_recovery": 10.0, "moving_inaccuracy": 7.0, "armor_pen": 0.2,
		"range_mod": 0.88, "automatic": false, "ideal_range": 320.0, "tier": 0.0},
	DUSTER: {"name": "Duster P7", "cat": PISTOL, "sound": "duster", "price": 300, "damage": 32.0, "fire_rate": 4.0,
		"mag_size": 13, "reload_time": 2.2, "spread_mult": 1.2, "base_spread": 0.5, "recoil": 1.6,
		"max_bloom": 7.0, "recoil_recovery": 10.0, "moving_inaccuracy": 7.5, "armor_pen": 0.5,
		"range_mod": 0.85, "automatic": false, "ideal_range": 300.0, "tier": 0.4},
	VIPER: {"name": "Viper MP", "cat": PISTOL, "sound": "viper", "side": 0, "price": 500, "damage": 30.0, "fire_rate": 6.5,
		"mag_size": 18, "reload_time": 2.5, "spread_mult": 1.4, "base_spread": 0.8, "recoil": 1.5,
		"max_bloom": 8.0, "recoil_recovery": 10.0, "moving_inaccuracy": 9.0, "armor_pen": 0.4,
		"range_mod": 0.83, "automatic": false, "ideal_range": 260.0, "tier": 0.6},
	FALCON: {"name": "Falcon 5.7", "cat": PISTOL, "sound": "falcon", "side": 1, "price": 500, "damage": 30.0, "fire_rate": 5.5,
		"mag_size": 20, "reload_time": 2.2, "spread_mult": 1.15, "base_spread": 0.4, "recoil": 1.3,
		"max_bloom": 7.0, "recoil_recovery": 10.0, "moving_inaccuracy": 6.5, "armor_pen": 0.5,
		"range_mod": 0.86, "automatic": false, "ideal_range": 320.0, "tier": 0.6},
	MAGNUM: {"name": "Magnum .50", "cat": PISTOL, "sound": "magnum", "price": 700, "damage": 58.0, "fire_rate": 2.2,
		"mag_size": 7, "reload_time": 2.2, "spread_mult": 1.0, "base_spread": 0.4, "recoil": 4.0,
		"max_bloom": 9.0, "recoil_recovery": 8.0, "moving_inaccuracy": 12.0, "armor_pen": 0.6,
		"range_mod": 0.82, "automatic": false, "ideal_range": 380.0, "tier": 0.8},
	HORNET: {"name": "Hornet M10", "cat": SMG, "sound": "hornet", "side": 0, "price": 1050, "kill_reward": 600, "damage": 18.0,
		"fire_rate": 13.0, "mag_size": 30, "reload_time": 2.4, "spread_mult": 1.5, "base_spread": 2.0,
		"recoil": 0.65, "max_bloom": 8.0, "recoil_recovery": 12.0, "moving_inaccuracy": 3.0,
		"armor_pen": 0.15, "range_mod": 0.8, "ideal_range": 250.0, "tier": 1.9},
	KESTREL: {"name": "Kestrel K9", "cat": SMG, "sound": "kestrel", "side": 1, "price": 1250, "kill_reward": 600, "damage": 17.0,
		"fire_rate": 14.0, "mag_size": 30, "reload_time": 2.0, "spread_mult": 1.3, "base_spread": 1.4,
		"recoil": 0.55, "max_bloom": 7.0, "recoil_recovery": 12.0, "moving_inaccuracy": 3.0,
		"armor_pen": 0.2, "range_mod": 0.82, "ideal_range": 270.0, "tier": 2.0},
	BULLDOG: {"name": "Bulldog .45", "cat": SMG, "sound": "bulldog", "price": 1200, "kill_reward": 600, "damage": 23.0,
		"fire_rate": 9.5, "mag_size": 25, "reload_time": 2.6, "spread_mult": 1.25, "base_spread": 1.2,
		"recoil": 0.75, "max_bloom": 7.0, "recoil_recovery": 12.0, "moving_inaccuracy": 4.0,
		"armor_pen": 0.3, "range_mod": 0.85, "ideal_range": 300.0, "move_mult": 0.98, "tier": 2.0},
	SWARM: {"name": "Swarm 50", "cat": SMG, "sound": "swarm", "price": 2350, "kill_reward": 300, "damage": 19.0,
		"fire_rate": 14.0, "mag_size": 50, "reload_time": 3.0, "spread_mult": 1.3, "base_spread": 1.6,
		"recoil": 0.5, "max_bloom": 7.0, "recoil_recovery": 12.0, "moving_inaccuracy": 4.0,
		"armor_pen": 0.25, "range_mod": 0.85, "ideal_range": 300.0, "move_mult": 0.97, "tier": 2.6},
	BREACHER: {"name": "Breacher Pump", "cat": SHOTGUN, "sound": "breacher", "price": 1050, "kill_reward": 900, "damage": 14.0,
		"pellets": 8, "fire_rate": 1.1, "automatic": false, "mag_size": 8, "reload_time": 3.0,
		"base_spread": 13.0, "recoil": 3.0, "max_bloom": 6.0, "moving_inaccuracy": 4.0, "armor_pen": 0.0,
		"range_mod": 0.5, "max_range": 550.0, "ideal_range": 150.0, "move_mult": 0.97, "tier": 1.5},
	TEMPEST: {"name": "Tempest Auto-12", "cat": SHOTGUN, "sound": "tempest", "price": 1800, "kill_reward": 900, "damage": 13.0,
		"pellets": 6, "fire_rate": 3.0, "automatic": false, "mag_size": 7, "reload_time": 3.2,
		"base_spread": 14.0, "recoil": 2.5, "max_bloom": 5.0, "moving_inaccuracy": 4.5, "armor_pen": 0.0,
		"range_mod": 0.55, "max_range": 550.0, "ideal_range": 170.0, "move_mult": 0.95, "tier": 1.8},
	HAMMER: {"name": "Hammer LMG", "cat": HEAVY, "sound": "hammer", "price": 1900, "kill_reward": 300, "damage": 26.0,
		"fire_rate": 12.0, "mag_size": 100, "reload_time": 5.5, "spread_mult": 1.6, "base_spread": 2.5,
		"recoil": 0.45, "max_bloom": 9.0, "recoil_recovery": 9.0, "moving_inaccuracy": 14.0,
		"armor_pen": 0.45, "range_mod": 0.95, "ideal_range": 450.0, "move_mult": 0.85, "tier": 2.2},
	KODIAK: {"name": "Kodiak AR", "cat": RIFLE, "sound": "kodiak", "side": 0, "price": 1800, "damage": 29.0, "fire_rate": 9.5,
		"mag_size": 35, "reload_time": 2.8, "spread_mult": 1.15, "base_spread": 0.6, "recoil": 0.85,
		"max_bloom": 11.0, "recoil_recovery": 9.0, "moving_inaccuracy": 17.0, "armor_pen": 0.4,
		"range_mod": 0.96, "ideal_range": 420.0, "move_mult": 0.95, "tier": 3.0},
	LANCER: {"name": "Lancer F2", "cat": RIFLE, "sound": "lancer", "side": 1, "price": 2050, "damage": 28.0, "fire_rate": 10.0,
		"mag_size": 25, "reload_time": 2.9, "spread_mult": 1.1, "base_spread": 0.5, "recoil": 0.85,
		"max_bloom": 10.0, "recoil_recovery": 9.0, "moving_inaccuracy": 16.0, "armor_pen": 0.4,
		"range_mod": 0.96, "ideal_range": 420.0, "move_mult": 0.96, "tier": 3.0},
	RAPTOR: {"name": "Raptor 762", "cat": RIFLE, "sound": "raptor", "side": 0, "price": 2700, "damage": 34.0, "fire_rate": 8.5,
		"mag_size": 30, "reload_time": 2.4, "spread_mult": 1.0, "recoil": 1.0, "max_bloom": 11.0,
		"recoil_recovery": 9.0, "moving_inaccuracy": 19.0, "armor_pen": 0.25, "range_mod": 0.98,
		"ideal_range": 450.0, "move_mult": 0.94, "tier": 4.0},
	GUARDIAN: {"name": "Guardian 556", "cat": RIFLE, "sound": "guardian", "side": 1, "price": 2900, "damage": 32.0, "fire_rate": 9.5,
		"mag_size": 30, "reload_time": 2.3, "spread_mult": 0.95, "recoil": 0.8, "max_bloom": 9.0,
		"recoil_recovery": 10.0, "moving_inaccuracy": 18.0, "armor_pen": 0.3, "range_mod": 0.97,
		"ideal_range": 450.0, "move_mult": 0.95, "tier": 4.0},
	TALON: {"name": "Talon SR", "cat": RIFLE, "sound": "talon", "side": 0, "price": 3000, "damage": 33.0, "fire_rate": 7.5,
		"mag_size": 30, "reload_time": 2.9, "spread_mult": 0.6, "recoil": 0.75, "max_bloom": 8.0,
		"recoil_recovery": 10.0, "moving_inaccuracy": 20.0, "armor_pen": 0.5, "range_mod": 0.98,
		"scope": true, "unscoped_spread": 2.5, "ideal_range": 600.0, "move_mult": 0.9, "tier": 4.2},
	OVERWATCH: {"name": "Overwatch SR", "cat": RIFLE, "sound": "overwatch", "side": 1, "price": 3300, "damage": 31.0, "fire_rate": 8.0,
		"mag_size": 30, "reload_time": 3.0, "spread_mult": 0.6, "recoil": 0.7, "max_bloom": 8.0,
		"recoil_recovery": 10.0, "moving_inaccuracy": 20.0, "armor_pen": 0.5, "range_mod": 0.98,
		"scope": true, "unscoped_spread": 2.5, "ideal_range": 600.0, "move_mult": 0.9, "tier": 4.2},
	PATHFINDER: {"name": "Pathfinder", "cat": SNIPER, "sound": "pathfinder", "price": 1700, "damage": 80.0, "fire_rate": 1.3,
		"automatic": false, "mag_size": 10, "reload_time": 3.0, "spread_mult": 0.2, "recoil": 0.0,
		"max_bloom": 0.0, "moving_inaccuracy": 8.0, "armor_pen": 0.75, "range_mod": 0.99, "scope": true,
		"unscoped_spread": 2.5, "bullet_speed": 2400.0, "max_range": 2200.0, "ideal_range": 600.0,
		"move_mult": 1.0, "tier": 2.8},
	LONGBOW: {"name": "Longbow .338", "cat": SNIPER, "sound": "longbow", "price": 4750, "kill_reward": 100, "damage": 115.0,
		"fire_rate": 0.7, "automatic": false, "mag_size": 5, "reload_time": 3.6, "spread_mult": 0.25,
		"recoil": 0.0, "max_bloom": 0.0, "moving_inaccuracy": 32.0, "armor_pen": 0.85, "range_mod": 0.99,
		"scope": true, "unscoped_spread": 10.0, "bullet_speed": 2400.0, "max_range": 2200.0,
		"ideal_range": 650.0, "move_mult": 0.85, "tier": 3.6},
}

const CAT_NAMES := ["Pistol", "SMG", "Shotgun", "Rifle", "Sniper", "Machine gun"]

@export var id: int = PK9
@export var cat: int = PISTOL
@export var weapon_name: String = ""
@export var side: int = ANY ## -1 both sides, 0 T only, 1 CT only.
@export var price: int = 0
@export var kill_reward: int = 300
@export var damage: float = 25.0
@export var fire_rate: float = 5.0 ## Shots per second.
@export var mag_size: int = 12
@export var reload_time: float = 2.0
@export var spread_mult: float = 1.0 ## Multiplies the shooter's aim-based spread.
@export var base_spread: float = 0.0 ## Degrees added regardless of aim.
@export var moving_inaccuracy: float = 6.0 ## Degrees added at full run speed (run-and-gun penalty).
@export var recoil: float = 1.0 ## Bloom degrees added per shot (before recoil control).
@export var max_bloom: float = 8.0
@export var recoil_recovery: float = 12.0 ## Bloom degrees recovered per second.
@export var pellets: int = 1
@export var automatic: bool = true
@export var bullet_speed: float = 1600.0
@export var max_range: float = 1000.0
@export var ideal_range: float = 400.0 ## Distance bots try to fight at.
@export var move_mult: float = 1.0
@export var armor_pen: float = 0.0 ## Share of the armour's protection this gun ignores.
@export var range_mod: float = 1.0 ## Damage multiplier per 500px travelled.
@export var scope: bool = false ## Has a scope (right mouse / bots standing still).
@export var unscoped_spread: float = 0.0 ## Extra degrees when not scoped in.
@export var tier: float = 0.0 ## How good the gun is, for bots choosing what to pick up.
@export var sound: String = "" ## Firing sound: res://audio/guns/<sound>.wav (Sfx.shot_sound).

var ammo: int = 0


static func by_id(weapon_id: int) -> WeaponData:
	var w := WeaponData.new()
	if not TABLE.has(weapon_id):
		push_error("WeaponData: unknown weapon id %d" % weapon_id)
		weapon_id = PK9
	w.id = weapon_id
	var d: Dictionary = TABLE[weapon_id]
	for k: String in d:
		if k == "name":
			w.weapon_name = d[k]
		else:
			w.set(k, d[k])
	w.move_mult = move_mult_for(w.cat, w.scope)
	w.ammo = w.mag_size
	return w


## Holding a gun slows you down by type: pistol -10%, SMG -15%, rifle -20%,
## sniper -30% (scoped rifles count as snipers). Shotguns move like SMGs,
## the LMG between a rifle and a sniper. The knife is full speed.
static func move_mult_for(category: int, scoped: bool) -> float:
	if scoped or category == SNIPER:
		return 0.7
	match category:
		PISTOL:
			return 0.9
		SMG, SHOTGUN:
			return 0.85
		RIFLE:
			return 0.8
		HEAVY:
			return 0.75
	return 1.0


static func price_of(weapon_id: int) -> int:
	return int(TABLE[weapon_id].get("price", 0))


static func name_of(weapon_id: int) -> String:
	return String(TABLE[weapon_id].get("name", "?"))


static func cat_of(weapon_id: int) -> int:
	return int(TABLE[weapon_id].get("cat", PISTOL))


static func side_of(weapon_id: int) -> int:
	return int(TABLE[weapon_id].get("side", ANY))


static func tier_of(weapon_id: int) -> float:
	return float(TABLE[weapon_id].get("tier", 0.0))


static func reward_of(weapon_id: int) -> int:
	return int(TABLE[weapon_id].get("kill_reward", 300))


static func allowed(weapon_id: int, p_side: int) -> bool:
	var s := side_of(weapon_id)
	return s == ANY or s == p_side


static func starter(p_side: int) -> int:
	return STARTER[clampi(p_side, 0, 1)]


static func is_secondary(weapon_id: int) -> bool:
	return cat_of(weapon_id) == PISTOL


## Side-correct pick: `t_id` for T, `ct_id` for CT.
static func pick(p_side: int, t_id: int, ct_id: int) -> int:
	return t_id if p_side == 0 else ct_id


## Damage after travelling `dist` px (falloff per 500px).
func damage_at(dist: float) -> float:
	if range_mod >= 1.0:
		return damage
	return damage * pow(range_mod, dist / 500.0)


func is_pistol() -> bool:
	return cat == PISTOL


func is_sniper() -> bool:
	return cat == SNIPER


## One line of stats for the buy menu.
func stat_line() -> String:
	var dmg := ("%dx%d" % [int(damage), pellets]) if pellets > 1 else str(int(damage))
	var parts := ["%s" % CAT_NAMES[cat], "DMG %s" % dmg, "RPM %d" % int(round(fire_rate * 60.0)),
		"MAG %d" % mag_size, "ARMOR PEN %d%%" % int(round(armor_pen * 100.0)),
		"SPEED %d%%" % int(round(move_mult * 100.0)), "KILL $%d" % kill_reward]
	if scope:
		parts.append("SCOPE (right mouse)")
	return "   ".join(parts)
