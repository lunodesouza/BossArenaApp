extends CharacterBody2D

const SPEED = 200.0
const SHOOT_COOLDOWN := 0.25

var player_id: int = 0
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
var _aim_dir := Vector2.RIGHT
var _shoot_cd := 0.0

func _ready():
	# Definir autoridade baseado no ID do jogador
	# Se player_id não foi definido, usar o unique_id
	if player_id == 0:
		player_id = multiplayer.get_unique_id()
	
	set_multiplayer_authority(player_id)
	# Keep synchronizer authority aligned with this player
	if synchronizer:
		synchronizer.set_multiplayer_authority(player_id)
		# Replication config is defined in the scene; only fall back if missing.
		if synchronizer.replication_config == null:
			var cfg := SceneReplicationConfig.new()
			cfg.add_property(NodePath(".:position"))
			synchronizer.replication_config = cfg
	
	# Apenas o dono do player pode controlá-lo
	set_physics_process(is_multiplayer_authority())

func _physics_process(_delta):
	if not is_multiplayer_authority():
		return
	
	_shoot_cd = max(_shoot_cd - _delta, 0.0)
	
	var direction = Vector2.ZERO
	
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	
	direction = direction.normalized()
	if direction.length() > 0.1:
		_aim_dir = direction
	velocity = direction * SPEED
	
	move_and_slide()

	# Shoot (Space = ui_accept by default)
	if Input.is_action_just_pressed("ui_accept") and _shoot_cd <= 0.0:
		_shoot_cd = SHOOT_COOLDOWN
		_try_shoot(_aim_dir)

func _try_shoot(dir: Vector2) -> void:
	var game := get_tree().current_scene
	if game == null:
		return
	# If we're the server, call directly; if we're a client, request to server (peer 1).
	if multiplayer.is_server():
		if game.has_method("_server_spawn_bullet"):
			game.call("_server_spawn_bullet", player_id, dir)
	else:
		if game.has_method("request_shoot"):
			# request_shoot is an RPC method on Game.gd
			game.request_shoot.rpc_id(1, dir)
