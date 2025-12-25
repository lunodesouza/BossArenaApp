extends Control

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var client_button: Button = $VBoxContainer/ClientButton
@onready var room_code_input: LineEdit = $VBoxContainer/RoomCodeInput
@onready var player_name_label: Label = $VBoxContainer/PlayerNameLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var server_option: OptionButton = $VBoxContainer/ServerOption

func _ready():
	# Sinais de UI já estão conectados na cena (.tscn)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
	# Mostrar nome do jogador
	player_name_label.text = "Jogador: " + PlayerData.get_player_name()
	
	# Configurar opções do servidor
	server_option.add_item("Público")
	server_option.add_item("Local")
	server_option.selected = 0  # Padrão: tomfol.io
	
	# Focar no input de código de sala
	room_code_input.placeholder_text = "Cole o código da sala aqui"

func _get_noray_address() -> String:
	if server_option.selected == 0:
		return "tomfol.io"
	else:
		return "localhost"

func _on_host_pressed():
	status_label.text = "Criando servidor..."
	host_button.disabled = true
	client_button.disabled = true
	server_option.disabled = true
	NetworkManager.start_host(_get_noray_address())

func _on_client_pressed():
	var input = room_code_input.text.strip_edges()
	if input.is_empty():
		status_label.text = "Por favor, insira o código da sala ou OID!"
		return
	
	status_label.text = "Conectando..."
	host_button.disabled = true
	client_button.disabled = true
	server_option.disabled = true
	room_code_input.editable = false
	
	# Aceitar tanto código formatado (HTTR-PCC7) quanto OID direto
	# O código formatado é apenas visual, o cliente precisa do OID real do noray
	# Por enquanto, aceitamos ambos e tentamos conectar
	NetworkManager.start_client(input, _get_noray_address())

func _on_connection_succeeded():
	if NetworkManager.is_host:
		status_label.text = "Sala criada! Código: " + NetworkManager.room_code
		# Mudar para o lobby após um breve delay
		await get_tree().create_timer(1.0).timeout
		get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
	else:
		status_label.text = "Conectado!"
		await get_tree().create_timer(1.0).timeout
		get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _on_connection_failed():
	status_label.text = "Falha na conexão. Verifique se está usando o mesmo servidor noray que o host!"
	host_button.disabled = false
	client_button.disabled = false
	server_option.disabled = false
	room_code_input.editable = true
