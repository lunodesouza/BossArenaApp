extends CharacterBody2D

@onready var stats: BossStats = $Stats
@onready var hp_bar_fg: Line2D = $HpBarFg
@onready var brain: BossBrain = $Brain

var boss_id: int = 2 # arbitrary non-player id for authority; server owns anyway

func _ready() -> void:
	# Server-authoritative: boss is controlled by server (peer 1).
	set_multiplayer_authority(1)
	if stats:
		stats.died.connect(_on_died)
	# Ensure boss stays in group even if scene was edited
	if not is_in_group("boss"):
		add_to_group("boss")

@rpc("any_peer", "call_local", "reliable")
func rpc_despawn() -> void:
	queue_free()

func _process(_delta: float) -> void:
	# Update HP bar on all peers (hp/max_hp replicated from server)
	if hp_bar_fg == null or stats == null:
		return
	var max_hp: int = max(1, int(stats.max_hp))
	var ratio: float = clamp(float(stats.hp) / float(max_hp), 0.0, 1.0)
	var half: float = 60.0
	hp_bar_fg.points = PackedVector2Array([
		Vector2(-half, 0.0),
		Vector2(-half + (half * 2.0 * ratio), 0.0),
	])

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if stats and stats.hp <= 0:
		return
	# Brain decides velocity + when to fire; boss applies physics.
	if brain:
		brain.tick(delta)
	move_and_slide()

func _boss_get_nearest_player(from_pos: Vector2) -> Dictionary:
	# Called by BossBrain
	var game := get_tree().current_scene
	if game and game.has_method("_server_get_nearest_player"):
		return game.call("_server_get_nearest_player", from_pos)
	return {"id": 0, "pos": Vector2.ZERO, "dist": INF}

func _boss_fire(dir: Vector2) -> void:
	# Called by BossBrain
	var game := get_tree().current_scene
	if game == null:
		return
	var dmg := stats.roll_damage() if stats else 10
	if game.has_method("_server_spawn_enemy_bullet"):
		game.call("_server_spawn_enemy_bullet", global_position + dir.normalized() * 32.0, dir.normalized(), dmg)

func _on_died(killer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Inform game to award XP and handle boss death.
	var game := get_tree().current_scene
	if game and game.has_method("_server_boss_died"):
		game.call("_server_boss_died", killer_id)
	# Despawn on all peers (clients otherwise keep the node frozen)
	rpc_despawn.rpc()
	queue_free()
