extends Node
class_name StatsComponent

## Server-authoritative stats.
## Replicate only the runtime state (hp/xp/level/class_id) via MultiplayerSynchronizer.

@export var class_id: String = "warrior"

var level: int = 1
var xp: int = 0
var hp: int = 1

var base_stats: PlayerStats

@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

func _ready() -> void:
	# Determine authority from parent (Player has player_id)
	var auth_id := 1
	var parent := get_parent()
	if parent:
		# Using get("player_id") is safe even if the property doesn't exist (returns null)
		var pid = parent.get("player_id")
		if typeof(pid) == TYPE_INT and int(pid) != 0:
			auth_id = int(pid)
		else:
			auth_id = multiplayer.get_unique_id()
	else:
		auth_id = multiplayer.get_unique_id()

	set_multiplayer_authority(auth_id)

	if synchronizer:
		synchronizer.set_multiplayer_authority(auth_id)
		# Replication config is defined in the scene; only fall back if missing.
		if synchronizer.replication_config == null:
			var cfg := SceneReplicationConfig.new()
			cfg.add_property(NodePath(".:class_id"))
			cfg.add_property(NodePath(".:level"))
			cfg.add_property(NodePath(".:xp"))
			cfg.add_property(NodePath(".:hp"))
			synchronizer.replication_config = cfg

	_apply_class_defaults()

	# Initialize only on server; clients will get state via synchronizer.
	if multiplayer.is_server():
		hp = max_hp()

func _apply_class_defaults() -> void:
	# Keep it simple for now: presets in code. You can later move these to .tres Resources.
	base_stats = PlayerStats.new()
	match class_id:
		"warrior":
			base_stats.strength = 4
			base_stats.agility = 2
			base_stats.vitality = 4
			base_stats.physical_resistance = 2
			base_stats.magic_resistance = 0
		"mage":
			base_stats.strength = 1
			base_stats.agility = 2
			base_stats.vitality = 2
			base_stats.physical_resistance = 0
			base_stats.magic_resistance = 3
		"rogue":
			base_stats.strength = 2
			base_stats.agility = 4
			base_stats.vitality = 2
			base_stats.physical_resistance = 1
			base_stats.magic_resistance = 0
		_:
			# Default baseline
			base_stats.strength = 2
			base_stats.agility = 2
			base_stats.vitality = 2

func max_hp() -> int:
	return base_stats.max_hp(level) if base_stats else 50

func xp_to_next_level() -> int:
	# Simple curve; change as needed
	return 100 + (level - 1) * 50

func gain_xp(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if amount <= 0:
		return
	xp += amount
	while xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		hp = max_hp()

func apply_damage(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if amount <= 0:
		return
	hp = max(hp - amount, 0)

func heal(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if amount <= 0:
		return
	hp = min(hp + amount, max_hp())
