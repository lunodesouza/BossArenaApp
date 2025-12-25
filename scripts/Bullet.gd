extends Area2D

const SPEED := 520.0
const LIFE_TIME := 1.2
const DAMAGE := 15

var shooter_id: int = 0
var direction: Vector2 = Vector2.RIGHT
var _life := LIFE_TIME
var _armed := false

func _ready() -> void:
	direction = direction.normalized()
	body_entered.connect(_on_body_entered)
	# Avoid instant hit when spawning overlapped with a player.
	await get_tree().process_frame
	_armed = true

func _physics_process(delta: float) -> void:
	position += direction * SPEED * delta
	_life -= delta
	if _life <= 0.0:
		# Only the server tells everyone to despawn (prevents double-despawn spam).
		if multiplayer.is_server():
			rpc_despawn.rpc()
		queue_free()

func _on_body_entered(body: Node) -> void:
	# Only server applies damage.
	if not multiplayer.is_server():
		return
	if not _armed:
		return

	# Ignore invalid bodies
	if body == null:
		return

	# Players should only damage the boss (no PvP)
	if not body.is_in_group("boss"):
		return

	var stats := body.get_node_or_null("Stats")
	if stats == null:
		return

	# BossStats.apply_damage(amount, attacker_id)
	if stats.has_method("apply_damage"):
		stats.call("apply_damage", DAMAGE, shooter_id)

	# Despawn bullet for everyone
	rpc_despawn.rpc()
	queue_free()

@rpc("any_peer", "call_local", "reliable")
func rpc_despawn() -> void:
	queue_free()


