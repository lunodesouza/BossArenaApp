extends Area2D

const SPEED := 460.0
const LIFE_TIME := 1.6

var direction: Vector2 = Vector2.RIGHT
var damage: int = 10
var _life := LIFE_TIME
var _armed := false

func _ready() -> void:
	direction = direction.normalized()
	body_entered.connect(_on_body_entered)
	await get_tree().process_frame
	_armed = true

func _physics_process(delta: float) -> void:
	position += direction * SPEED * delta
	_life -= delta
	if _life <= 0.0:
		if multiplayer.is_server():
			rpc_despawn.rpc()
		queue_free()

func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if not _armed:
		return
	if body == null:
		return

	# Only damage players
	var victim_id := int(body.get("player_id")) if body.has_method("get") else 0
	if victim_id == 0:
		return

	var stats := body.get_node_or_null("Stats")
	if stats == null:
		return
	if stats.has_method("apply_damage"):
		stats.call("apply_damage", damage)

	var hp_val = stats.get("hp")
	var hp := int(hp_val) if typeof(hp_val) == TYPE_INT else 1
	if hp <= 0:
		var game := get_tree().current_scene
		if game and game.has_method("_server_respawn_player"):
			game.call("_server_respawn_player", victim_id)

	rpc_despawn.rpc()
	queue_free()

@rpc("any_peer", "call_local", "reliable")
func rpc_despawn() -> void:
	queue_free()


