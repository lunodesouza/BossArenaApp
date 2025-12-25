extends CharacterBody2D

const SPEED = 200.0
const SYNC_INTERVAL = 0.1  # Sincronizar a cada 0.1 segundos

@onready var sprite: Sprite2D = $Sprite2D

var player_id: int = 0
var sync_timer: float = 0.0

func _ready():
	# Definir autoridade baseado no ID do jogador
	# Se player_id não foi definido, usar o unique_id
	if player_id == 0:
		player_id = multiplayer.get_unique_id()
	
	set_multiplayer_authority(player_id)
	
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
	
	# Sincronizar posição periodicamente
	sync_timer += delta
	if sync_timer >= SYNC_INTERVAL:
		update_position.rpc(position)
		sync_timer = 0.0

@rpc("any_peer", "unreliable")
func update_position(new_position: Vector2):
	if not is_multiplayer_authority():
		position = new_position
