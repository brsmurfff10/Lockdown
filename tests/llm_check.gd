extends Node
## Asks the configured local model (Settings > Local AI chat) for one in-character line.
##   godot --headless --path . res://tests/llm_check.tscn
func _ready() -> void:
	print("enabled=%s model=%s url=%s" % [LlmClient.enabled(), LlmClient.model(), LlmClient.url()])
	var c := LlmClient.new()
	c.timeout = 150.0
	add_child(c)
	var t0 := Time.get_ticks_msec()
	c.chat("You are Viper, a toxic AWPer on a rival pro team. The player just trash talked your team on social media. Reply in one short chat line, lowercase.",
		"your awper is washed, we're taking the final", func(t: String) -> void:
			print("reply (%.1fs): %s" % [(Time.get_ticks_msec() - t0) / 1000.0, t if t != "" else "<none>"])
			get_tree().quit())
