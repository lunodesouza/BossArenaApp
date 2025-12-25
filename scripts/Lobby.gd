extends Control

@onready var players_label: Label = $VBoxContainer/PlayersLabel
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var room_code_label: Label = $VBoxContainer/RoomCodeLabel
@onready var copy_button: Button = $VBoxContainer/CopyButton
@onready var back_button: Button = $VBoxContainer/BackButton

var players: Dictionary = {}  # player_id -> player_name
var player_count: int = 0

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
		# Sinais já estão conectados na cena, não precisamos conectar novamente
		# start_button.pressed.connect(_on_start_pressed)
	else:
		room_code_label.text = "Aguardando host iniciar o jogo..."
		start_button.visible = false
	
	# Sinais já estão conectados na cena
	# back_button.pressed.connect(_on_back_pressed)
	
	if NetworkManager.is_host:
		copy_button.visible = true
		# Sinais já estão conectados na cena
		# copy_button.pressed.connect(_on_copy_pressed)
	else:
		copy_button.visible = false
	
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	
	# Adicionar o próprio jogador
	var my_id = multiplayer.get_unique_id()
	_add_player(my_id, _get_player_name())
	
	# Enviar nosso nome para outros players
	if multiplayer.is_server():
		# Ensure host name is broadcast (clients that load Lobby after connecting still get it)
		broadcast_player_name.rpc(1, _get_player_name())
		
		# Servidor não precisa enviar, já tem seu próprio nome
		# Mas precisa solicitar nomes dos clientes conectados
		for peer_id in multiplayer.get_peers():
			_add_player(peer_id, "Jogador " + str(peer_id))  # Nome temporário
			# Push our current roster to peers that are already connected (common case!)
			_send_full_roster_to_peer(peer_id)
			# Solicitar nome do cliente
			request_player_name.rpc_id(peer_id)
	else:
		# Cliente aguarda estar conectado antes de enviar nome
		await _wait_for_connection()
		if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			send_player_name_to_server.rpc_id(1, _get_player_name())
			# Ask server for full roster (covers the case where we joined before Lobby was loaded)
			request_full_roster.rpc_id(1)
	
	# Atualizar lista
	_update_players_list()

func _wait_for_connection() -> void:
	# Aguardar até estar conectado (máximo 5 segundos)
	var timeout = 5.0
	while timeout > 0:
		if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			return
		await get_tree().create_timer(0.1).timeout
		timeout -= 0.1

# Cliente envia nome para servidor
@rpc("any_peer", "reliable")
func send_player_name_to_server(player_name: String):
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	print("Servidor recebeu nome do player ", sender_id, ": ", player_name)
	_add_player(sender_id, player_name)
	_update_players_list()
	
	# Servidor retransmite para todos os outros clientes
	broadcast_player_name.rpc(sender_id, player_name)

# Servidor solicita nome do cliente
@rpc("any_peer", "reliable")
func request_player_name():
	if multiplayer.is_server():
		return
	
	var my_name = _get_player_name()
	print("Cliente recebeu solicitação de nome, enviando: ", my_name)
	# Cliente responde com seu nome
	send_player_name_to_server.rpc_id(1, my_name)

# Servidor transmite nome para todos os clientes
@rpc("any_peer", "call_local", "reliable")
func broadcast_player_name(player_id: int, player_name: String):
	print("Recebido broadcast de nome: Player ", player_id, " = ", player_name)
	_add_player(player_id, player_name)
	_update_players_list()

func _add_player(player_id: int, player_name: String):
	# Add or update (important: we often add placeholders first, then receive the real name)
	if not players.has(player_id) or players[player_id] != player_name:
		players[player_id] = player_name
		player_count = players.size()

func _send_full_roster_to_peer(peer_id: int) -> void:
	# Send all currently known players (including host) to a newly joined peer.
	# This fixes "client doesn't see server" in lobby.
	if not multiplayer.is_server():
		return
	for pid in players.keys():
		broadcast_player_name.rpc_id(peer_id, pid, players[pid])

@rpc("any_peer", "reliable")
func request_full_roster():
	# Client asks server to resend the full roster.
	if not multiplayer.is_server():
		return
	var requester_id = multiplayer.get_remote_sender_id()
	_send_full_roster_to_peer(requester_id)

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
	
	# Se for servidor, solicitar nome do novo cliente
	if multiplayer.is_server():
		# First, ensure the new client learns about the host (and any already known players).
		_send_full_roster_to_peer(player_id)
		request_player_name.rpc_id(player_id)
		# Also broadcast host name to everyone (covers cases where client never had host entry)
		broadcast_player_name.rpc(1, players.get(1, _get_player_name()))

func _on_player_disconnected(player_id: int):
	_remove_player(player_id)
	_update_players_list()

func _on_start_pressed():
	if NetworkManager.is_host and player_count > 0:
		# Servidor inicia o jogo para todos
		start_game.rpc()

@rpc("any_peer", "call_local", "reliable")
func start_game():
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

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
