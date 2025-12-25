extends Control

@onready var name_input: LineEdit = $VBoxContainer/NameInput
@onready var confirm_button: Button = $VBoxContainer/ConfirmButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

func _ready():
	# Carregar nome salvo se existir
	if PlayerData.has_set_name:
		name_input.text = PlayerData.player_name
	
	# Sinais de UI já estão conectados na cena (.tscn)
	
	# Focar no input
	name_input.grab_focus()
	
	# Selecionar texto se já existir
	if not name_input.text.is_empty():
		name_input.select_all()

func _on_name_submitted(_text: String):
	_on_confirm_pressed()

func _on_confirm_pressed():
	var player_name_input = name_input.text.strip_edges()
	
	if player_name_input.is_empty():
		status_label.text = "Por favor, insira um nome!"
		status_label.modulate = Color.RED
		return
	
	if player_name_input.length() < 2:
		status_label.text = "Nome muito curto! (mínimo 2 caracteres)"
		status_label.modulate = Color.RED
		return
	
	if player_name_input.length() > 20:
		status_label.text = "Nome muito longo! (máximo 20 caracteres)"
		status_label.modulate = Color.RED
		return
	
	# Salvar nome
	if PlayerData.set_player_name(player_name_input):
		# Ir para o menu principal
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	else:
		status_label.text = "Erro ao salvar nome!"
		status_label.modulate = Color.RED
