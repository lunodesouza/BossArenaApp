extends Node
class_name BossStats

@export var boss_name: String = "Demo Boss"
@export var level: int = 3
@export var xp_reward: int = 120

@export var max_hp: int = 300
var hp: int = 300

@export var damage: int = 12
@export var crit_chance: float = 0.15
@export var crit_mult: float = 1.75

@export var move_speed: float = 90.0
var is_rage: bool = false

var last_attacker_id: int = 0

signal died(killer_id: int)

@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

func _ready() -> void:
	# Server initializes HP; clients will receive via synchronizer if you add one later.
	# Boss stats are always owned by the server (peer 1).
	set_multiplayer_authority(1)
	if synchronizer:
		synchronizer.set_multiplayer_authority(1)
	if multiplayer.is_server():
		hp = max_hp

func apply_damage(amount: int, attacker_id: int) -> void:
	if not multiplayer.is_server():
		return
	if amount <= 0:
		return
	if hp <= 0:
		return

	last_attacker_id = attacker_id
	hp = max(hp - amount, 0)

	if not is_rage and hp > 0 and float(hp) / float(max_hp) <= 0.35:
		is_rage = true
		# Simple rage buffs
		move_speed *= 1.35
		damage = int(round(damage * 1.35))
		crit_chance = min(0.5, crit_chance + 0.15)

	if hp <= 0:
		died.emit(last_attacker_id)

func roll_damage() -> int:
	var d := damage
	if randf() < crit_chance:
		d = int(round(float(d) * crit_mult))
	return d


