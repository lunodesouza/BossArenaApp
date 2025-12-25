extends Resource
class_name PlayerStats

@export var strength: int = 1
@export var agility: int = 1
@export var vitality: int = 1
@export var physical_resistance: int = 0
@export var magic_resistance: int = 0

func max_hp(level: int) -> int:
	return 50 + vitality * 10 + level * 5

func attack_power(level: int) -> int:
	return strength * 2 + level

func move_speed_bonus() -> float:
	# If you later want speed scaling, keep it here.
	return 0.0


