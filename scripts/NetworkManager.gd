extends Node

## Gerenciador de rede usando netfox.noray para NAT punchthrough

const MAX_PLAYERS = 4
const PORT = 7777
const DEFAULT_NORAY_ADDRESS := "tomfol.io"
const DEFAULT_NORAY_PORT := 8890
const DEBUG_LOG := false

var multiplayer_peer: ENetMultiplayerPeer
var is_host: bool = false
var host_oid: String = ""
var room_code: String = ""  # Código da sala no formato HTTR-PCC7
var is_connecting: bool = false  # Flag para evitar múltiplas conexões simultâneas

enum Role { NONE, HOST, CLIENT }
var role: Role = Role.NONE

# Client connect state (to avoid multiple attempts when noray emits multiple connect commands)
var _client_connected: bool = false
var _client_relay_requested: bool = false

signal connection_succeeded
signal connection_failed
signal player_connected(player_id: int)
signal player_disconnected(player_id: int)

func _log(msg: String) -> void:
	if DEBUG_LOG:
		print(msg)

## Converte OID do noray para um código de sala mais legível (formato HTTR-PCC7)
func oid_to_room_code(oid: String) -> String:
	# Usar hash do OID para gerar código consistente e determinístico
	var oid_hash = oid.hash()
	var rng = RandomNumberGenerator.new()
	rng.seed = abs(oid_hash)  # Garantir seed positivo
	
	var letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var numbers = "0123456789"
	
	var code = ""
	# Primeira parte: 4 letras (ex: HTTR)
	for i in range(4):
		code += letters[rng.randi() % letters.length()]
	
	code += "-"
	
	# Segunda parte: 3 letras (ex: PCC)
	for i in range(3):
		code += letters[rng.randi() % letters.length()]
	
	# Adicionar um número no final (ex: 7)
	code += numbers[rng.randi() % numbers.length()]
	
	return code

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Noray connect callbacks are essential for the handshake flow.
	# See netfox example: examples/shared/scripts/noray-bootstrapper.gd
	if not Noray.on_connect_nat.is_connected(_on_noray_connect_nat):
		Noray.on_connect_nat.connect(_on_noray_connect_nat)
	if not Noray.on_connect_relay.is_connected(_on_noray_connect_relay):
		Noray.on_connect_relay.connect(_on_noray_connect_relay)

func start_host(noray_address: String = DEFAULT_NORAY_ADDRESS, noray_port: int = DEFAULT_NORAY_PORT):
	_log("Iniciando como Host...")
	is_host = true
	role = Role.HOST
	_client_connected = false
	_client_relay_requested = false
	is_connecting = false
	host_oid = ""
	room_code = ""
	# Ensure we don't keep an old peer around
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	
	# Conectar ao noray (é uma coroutine, precisa de await)
	var err = await Noray.connect_to_host(noray_address, noray_port)
	if err != OK:
		print("Erro ao conectar ao noray: ", err)
		connection_failed.emit()
		return
	
	# Registrar como host
	err = Noray.register_host()
	if err != OK:
		print("Erro ao registrar host: ", err)
		connection_failed.emit()
		return
	
	# Aguardar OID e PID
	await Noray.on_oid
	await Noray.on_pid
	
	# Gerar código de sala a partir do OID
	room_code = oid_to_room_code(Noray.oid)
	_log("Host registrado com OID: %s" % Noray.oid)
	_log("Código da sala: %s" % room_code)
	
	# Registrar porta remota
	err = await Noray.register_remote()
	if err != OK:
		print("Erro ao registrar porta remota: ", err)
		connection_failed.emit()
		return
	
	# Usar a porta registrada no Noray (importante para o handshake funcionar)
	var server_port = Noray.local_port if Noray.local_port > 0 else PORT
	_log("Usando porta registrada: %s" % server_port)
	
	# Criar servidor ENet na porta registrada
	# No Windows, não podemos fazer bind na mesma porta duas vezes,
	# então vamos criar o servidor ENet primeiro
	multiplayer_peer = ENetMultiplayerPeer.new()
	err = multiplayer_peer.create_server(server_port, MAX_PLAYERS)
	if err != OK:
		print("Erro ao criar servidor ENet: ", err)
		connection_failed.emit()
		return
	
	multiplayer.multiplayer_peer = multiplayer_peer
	
	# Aguardar servidor iniciar (como no exemplo)
	while multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		await get_tree().process_frame
	
	if multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		print("Falha ao iniciar servidor com status: ", multiplayer_peer.get_connection_status())
		connection_failed.emit()
		return
	
	# Habilitar relay no servidor (como no exemplo)
	multiplayer.server_relay = true
	
	_log("Servidor ENet criado na porta %s" % server_port)
	connection_succeeded.emit()

func start_client(host_oid_to_connect: String, noray_address: String = DEFAULT_NORAY_ADDRESS, noray_port: int = DEFAULT_NORAY_PORT):
	_log("Conectando como Cliente...")
	is_host = false
	role = Role.CLIENT
	host_oid = host_oid_to_connect
	_client_connected = false
	_client_relay_requested = false
	is_connecting = false
	room_code = ""
	# Ensure we don't keep an old peer around
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	
	# Conectar ao noray (é uma coroutine, precisa de await)
	var err = await Noray.connect_to_host(noray_address, noray_port)
	if err != OK:
		print("Erro ao conectar ao noray: ", err)
		connection_failed.emit()
		return
	
	# Cliente precisa registrar como host temporariamente para obter PID
	# Isso é necessário para registrar a porta remota (usado no relay)
	err = Noray.register_host()
	if err != OK:
		print("Erro ao registrar host temporário: ", err)
		connection_failed.emit()
		return
	
	# Aguardar PID (não precisamos do OID, apenas do PID)
	await Noray.on_pid
	
	# Registrar porta remota (necessário para relay funcionar)
	err = await Noray.register_remote()
	if err != OK:
		print("Erro ao registrar porta remota: ", err)
		# Continuar mesmo assim, pode funcionar via NAT direto, mas relay pode falhar
		_log("Continuando sem porta remota registrada (relay pode falhar)...")
	
	# Ask noray to connect (noray will emit on_connect_nat / on_connect_relay with address:port)
	err = Noray.connect_nat(host_oid_to_connect)
	if err != OK:
		print("Erro ao solicitar conexão via NAT: ", err)
		connection_failed.emit()
		return

func _on_noray_connect_nat(address: String, port: int) -> void:
	# Host also receives this when a client requests to connect
	# Client receives this when noray tells it which endpoint to connect to
	await _handle_connect_nat(address, port)

func _on_noray_connect_relay(address: String, port: int) -> void:
	await _handle_connect_relay(address, port)

func _handle_connect_nat(address: String, port: int) -> void:
	var err = await _handle_connect(address, port)
	# If client failed to connect over NAT, try again over relay (same as netfox example)
	if err != OK and role == Role.CLIENT and not _client_relay_requested and not _client_connected:
		_client_relay_requested = true
		_log("NAT connect falhou (%s), tentando relay..." % error_string(err))
		Noray.connect_relay(host_oid)

func _handle_connect_relay(address: String, port: int) -> void:
	var err = await _handle_connect(address, port)
	if err != OK and role == Role.CLIENT and not _client_connected:
		_log("Relay connect falhou (%s)" % error_string(err))
		connection_failed.emit()

func _handle_connect(address: String, port: int) -> Error:
	# Evitar múltiplas tentativas de conexão simultâneas
	if is_connecting:
		_log("Já está tentando conectar, ignorando tentativa duplicada")
		return ERR_BUSY
	
	# Validar endereço e porta antes de tentar conectar
	if address.is_empty() or address.contains("AssertionError") or address.contains("ERR"):
		print("Erro: Endereço inválido recebido: ", address)
		return ERR_INVALID_PARAMETER
	
	if port <= 0 or port > 65535:
		print("Erro: Porta inválida recebida: ", port)
		return ERR_INVALID_PARAMETER

	# HOST: when noray tells us the remote endpoint, answer the handshake using ENet socket.
	if role == Role.HOST:
		if not multiplayer_peer:
			return ERR_UNCONFIGURED
		_log("Host: respondendo handshake para %s:%s" % [address, port])
		return await PacketHandshake.over_enet_peer(multiplayer_peer, address, port)
	
	# CLIENT: perform UDP handshake, then create ENet client bound to Noray.local_port
	is_connecting = true
	_log("Conectando ao host em %s:%s" % [address, port])
	
	# Fazer handshake ANTES de criar o cliente ENet
	# O handshake deve usar a porta registrada no Noray
	var udp = PacketPeerUDP.new()
	var bind_port = Noray.local_port if Noray.local_port > 0 else 0
	var bind_result = udp.bind(bind_port)
	if bind_result != OK:
		print("Erro ao fazer bind na porta ", bind_port, ": ", bind_result)
		# Tentar porta aleatória
		bind_result = udp.bind(0)
		if bind_result != OK:
			print("Erro ao fazer bind em porta aleatória: ", bind_result)
			is_connecting = false
			return bind_result
	
	udp.set_dest_address(address, port)
	_log("Iniciando handshake UDP de %s para %s:%s" % [bind_port, address, port])
	
	var handshake_result = await PacketHandshake.over_packet_peer(udp, 8.0, 0.1)
	udp.close()
	
	# ERR_BUSY significa que conseguimos ler e escrever, mas o handshake completo não foi confirmado.
	# O exemplo oficial tenta conectar mesmo assim.
	if handshake_result == ERR_BUSY:
		_log("Handshake parcial (ERR_BUSY) - tentando conectar mesmo assim...")
		# Continuar com a conexão
	elif handshake_result != OK:
		_log("Handshake falhou com código: %s" % handshake_result)
		is_connecting = false
		return handshake_result
	
	_log("Handshake bem-sucedido! Criando cliente ENet...")
	
	# Criar cliente ENet após handshake bem-sucedido
	# IMPORTANTE: Passar Noray.local_port como último parâmetro (porta local)
	multiplayer_peer = ENetMultiplayerPeer.new()
	var local_port_for_client = Noray.local_port if Noray.local_port > 0 else 0
	var err = multiplayer_peer.create_client(address, port, 0, 0, 0, local_port_for_client)
	if err != OK:
		print("Erro ao criar cliente: ", err)
		is_connecting = false
		return err
	
	multiplayer.multiplayer_peer = multiplayer_peer
	_log("Cliente ENet criado na porta local %s" % local_port_for_client)
	
	# Aguardar conexão estabelecida
	while multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		await get_tree().process_frame
	
	if multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_log("Falha ao conectar com status: %s" % multiplayer_peer.get_connection_status())
		multiplayer.multiplayer_peer = null
		is_connecting = false
		return ERR_CANT_CONNECT
	
	_log("Cliente ENet conectado!")
	_client_connected = true
	# Não emitir connection_succeeded aqui - deixar o sinal connected_to_server fazer isso
	is_connecting = false
	return OK

func _on_peer_connected(player_id: int):
	_log("Jogador conectado: %s" % player_id)
	player_connected.emit(player_id)

func _on_peer_disconnected(player_id: int):
	_log("Jogador desconectado: %s" % player_id)
	player_disconnected.emit(player_id)

func _on_connected_to_server():
	_log("Conectado ao servidor!")
	connection_succeeded.emit()

func _on_connection_failed():
	_log("Falha na conexão!")
	connection_failed.emit()

func _on_server_disconnected():
	_log("Servidor desconectado!")
	connection_failed.emit()


func disconnect_from_server():
	if multiplayer_peer:
		multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	multiplayer_peer = null
	role = Role.NONE
	_client_connected = false
	_client_relay_requested = false
	Noray.disconnect_from_host()
