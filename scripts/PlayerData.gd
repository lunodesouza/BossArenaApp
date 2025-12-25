extends Node

## Gerenciador de dados do jogador (nome, preferências, etc)

const CONFIG_FILE = "user://player_data.cfg"

var player_name: String = "Jogador"
var has_set_name: bool = false

func _ready():
	load_player_data()

func save_player_data():
	var config = ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.set_value("player", "has_set_name", has_set_name)
	config.save(CONFIG_FILE)

func load_player_data():
	var config = ConfigFile.new()
	var err = config.load(CONFIG_FILE)
	if err != OK:
		# Arquivo não existe, usar valores padrão
		return
	
	player_name = config.get_value("player", "name", "Jogador")
	has_set_name = config.get_value("player", "has_set_name", false)

func set_player_name(player_name_input: String):
	if player_name_input.strip_edges().is_empty():
		return false
	
	player_name = player_name_input.strip_edges().substr(0, 20)  # Limitar a 20 caracteres
	has_set_name = true
	save_player_data()
	return true

func get_player_name() -> String:
	return player_name
