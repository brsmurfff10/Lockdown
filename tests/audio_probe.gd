extends Node


func _ready() -> void:
	var sfx := Sfx.new()
	add_child(sfx)
	for speed in [1.0, 2.0, 4.0, 8.0]:
		Engine.time_scale = speed
		sfx.played_log.clear()
		sfx._recent.clear()
		for i in 20:
			sfx.play("rifle_shot", Vector2.ZERO)
			sfx.play("lockdown_footstep", Vector2.ZERO)
		var shots := sfx.played_log.count("rifle_shot")
		var steps := sfx.played_log.count("lockdown_footstep")
		print("[audio] speed %dx: 20 shots -> %d played, 20 footsteps -> %d played, volume offset %.1f dB" % [speed, shots, steps, -5.0 * log(speed) / log(2.0)])
	Engine.time_scale = 1.0
	get_tree().quit()
