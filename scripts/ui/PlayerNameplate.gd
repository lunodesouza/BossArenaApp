extends Label

const UPDATE_INTERVAL := 0.15

var _timer := 0.0
var _last_text := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_INTERVAL

	var p := get_parent()
	if p == null:
		return

	var pid_val = p.get("player_id")
	var pid := int(pid_val) if typeof(pid_val) == TYPE_INT else 0

	var display_name := ""
	if Engine.has_singleton("NetworkManager") or NetworkManager != null:
		display_name = NetworkManager.get_player_name(pid)
	if display_name.is_empty():
		display_name = "Player %s" % pid

	var stats := p.get_node_or_null("Stats")
	var hp := 0
	var max_hp := 0
	var xp := 0
	var xp_next := 0
	var level := 1

	if stats:
		hp = int(stats.get("hp"))
		xp = int(stats.get("xp"))
		level = int(stats.get("level"))
		if stats.has_method("max_hp"):
			max_hp = int(stats.call("max_hp"))
		if stats.has_method("xp_to_next_level"):
			xp_next = int(stats.call("xp_to_next_level"))

	var t := "%s\nHP %d/%d\nXP %d/%d\nLv %d" % [display_name, hp, max_hp, xp, xp_next, level]
	if t != _last_text:
		text = t
		_last_text = t


