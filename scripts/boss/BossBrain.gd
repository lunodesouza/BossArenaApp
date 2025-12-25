extends Node
class_name BossBrain

## Reusable boss AI "brain" (server-authoritative).
## Requires parent to provide:
## - global_position (Vector2)
## - velocity (Vector2) writable
## - stats: BossStats (Node at "Stats") with move_speed/is_rage
## - method _boss_fire(dir: Vector2) -> void
## - method _boss_get_nearest_player(from_pos: Vector2) -> Dictionary {id, pos, dist}

enum State { CHASE, BURST, RANDOM_MOVE }

@export var stop_range: float = 170.0
@export var shoot_range: float = 420.0

@export var burst_shots: int = 10
@export var burst_fire_interval: float = 0.12
@export var burst_cooldown: float = 0.6

@export var random_move_distance: float = 220.0
@export var random_move_duration: float = 0.9
@export var random_move_chance: float = 0.35

@export var strafe_enabled: bool = true
@export var strafe_angle_deg: float = 35.0

var state: State = State.CHASE

var _target_id: int = 0
var _target_pos: Vector2 = Vector2.ZERO
var _target_dist: float = INF

var _shots_left: int = 0
var _fire_timer: float = 0.0
var _state_timer: float = 0.0
var _move_goal: Vector2 = Vector2.ZERO

func _boss() -> Node2D:
	return get_parent() as Node2D

func _boss_stats() -> BossStats:
	var b := _boss()
	if b == null:
		return null
	return b.get_node_or_null("Stats") as BossStats

func _refresh_target() -> void:
	var b := _boss()
	if b == null:
		_target_id = 0
		return
	if not b.has_method("_boss_get_nearest_player"):
		_target_id = 0
		return
	var result = b.call("_boss_get_nearest_player", b.global_position)
	if result is Dictionary and result.has("id"):
		_target_id = int(result["id"])
		var pos_v = result.get("pos")
		_target_pos = pos_v if pos_v is Vector2 else Vector2.ZERO
		_target_dist = float(result.get("dist", INF))
	else:
		_target_id = 0

func _desired_speed() -> float:
	var stats := _boss_stats()
	if stats == null:
		return 80.0
	return stats.move_speed

func _can_shoot() -> bool:
	return _target_id != 0 and _target_dist <= shoot_range

func _start_burst() -> void:
	state = State.BURST
	_shots_left = max(1, burst_shots)
	_fire_timer = 0.0
	_state_timer = burst_cooldown

func _start_random_move() -> void:
	state = State.RANDOM_MOVE
	_state_timer = max(0.2, random_move_duration)
	# pick a random goal around current position, biased away/towards target a bit
	var b := _boss()
	if b == null:
		return
	var angle := randf() * TAU
	var offset := Vector2(cos(angle), sin(angle)) * random_move_distance
	_move_goal = b.global_position + offset

func _start_chase() -> void:
	state = State.CHASE

func tick(delta: float) -> void:
	# Server-authoritative only
	if not multiplayer.is_server():
		return

	var b: Node2D = _boss()
	if b == null:
		return

	_refresh_target()
	if _target_id == 0:
		b.velocity = Vector2.ZERO
		return

	var to_target: Vector2 = _target_pos - b.global_position
	var dist: float = to_target.length()
	_target_dist = dist
	var dir: Vector2 = (to_target / dist) if dist > 0.001 else Vector2.RIGHT

	# Rage speeds up shooting a bit (global modifier)
	var rage_mult := 1.0
	var stats := _boss_stats()
	if stats and stats.is_rage:
		rage_mult = 0.65

	match state:
		State.CHASE:
			if dist > stop_range:
				# Optional strafe: rotate slightly to be less linear
				if strafe_enabled:
					var ang := deg_to_rad(strafe_angle_deg)
					if randf() < 0.5:
						ang = -ang
					dir = dir.rotated(ang)
				b.velocity = dir * _desired_speed()
			else:
				b.velocity = Vector2.ZERO
				_start_burst()

		State.BURST:
			b.velocity = Vector2.ZERO
			_state_timer -= delta
			_fire_timer -= delta
			if _shots_left > 0 and _can_shoot() and _fire_timer <= 0.0:
				_fire_timer = max(0.03, burst_fire_interval * rage_mult)
				_shots_left -= 1
				if b.has_method("_boss_fire"):
					b.call("_boss_fire", dir)
			if _shots_left <= 0 and _state_timer <= 0.0:
				# After burst: sometimes do random movement, otherwise chase again
				if randf() < random_move_chance:
					_start_random_move()
				else:
					_start_chase()

		State.RANDOM_MOVE:
			_state_timer -= delta
			var to_goal: Vector2 = _move_goal - b.global_position
			var gd: float = to_goal.length()
			if gd > 8.0:
				var gdir: Vector2 = to_goal / gd
				b.velocity = gdir * _desired_speed()
			else:
				b.velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				# After random move, shoot again
				_start_burst()
