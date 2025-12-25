extends CanvasLayer

@export var message: String = "Desconectado do servidor"
@export var return_scene: String = "res://scenes/Lobby.tscn"

@onready var label: Label = $Panel/Label

func _ready() -> void:
	layer = 100
	visible = false
	if label:
		label.text = message + "\n\nClique ou pressione qualquer tecla para voltar"

func show_disconnect(custom_message: String = "") -> void:
	if not custom_message.is_empty():
		message = custom_message
	if label:
		label.text = message + "\n\nClique ou pressione qualquer tecla para voltar"
	visible = true

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var ok := false
	if event is InputEventKey and event.pressed:
		ok = true
	if event is InputEventMouseButton and event.pressed:
		ok = true
	if not ok:
		return

	# Local cleanup + go back
	if NetworkManager:
		NetworkManager.disconnect_from_server()
	get_tree().change_scene_to_file(return_scene)


