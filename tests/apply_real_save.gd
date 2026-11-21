extends Node
## One-off tool: applies the real teams pack to your REAL My Player save
## (user://player_career.json), after copying it to player_career.json.pre_real.
## Run with the game closed:  godot --headless --path . res://tests/apply_real_save.tscn


func _ready() -> void:
	var path := Game.PLAYER_CAREER_PATH
	if path.contains("test_"):
		print("Refusing: running in --test mode (%s)" % path)
		get_tree().quit(1)
		return
	Game.load_my_player()
	Game.load_player_career()
	var w := Game.pworld
	if w == null:
		print("No My Player career found at %s" % path)
		get_tree().quit(1)
		return
	var ap := ProjectSettings.globalize_path(path)
	DirAccess.copy_absolute(ap, ap + ".pre_real")
	var before := "%s at %s, S%d W%d" % [w.user_player.player_name, w.user_team().team_name, w.season, w.week]
	var n := RealTeams.apply_existing(w)
	Game.save_player_career()
	print("Before: %s" % before)
	print("Renamed %d clubs. You (%s) now play for %s (%s League)." % [n, w.user_player.player_name, w.user_team().team_name, World.LEAGUES[w.user_team().league].name])
	print("Premier League: %s" % ", ".join(w.league_teams(0).map(func(t: TeamData) -> String: return t.team_name)))
	print("Backup: %s.pre_real" % ap)
	get_tree().quit()
