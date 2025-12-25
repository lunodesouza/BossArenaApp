extends Control

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var client_button: Button = $VBoxContainer/ClientButton
@onready var oid_input: LineEdit = $VBoxContainer/OIDInput
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var server_option: OptionButton = $VBoxContainer/ServerOption

func _ready():
	host_button.pressed.connect(_on_host_pressed)
	client_button.pressed.connect(_on_client_pressed)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
	# Configurar opções do servidor
	server_option.add_item("tomfol.io (Público)")
	server_option.add_item("localhost (Local)")
	server_option.selected = 0  # Padrão: tomfol.io

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
	var oid = oid_input.text.strip_edges()
	if oid.is_empty():
		status_label.text = "Por favor, insira o OID do host!"
		return
	
	status_label.text = "Conectando..."
	host_button.disabled = true
	client_button.disabled = true
	server_option.disabled = true
	NetworkManager.start_client(oid, _get_noray_address())

func _on_connection_succeeded():
	if NetworkManager.is_host:
		status_label.text = "Servidor criado! OID: " + Noray.oid
		# Mudar para o lobby após um breve delay
		await get_tree().create_timer(1.0).timeout
		get_tree().change_scene_to_file("res://Lobby.tscn")
	else:
		status_label.text = "Conectado!"
		await get_tree().create_timer(1.0).timeout
		get_tree().change_scene_to_file("res://Lobby.tscn")

func _on_connection_failed():
	status_label.text = "Falha na conexão. Tente novamente."
	host_button.disabled = false
	client_button.disabled = false
	server_option.disabled = false

