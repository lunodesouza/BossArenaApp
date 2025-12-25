extends Node2D

@onready var players_container: Node2D = $PlayersContainer

const PlayerScene = preload("res://scenes/Player.tscn")

var players: Dictionary = {}
var spawn_positions: Dictionary = {} # player_id -> Vector2 (server-authoritative)

func _ready():
	# Criar o próprio player localmente
	var my_id = multiplayer.get_unique_id()
	_create_player(my_id)
	
	# Se for servidor, criar players para todos os peers já conectados
	if multiplayer.is_server():
		# Server decides spawn positions and tells everyone.
		_server_spawn_player_for_all(my_id)

		for peer_id in multiplayer.get_peers():
			_server_spawn_player_for_all(peer_id)
	
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

func _server_get_spawn_position(player_id: int) -> Vector2:
	if spawn_positions.has(player_id):
		return spawn_positions[player_id]
	# Simple grid around origin (stable, avoids collisions)
	var idx := spawn_positions.size()
	var spacing := 120.0
	var cols := 4
	var x := (idx % cols) * spacing
	var y := int(idx / cols) * spacing
	var pos := Vector2(x, y)
	# Center around 0,0
	pos -= Vector2((cols - 1) * spacing * 0.5, spacing * 0.5)
	spawn_positions[player_id] = pos
	return pos

func _server_spawn_player_for_all(player_id: int) -> void:
	var pos := _server_get_spawn_position(player_id)
	_create_player(player_id, pos)
	spawn_player.rpc(player_id, pos)

func _create_player(player_id: int, spawn_pos: Variant = null):
	# If already exists, update position if provided (important for clients: they may create locally first)
	if players.has(player_id):
		if spawn_pos != null:
			players[player_id].position = spawn_pos
		return
	
	var player = PlayerScene.instantiate()
	player.player_id = player_id
	player.name = "Player" + str(player_id)
	if spawn_pos != null:
		player.position = spawn_pos
	else:
		player.position = Vector2.ZERO
	players_container.add_child(player, true)  # force_readable_name = true para multiplayer
	players[player_id] = player

@rpc("any_peer", "call_local", "reliable")
func spawn_player(player_id: int, spawn_pos: Vector2):
	_create_player(player_id, spawn_pos)

func _on_player_connected(player_id: int):
	# Se for servidor, sincronizar com outros clientes
	if multiplayer.is_server():
		# Spawn the new player everywhere (with server-selected position)
		_server_spawn_player_for_all(player_id)

		# Sync all existing players to the newly connected peer (positions included)
		for existing_id in spawn_positions.keys():
			spawn_player.rpc_id(player_id, existing_id, spawn_positions[existing_id])

func _on_player_disconnected(player_id: int):
	if players.has(player_id):
		players[player_id].queue_free()
		players.erase(player_id)
		if spawn_positions.has(player_id):
			spawn_positions.erase(player_id)
		# Sincronizar remoção
		if multiplayer.is_server():
			remove_player.rpc(player_id)

@rpc("any_peer", "call_local", "reliable")
func remove_player(player_id: int):
	if players.has(player_id):
		players[player_id].queue_free()
		players.erase(player_id)

