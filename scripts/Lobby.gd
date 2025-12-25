extends Control

@onready var players_label: Label = $VBoxContainer/PlayersLabel
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var room_code_label: Label = $VBoxContainer/RoomCodeLabel
@onready var copy_button: Button = $VBoxContainer/CopyButton
@onready var back_button: Button = $VBoxContainer/BackButton

var players: Dictionary = {}  # player_id -> player_name
var player_count: int = 0
const DEBUG_LOG := false
const DisconnectOverlayScene = preload("res://scenes/ui/DisconnectOverlay.tscn")
var _disconnect_overlay: CanvasLayer = null

func _log(msg: String) -> void:
	if DEBUG_LOG:
		print(msg)

func _get_player_name() -> String:
	# Avoid hard dependency on autoload symbol at compile-time.
	# If PlayerData autoload is present, use it; otherwise fall back.
	var pd = get_tree().root.get_node_or_null("PlayerData")
	if pd and pd.has_method("get_player_name"):
		return pd.call("get_player_name")
	return "Jogador"

func _ready():
	if NetworkManager.is_host:
		# Mostrar código formatado e OID real
		room_code_label.text = "Código: " + NetworkManager.room_code + "\nOID: " + Noray.oid
		start_button.visible = true
	else:
		room_code_label.text = "Aguardando host iniciar o jogo..."
		start_button.visible = false
	
	if NetworkManager.is_host:
		copy_button.visible = true
	else:
		copy_button.visible = false
	
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.player_name_updated.connect(_on_player_name_updated)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	_setup_disconnect_overlay()
	
	# Adicionar o próprio jogador
	var my_id = multiplayer.get_unique_id()
	_add_player(my_id, _get_player_name())
	NetworkManager.set_player_name(my_id, _get_player_name())
	
	# Populate from NetworkManager cache (works across scenes, no Lobby RPCs)
	for pid in NetworkManager.player_names.keys():
		_add_player(int(pid), NetworkManager.get_player_name(int(pid)))
	
	# Ensure roster is available on clients (NetworkManager will also request on connect)
	if not multiplayer.is_server():
		await _wait_for_connection()
		if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			NetworkManager.rpc_request_roster.rpc_id(1)
	else:
		# Host broadcasts its name via autoload RPC so clients get it even if Lobby is gone later
		NetworkManager.rpc_player_name_updated.rpc(1, _get_player_name())
	
	# Atualizar lista
	_update_players_list()

func _setup_disconnect_overlay() -> void:
	if _disconnect_overlay != null:
		return
	_disconnect_overlay = DisconnectOverlayScene.instantiate()
	add_child(_disconnect_overlay)

func _on_server_disconnected() -> void:
	if multiplayer.is_server():
		return
	if _disconnect_overlay and _disconnect_overlay.has_method("show_disconnect"):
		_disconnect_overlay.call("show_disconnect", "Desconectado do servidor")

func _wait_for_connection() -> void:
	# Aguardar até estar conectado (máximo 5 segundos)
	var timeout = 5.0
	while timeout > 0:
		if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			return
		await get_tree().create_timer(0.1).timeout
		timeout -= 0.1

func _on_player_name_updated(player_id: int, player_name: String) -> void:
	_add_player(player_id, player_name)
	_update_players_list()

func _add_player(player_id: int, player_name: String):
	# Add or update (important: we often add placeholders first, then receive the real name)
	if not players.has(player_id) or players[player_id] != player_name:
		players[player_id] = player_name
		player_count = players.size()

## Roster RPCs moved to NetworkManager (autoload) to avoid "Lobby not found" after scene changes.

func _remove_player(player_id: int):
	if players.has(player_id):
		players.erase(player_id)
		player_count = players.size()

func _update_players_list():
	var text = "Jogadores (" + str(player_count) + "/4):\n\n"
	var player_list = players.keys()
	player_list.sort()
	
	for i in range(4):
		if i < player_list.size():
			var pid = player_list[i]
			var pname = players[pid]
			var indicator = " (Você)" if pid == multiplayer.get_unique_id() else ""
			text += str(i + 1) + ". " + pname + indicator + "\n"
		else:
			text += str(i + 1) + ". (vazio)\n"
	players_label.text = text
	
	# Habilitar botão de iniciar apenas se houver pelo menos 1 jogador e for host
	if NetworkManager.is_host:
		start_button.disabled = player_count < 1

func _on_player_connected(player_id: int):
	# Nome será atualizado quando receber via RPC
	_add_player(player_id, "Jogador " + str(player_id))
	_update_players_list()

func _on_player_disconnected(player_id: int):
	_remove_player(player_id)
	_update_players_list()

func _on_start_pressed():
	if NetworkManager.is_host and player_count > 0:
		# Servidor inicia o jogo para todos
		NetworkManager.rpc_start_game.rpc()

func _on_copy_pressed():
	if NetworkManager.is_host and not Noray.oid.is_empty():
		# Copiar OID real (não o código formatado) pois é isso que o cliente precisa
		DisplayServer.clipboard_set(Noray.oid)
		copy_button.text = "OID Copiado!"
		await get_tree().create_timer(2.0).timeout
		copy_button.text = "Copiar OID"

func _on_back_pressed():
	NetworkManager.disconnect_from_server()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
