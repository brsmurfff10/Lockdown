class_name BotPersonality
extends RefCounted
## Stable per-player habits. Built from role + stats + a hash of the player's
## name, so the same player plays the same way every match: one rifler is a
## hothead who wide-swings everything, another sits on an off-angle all round.

var aggression := 0.5 ## Takes duels, swings, pushes contacts, plays early aggressive.
var patience := 0.5 ## Holds longer, lurks, waits for the enemy to come, walks quietly.
var discipline := 0.5 ## Sticks to the plan, trades teammates, sound discipline.
var peek_style := "jiggle" ## "wide" (full swing), "jiggle" (info peek), "shoulder" (bait), "hold" (wait)
var composure := 0.5 ## Calm under pressure: resists stress (low HP, clutches, flashes, tilt).
var trash_talk := 0.2 ## Chat: taunts after aces / clutches when high.
var quirks: Array[String] = [] ## One or two personal habits (see HABITS / habits()).

## Personal habits, deterministic per player (uid, else name):
##  early_peek  - takes an early peek at the same area most rounds
##  awp_angle   - has a favourite angle and goes back to it
##  prefire     - prefires spots where they expect someone
##  jiggler     - jiggle-peeks a lot (baits AWPs)
##  hothead     - overpeeks after a kill
##  nade_happy  - throws utility more readily
##  silent      - walks (no footsteps) more than most
##  clutch_calm - gets calmer, not shakier, when last alive
const HABITS := ["early_peek", "awp_angle", "prefire", "jiggler", "hothead", "nade_happy", "silent", "clutch_calm"]

const ROLE_AGGRESSION := {"Entry": 0.78, "Rifler": 0.55, "AWPer": 0.32, "Support": 0.42, "Lurker": 0.38}
const ROLE_PATIENCE := {"Entry": 0.28, "Rifler": 0.5, "AWPer": 0.72, "Support": 0.55, "Lurker": 0.82}


static func for_player(p: PlayerData) -> BotPersonality:
	var b := BotPersonality.new()
	var r := RandomNumberGenerator.new()
	r.seed = hash(p.player_name + "/habits")
	b.aggression = clampf(float(ROLE_AGGRESSION.get(p.role, 0.5)) + r.randf_range(-0.22, 0.22), 0.05, 0.95)
	b.patience = clampf(float(ROLE_PATIENCE.get(p.role, 0.5)) + r.randf_range(-0.2, 0.2) - (b.aggression - 0.5) * 0.35, 0.05, 0.95)
	b.discipline = clampf(lerpf(0.25, 0.85, p._t("decision")) + r.randf_range(-0.15, 0.15), 0.05, 0.95)
	# Peek style: weighted by temperament, but still a personal habit.
	var w := {
		"wide": 0.2 + maxf(0.0, b.aggression - 0.45) * 2.0,
		"jiggle": 0.6,
		"shoulder": 0.15 + b.discipline * 0.7,
		"hold": 0.1 + maxf(0.0, b.patience - 0.5) * 2.0 + (0.8 if p.role == "AWPer" else 0.0),
	}
	b.composure = clampf(0.5 + r.randf_range(-0.3, 0.3) + (p._t("decision") - 0.5) * 0.3 - (b.aggression - 0.5) * 0.25, 0.05, 0.95)
	b.trash_talk = clampf(r.randf() * r.randf() + (b.aggression - 0.5) * 0.4, 0.0, 1.0)
	b.quirks = habits(p)
	var total := 0.0
	for k in w:
		total += w[k]
	var roll := r.randf() * total
	for k in w:
		roll -= w[k]
		if roll <= 0.0:
			b.peek_style = k
			break
	return b


## The player's one or two habits. Deterministic from the player's uid (or
## name when there's no uid), so the same player has the same habits in every
## match without saving anything. Safe to call from UI code.
static func habits(p: PlayerData) -> Array[String]:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d/%s/quirks" % [p.uid, p.player_name if p.uid == 0 else ""])
	var pool: Array = HABITS.duplicate()
	if p.role != "AWPer":
		pool.erase("awp_angle")
	var out: Array[String] = []
	var n := 1 if r.randf() < 0.6 else 2
	for i in n:
		var h: String = pool[r.randi() % pool.size()]
		pool.erase(h)
		out.append(h)
	return out


## Readable habit names for UI.
static func habit_text(h: String) -> String:
	return {"early_peek": "Early peeker", "awp_angle": "Favourite AWP angle", "prefire": "Prefires spots",
		"jiggler": "Jiggle-peeker", "hothead": "Overpeeks after kills", "nade_happy": "Utility-happy",
		"silent": "Silent walker", "clutch_calm": "Ice-cold in clutches"}.get(h, h)


func has(h: String) -> bool:
	return quirks.has(h)


## Two-word summary for the spectate overlay / tooltips, e.g. "aggressive, wide-swinger".
func describe() -> String:
	var temper := "aggressive" if aggression > 0.62 else ("passive" if aggression < 0.38 else "balanced")
	if patience > 0.7:
		temper += ", patient"
	elif patience < 0.3:
		temper += ", impatient"
	var style: String = {"wide": "wide-swinger", "jiggle": "info-peeker", "shoulder": "baiter", "hold": "angle-holder"}[peek_style]
	return "%s %s" % [temper, style]
