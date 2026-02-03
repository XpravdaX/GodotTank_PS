extends RigidBody3D
class_name Tank_PS

@export var left_wheels: Array[Wheel_PS] = []
@export var right_wheels: Array[Wheel_PS] = []
@export var engine_power: float = 12
@export var max_speed: float = 35
@export var brake_power: float = 5
@export var idle_drag: float = 2.0
@export var turn_power_multiplier: float = 0.7
@export var turn_in_place_multiplier: float = 2.0
@export var min_turn_speed: float = 0.5
@export var max_turn_speed: float = 15.0
@export var max_turn_in_place_speed: float = 2.0
@export var turn_in_place_power: float = 8.0

var accel_input: float
var rotation_input: float
var is_moving: bool = false
var last_rotation_input: float = 0.0
var target_angular_velocity: float = 0.0

func _physics_process(delta) -> void:
	tank_control(delta)
	
	limit_max_speed()
	
	limit_turn_in_place_speed(delta)
	
	if abs(accel_input) < 0.1 and linear_velocity.length() > 0.5:
		apply_drag_force(delta)
	
	for wheel_node in left_wheels:
		process_wheel(wheel_node, delta, true)
	
	for wheel_node in right_wheels:
		process_wheel(wheel_node, delta, false)

func process_wheel(wheel_node: Wheel_PS, delta: float, is_left_wheel: bool) -> void:
	wheel_node.force_raycast_update()
	if wheel_node.is_colliding():
		var collision_point = wheel_node.get_collision_point()
		wheel_node.suspension(delta, collision_point)
		wheel_node.acceleration(collision_point, accel_input, is_left_wheel, rotation_input)
		
		wheel_node.apply_z_force(collision_point)
		wheel_node.apply_x_force(delta, collision_point)
		
		wheel_node.set_wheel_position(wheel_node.to_local(collision_point).y + (1 - wheel_node.wheel_radius))

func tank_control(delta) -> void:
	accel_input = Input.get_axis("W", "S")
	rotation_input = Input.get_axis("D", "A")
	
	if abs(rotation_input) > 0.1:
		last_rotation_input = rotation_input
	
	is_moving = abs(accel_input) > 0.1 or linear_velocity.length() > 0.5
	
	var current_speed = linear_velocity.length()
	if current_speed < min_turn_speed and abs(rotation_input) > 0.1:
		target_angular_velocity = rotation_input * max_turn_in_place_speed
	else:
		target_angular_velocity = 0.0

func limit_max_speed() -> void:
	var horizontal_velocity = Vector3(linear_velocity.x, 0, linear_velocity.z)
	if horizontal_velocity.length() > max_speed:
		var limited_velocity = horizontal_velocity.normalized() * max_speed
		linear_velocity.x = limited_velocity.x
		linear_velocity.z = limited_velocity.z

func limit_turn_in_place_speed(delta: float) -> void:
	var current_speed = linear_velocity.length()
	
	if current_speed < min_turn_speed:
		var current_angular_speed = angular_velocity.length()
		
		if current_angular_speed > max_turn_in_place_speed:
			var limited_angular = angular_velocity.normalized() * max_turn_in_place_speed
			angular_velocity = limited_angular
		
		if abs(rotation_input) > 0.1 and current_angular_speed >= max_turn_in_place_speed * 0.9:
			var angular_drag = -angular_velocity.normalized() * turn_in_place_power * 0.5 * mass
			apply_torque(angular_drag * delta)

func apply_drag_force(delta: float) -> void:
	if linear_velocity.length() > 0:
		var drag_direction = -linear_velocity.normalized()
		var drag_force = drag_direction * idle_drag * mass
		apply_central_force(drag_force)
		
		var angular_drag = -angular_velocity * idle_drag * 0.5 * mass
		apply_torque(angular_drag)

func get_brake_power() -> float:
	if abs(accel_input) < 0.1 and linear_velocity.length() > 1.0:
		return brake_power
	return 0.0

func get_turn_power() -> float:
	var current_speed = linear_velocity.length()
	
	if current_speed < min_turn_speed:
		return turn_in_place_power
	
	var speed_factor = clamp((current_speed - min_turn_speed) / (max_turn_speed - min_turn_speed), 0.0, 1.0)
	var turn_factor = 1.0 - speed_factor * 0.3
	
	return engine_power * turn_power_multiplier * turn_factor

func get_turn_direction(is_left_wheel: bool, rotation_input: float) -> float:
	if rotation_input > 0:
		return 1.0 if is_left_wheel else -1.0
	elif rotation_input < 0:
		return -1.0 if is_left_wheel else 1.0
	return 0.0
