extends Node
## A real back-and-forth through the Messages system and the local model
## (needs Ollama running): prints the conversation and reply timings.
##   godot --headless --path . res://tests/convo_check.tscn -- --test
var llm: LlmClient


func _ready() -> void:
	Game.settings["llm_on"] = true
	Game.end_career()
	Game.create_my_player("Testee", "Rifler", "Canada")
	Game.start_career()
	var w := Game.pworld
	var s := w.soc()
	s.llm_on = true
	llm = LlmClient.new()
	llm.timeout = 150.0
	add_child(llm)
	var mate: PlayerData = null
	for p: PlayerData in w.user_team().roster:
		if not p.is_user:
			mate = p
	var key := "p:%d" % mate.uid
	print("== DM with %s (%s)" % [mate.player_name, ChatText.voice(mate)])
	for line in ["yo, how you feeling about the next match?", "honestly i think our mid rounds are a mess, you agree?",
			"what would you change if you were igl?", "fair. wanna grind some retakes tonight?"]:
		await _say(s, key, line)
	print("== Team chat")
	for line in ["boys we need to talk about the last loss", "i'm not blaming anyone, i just want us to communicate more"]:
		await _say(s, "team", line)
	Game.end_career()
	get_tree().quit()


func _say(s: Social, key: String, line: String) -> void:
	var t0 := Time.get_unix_time_from_system()
	s.send(key, line)
	print("  you: %s" % line)
	var jobs := s.take_llm_jobs()
	for j: Dictionary in jobs:
		var done := [false]
		var hist := s.llm_history(j.th, j.msg)
		llm.chat(String(j.system), String(j.user), func(t: String) -> void:
			if t != "":
				j.msg.text = t
				j.msg.llm = true
			j.msg.erase("pending")
			done[0] = true, 60, hist)
		while not done[0]:
			await get_tree().process_frame
		print("  %s (+%.1fs%s): %s" % [j.msg.who, float(j.msg.get("at", t0)) - t0, "" if j.msg.get("llm", false) else ", template", j.msg.text])
