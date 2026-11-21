class_name NameGen
extends RefCounted
## Unique gamer handles. Mixes word handles, syllable handles and small
## variations so a world with hundreds of players never runs out of names.

const WORDS := [
	"Viper", "Nox", "Quill", "Brick", "Halo", "Rook", "Jinx", "Talon", "Mako", "Cinder",
	"Vex", "Bolt", "Kestrel", "Drift", "Onyx", "Pike", "Rune", "Sable", "Tusk", "Wraith",
	"Echo", "Flint", "Gage", "Hex", "Ion", "Jolt", "Knox", "Lynx", "Moss", "Nero",
	"Orbit", "Pyre", "Quake", "Rift", "Shade", "Torque", "Umbra", "Volt", "Wisp", "Zed",
	"Ash", "Blitz", "Crux", "Dusk", "Ember", "Frost", "Grit", "Husk", "Ivy", "Jett",
	"Kilo", "Lumen", "Mirage", "Nimbus", "Oxide", "Prism", "Razor", "Spectre", "Tempo", "Vandal",
	"Apex", "Bane", "Cobalt", "Dagger", "Fable", "Gunner", "Havoc", "Inferno", "Jackal", "Karma",
	"Lancer", "Mantis", "Nomad", "Omen", "Phantom", "Quasar", "Reaper", "Siren", "Tracer", "Vortex",
	"Warden", "Xeno", "Yeti", "Zenith", "Arrow", "Badger", "Cipher", "Dynamo", "Falcon", "Glitch",
	"Hornet", "Icarus", "Jaguar", "Kraken", "Legend", "Monarch", "Neon", "Outlaw", "Pixel", "Raptor",
	"Sniper", "Titan", "Unit", "Vector", "Wolf", "Zero", "Atlas", "Bishop", "Comet", "Delta",
	"Enigma", "Fury", "Golem", "Hydra", "Jester", "Krypt", "Lotus", "Matrix", "Nova", "Oracle",
]
const PRE := ["Ar", "Bl", "Cr", "Dr", "Fl", "Gr", "Kr", "Pr", "Sh", "St", "Tr", "Vr", "Z", "X", "Qu",
	"Ny", "Ky", "Ry", "My", "Ja", "Le", "Ro", "Sa", "Ti", "Ve", "Ze", "Ka", "Mo", "No", "Pi", "Sk", "Br"]
const MID := ["a", "e", "i", "o", "u", "y", "ae", "io", "ou", "ai"]
const SUF := ["x", "n", "nk", "rr", "th", "ze", "zo", "k", "l", "ro", "ra", "ix", "on", "us", "ek",
	"ax", "yn", "el", "or", "ik", "vo", "sh", "ty", "do"]


static func handle(rng: RandomNumberGenerator, used: Dictionary) -> String:
	for attempt in 40:
		var n := _candidate(rng, attempt)
		if not used.has(n):
			used[n] = true
			return n
	var fallback := "%s%d" % [WORDS[rng.randi() % WORDS.size()], rng.randi_range(100, 999)]
	used[fallback] = true
	return fallback


static func _candidate(rng: RandomNumberGenerator, attempt: int) -> String:
	var roll := rng.randf()
	if roll < 0.45 and attempt < 10:
		return WORDS[rng.randi() % WORDS.size()]
	if roll < 0.85:
		var s: String = PRE[rng.randi() % PRE.size()] + MID[rng.randi() % MID.size()] + SUF[rng.randi() % SUF.size()]
		return s.capitalize()
	# Word variants: "xViperx", "Viper7", "Vipr".
	var w: String = WORDS[rng.randi() % WORDS.size()]
	match rng.randi() % 3:
		0:
			return "%s%d" % [w, rng.randi_range(1, 99)]
		1:
			return w.to_lower() + "z"
	return "x" + w
