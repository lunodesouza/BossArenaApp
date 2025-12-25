extends CharacterBody2D

const TARGET_REFRESH := 0.25
const SHOOT_INTERVAL := 0.9
const SHOOT_RANGE := 340.0
const STOP_RANGE := 160.0

@onready var stats: BossStats = $Stats
@onready var hp_bar_fg: Line2D = $HpBarFg

var boss_id: int = 2 # arbitrary non-player id for authority; server owns anyway
var _target_timer := 0.0
var _shoot_timer := 0.0

func _ready() -> void:
	# Server-authoritative: boss is controlled by server (peer 1).
	set_multiplayer_authority(1)
	_shoot_timer = SHOOT_INTERVAL
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

	_target_timer -= delta
	_shoot_timer -= delta

	var game := get_tree().current_scene
	if game == null:
		return

	# Get nearest player
	var nearest_id := 0
	var nearest_pos := Vector2.ZERO
	var nearest_dist := INF
	if game.has_method("_server_get_nearest_player"):
		var result = game.call("_server_get_nearest_player", global_position)
		if result is Dictionary and result.has("id"):
			nearest_id = int(result["id"])
			nearest_pos = result["pos"]
			nearest_dist = float(result["dist"])

	if nearest_id == 0:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Move towards player if far
	var dir := (nearest_pos - global_position)
	var dist := dir.length()
	if dist > 0.001:
		dir = dir / dist

	var speed := stats.move_speed if stats else 80.0
	if dist > STOP_RANGE:
		velocity = dir * speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	# Shoot if in range
	if dist <= SHOOT_RANGE and _shoot_timer <= 0.0:
		_shoot_timer = SHOOT_INTERVAL
		if stats and stats.is_rage:
			_shoot_timer *= 0.6
		var dmg := stats.roll_damage() if stats else 10
		if game.has_method("_server_spawn_enemy_bullet"):
			game.call("_server_spawn_enemy_bullet", global_position + dir * 32.0, dir, dmg)

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
