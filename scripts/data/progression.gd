class_name Progression
extends RefCounted
## Player development: growth from match performance, training, and aging.
## Growth slows as a player's rating approaches their hidden potential.

const MATCH_GAIN := 0.35


static func age_factor(age: int) -> float:
	if age <= 19:
		return 1.0
	if age <= 21:
		return 0.85
	if age <= 24:
		return 0.6
	if age <= 27:
		return 0.35
	if age <= 29:
		return 0.1
	if age <= 31:
		return -0.3
	return -0.7


static func _room(p: PlayerData) -> float:
	return clampf((p.potential - p.rating_exact()) / 8.0, 0.0, 1.0)


## HLTV-style match rating: ~1.0 is average.
static func match_rating(kills: int, deaths: int, rounds: int, objectives: int = 0, damage: float = 0.0) -> float:
	if rounds <= 0:
		return 1.0
	var kill_r := (float(kills) / rounds) / 0.68
	var surv_r := (float(rounds - deaths) / rounds) / 0.32
	var adr_r := (damage / rounds) / 75.0 if damage > 0.0 else kill_r
	var r := (kill_r + 0.7 * surv_r + 0.6 * adr_r) / 2.3 + objectives * 0.03
	return clampf(r, 0.0, 3.0)


## Applies post-match development, driven by how well you actually played.
## A great game (rating ~1.5) grows you, an average one (~1.0) grows young
## players a little, a bad one (< ~0.75) can cost you. Veterans slide unless
## they keep performing. Returns {stat_key: delta}.
static func apply_match(p: PlayerData, rating: float, kpr: float, objectives: int, rng: RandomNumberGenerator) -> Dictionary:
	var changes := {}
	var age_f := age_factor(p.age)
	var room := _room(p)
	# -1 (awful) .. 0 (average) .. +1 (great)
	var perf := clampf((rating - 1.0) / 0.5, -1.0, 1.0)
	for k: String in PlayerData.STAT_KEYS:
		var weight := 1.0
		if k in ["aim", "flick", "preaim", "recoil", "reaction"]:
			weight += clampf((kpr - 0.6) * 0.8, -0.3, 0.5)
		elif k in ["decision", "utility", "positioning"]:
			weight += minf(objectives * 0.15, 0.5)
		# Youth adds a baseline; performance pushes it up or down.
		var base := maxf(age_f, 0.0) * room * 0.5 + minf(age_f, 0.0) * 0.4
		var swing := perf * (0.6 if perf > 0.0 else 0.45)
		var delta := MATCH_GAIN * (base + swing * maxf(room, 0.3)) * weight * rng.randf_range(0.4, 1.2)
		var before := p.stat(k)
		p.set_stat(k, before + delta)
		changes[k] = p.stat(k) - before
	return changes


## One My Player training session on one stat. Not guaranteed: usually a
## gain, but a bad session (sloppy habits, overthinking) can set you back.
## Younger players with room to grow get better odds. Returns the delta.
static func train(p: PlayerData, key: String, rng: RandomNumberGenerator, mult: float = 1.0, sd: float = 0.55) -> float:
	var age_f := maxf(0.25, age_factor(p.age) + 0.3)
	var room := maxf(0.15, _room(p))
	var mean := 0.55 * age_f * room * mult
	var before := p.stat(key)
	p.set_stat(key, before + rng.randfn(mean, sd))
	return p.stat(key) - before


## End-of-season aging.
static func age_up(p: PlayerData) -> void:
	p.age += 1
