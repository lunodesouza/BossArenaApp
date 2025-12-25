extends CharacterBody2D

const SPEED = 200.0

var player_id: int = 0
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

func _ready():
	# Definir autoridade baseado no ID do jogador
	# Se player_id não foi definido, usar o unique_id
	if player_id == 0:
		player_id = multiplayer.get_unique_id()
	
	set_multiplayer_authority(player_id)
	# Keep synchronizer authority aligned with this player
	if synchronizer:
		synchronizer.set_multiplayer_authority(player_id)
	
	# Apenas o dono do player pode controlá-lo
	set_physics_process(is_multiplayer_authority())

func _physics_process(delta):
	if not is_multiplayer_authority():
		return
	
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
	velocity = direction * SPEED
	
	move_and_slide()
