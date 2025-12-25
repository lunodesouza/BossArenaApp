extends Node2D

@onready var players_container: Node2D = $PlayersContainer
@onready var projectiles_container: Node2D = $ProjectilesContainer
@onready var boss_container: Node2D = $BossContainer
@onready var camera: Camera2D = $Camera2D

const PlayerScene = preload("res://scenes/Player.tscn")
const BulletScene = preload("res://scenes/Bullet.tscn")
const EnemyBulletScene = preload("res://scenes/EnemyBullet.tscn")
const BossScene = preload("res://scenes/Boss.tscn")
const DisconnectOverlayScene = preload("res://scenes/ui/DisconnectOverlay.tscn")

var players: Dictionary = {}
var spawn_positions: Dictionary = {} # player_id -> Vector2 (server-authoritative)
const GRID_SPACING := 120.0
const GRID_COLS := 4

const RESPAWN_DELAY := 1.0
const PLAYER_DEATH_RESPAWN_DELAY := 1.0

var _local_player_id: int = 0
var _camera_target: Node2D = null
var _disconnect_overlay: CanvasLayer = null

func _ready():
	# Criar o próprio player localmente
	var my_id = multiplayer.get_unique_id()
	_local_player_id = my_id
	_create_player(my_id)
	_setup_camera_follow(my_id)
	
	# Se for servidor, criar players para todos os peers já conectados
	if multiplayer.is_server():
		# Server decides spawn positions and tells everyone.
		_server_spawn_player_for_all(my_id)

		for peer_id in multiplayer.get_peers():
			_server_spawn_player_for_all(peer_id)

		# Spawn boss a bit far away so combat doesn't start instantly.
		_server_spawn_boss_far()
	
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	_setup_disconnect_overlay()

func _setup_disconnect_overlay() -> void:
	if _disconnect_overlay != null:
		return
	_disconnect_overlay = DisconnectOverlayScene.instantiate()
	add_child(_disconnect_overlay)

func _on_server_disconnected() -> void:
	# Only clients should react
	if multiplayer.is_server():
		return
	if _disconnect_overlay and _disconnect_overlay.has_method("show_disconnect"):
		_disconnect_overlay.call("show_disconnect", "Desconectado do servidor")

func _setup_camera_follow(local_id: int) -> void:
	if camera == null:
		return
	# Keep camera under Game root; just follow target position locally.
	_camera_target = players.get(local_id, null)
	if _camera_target == null:
		await get_tree().process_frame
		_camera_target = players.get(local_id, null)
	if _camera_target == null:
		return
	camera.enabled = true
	camera.make_current()
	camera.global_position = _camera_target.global_position

func _process(_delta: float) -> void:
	if camera == null:
		return
	if _camera_target == null:
		# Try to reacquire (e.g., after respawn/spawn order changes)
		_camera_target = players.get(_local_player_id, null)
		if _camera_target == null:
			return
	camera.global_position = _camera_target.global_position

@rpc("any_peer", "reliable")
func request_shoot(dir: Vector2) -> void:
	# Clients request; server validates and spawns.
	if not multiplayer.is_server():
		return
	var shooter_id := multiplayer.get_remote_sender_id()
	if shooter_id == 0:
		shooter_id = multiplayer.get_unique_id()
	_server_spawn_bullet(shooter_id, dir)

func _server_spawn_bullet(shooter_id: int, dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if dir.length() < 0.1:
		return
	if not players.has(shooter_id):
		return
	var p = players[shooter_id]
	var spawn_pos: Vector2 = p.global_position + dir.normalized() * 24.0
	spawn_bullet.rpc(shooter_id, spawn_pos, dir.normalized())

@rpc("any_peer", "call_local", "reliable")
func spawn_bullet(shooter_id: int, spawn_pos: Vector2, dir: Vector2) -> void:
	var b = BulletScene.instantiate()
	b.shooter_id = shooter_id
	b.direction = dir
	b.global_position = spawn_pos
	projectiles_container.add_child(b, true)

@rpc("any_peer", "call_local", "reliable")
func spawn_enemy_bullet(spawn_pos: Vector2, dir: Vector2, damage: int) -> void:
	var b = EnemyBulletScene.instantiate()
	b.direction = dir
	b.damage = damage
	b.global_position = spawn_pos
	projectiles_container.add_child(b, true)

func _server_spawn_enemy_bullet(spawn_pos: Vector2, dir: Vector2, damage: int) -> void:
	if not multiplayer.is_server():
		return
	if dir.length() < 0.1:
		return
	spawn_enemy_bullet.rpc(spawn_pos, dir.normalized(), damage)

func _server_respawn_player(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(player_id):
		return
	var victim = players[player_id]
	var victim_stats = victim.get_node_or_null("Stats")
	await get_tree().create_timer(PLAYER_DEATH_RESPAWN_DELAY).timeout
	if victim_stats and victim_stats.has_method("max_hp"):
		var max_hp = int(victim_stats.call("max_hp"))
		if victim_stats.has_method("heal"):
			victim_stats.call("heal", max_hp)
		else:
			victim_stats.set("hp", max_hp)
	# Reset position
	if spawn_positions.has(player_id):
		victim.global_position = spawn_positions[player_id]

func _server_get_nearest_player(from_pos: Vector2) -> Dictionary:
	var best_id := 0
	var best_dist := INF
	var best_pos := Vector2.ZERO
	for pid in players.keys():
		var p = players[pid]
		if p == null:
			continue
		var stats = p.get_node_or_null("Stats")
		if stats and int(stats.get("hp")) <= 0:
			continue
		var d := from_pos.distance_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best_id = int(pid)
			best_pos = p.global_position
	return {"id": best_id, "pos": best_pos, "dist": best_dist}

func _server_spawn_boss_far() -> void:
	if not multiplayer.is_server():
		return
	# Choose a spawn far from players' average position
	var avg := Vector2.ZERO
	var count := 0
	for pid in players.keys():
		avg += players[pid].global_position
		count += 1
	if count > 0:
		avg /= float(count)
	var boss_pos := avg + Vector2(700, -500)
	spawn_boss.rpc(boss_pos)

@rpc("any_peer", "call_local", "reliable")
func spawn_boss(boss_pos: Vector2) -> void:
	# Only spawn one boss
	if boss_container.get_child_count() > 0:
		return
	var boss = BossScene.instantiate()
	boss.global_position = boss_pos
	boss_container.add_child(boss, true)

func _server_boss_died(killer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Award XP to killer
	if players.has(killer_id):
		var killer = players[killer_id]
		var killer_stats = killer.get_node_or_null("Stats")
		if killer_stats and killer_stats.has_method("gain_xp"):
			# Boss XP reward is stored on boss stats; fall back to 120
			var reward := 120
			if boss_container.get_child_count() > 0:
				var boss = boss_container.get_child(0)
				var bs = boss.get_node_or_null("Stats")
				if bs:
					var xr = bs.get("xp_reward")
					if typeof(xr) == TYPE_INT:
						reward = int(xr)
			killer_stats.call("gain_xp", reward)

func _server_get_spawn_position(player_id: int) -> Vector2:
	if spawn_positions.has(player_id):
		return spawn_positions[player_id]
	# Simple grid around origin (stable, avoids collisions)
	var idx := spawn_positions.size()
	var x := (idx % GRID_COLS) * GRID_SPACING
	var y := int(float(idx) / float(GRID_COLS)) * GRID_SPACING
	var pos := Vector2(x, y)
	# Center around 0,0
	pos -= Vector2((GRID_COLS - 1) * GRID_SPACING * 0.5, GRID_SPACING * 0.5)
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
