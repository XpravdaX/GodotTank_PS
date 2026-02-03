extends RayCast3D
class_name Wheel_PS

@export var suspension_rest_dist: float = 0.3
@export var spring_strength: float = 400
@export var spring_damper: float = 15
@export var wheel_radius: float = 0.12
@export var brake_strength: float = 1.0
@export var is_left_wheel: bool = true
@export var turn_force_multiplier: float = 1.0

@onready var parent: Tank_PS = get_parent().get_parent()
@onready var wheel = get_child(0)
@export var skeletal: Skeleton3D

var previous_spring_length: float = 0.0

func _ready():
	add_exception(parent)
	if not Engine.is_editor_hint():
		determine_side()

func determine_side():
	var node_name = name.to_lower()
	if "left" in node_name or "l_" in node_name or "_l" in node_name:
		is_left_wheel = true
	elif "right" in node_name or "r_" in node_name or "_r" in node_name:
		is_left_wheel = false

func acceleration(collision_point, accel_input: float, wheel_is_left: bool, rotation_input: float):
	var accel_dir = -global_basis.z
	var point = Vector3(collision_point.x, collision_point.y + wheel_radius, collision_point.z)
	
	var state := PhysicsServer3D.body_get_direct_state(parent.get_rid())
	var tire_world_vel := state.get_velocity_at_local_position(global_position - parent.global_position)
	var forward_velocity = accel_dir.dot(tire_world_vel)
	
	if abs(accel_input) > 0.1:
		var speed_factor = max(0.0, 1.0 - abs(forward_velocity) / parent.max_speed)
		var torque = accel_input * parent.engine_power * speed_factor
		parent.apply_force(accel_dir * torque, point - parent.global_position)
	else:
		apply_braking(collision_point, forward_velocity)
	
	apply_turning(collision_point, wheel_is_left, rotation_input, forward_velocity, accel_dir, point)

func apply_turning(collision_point, wheel_is_left: bool, rotation_input: float, forward_velocity: float, accel_dir: Vector3, point: Vector3):
	if abs(rotation_input) > 0.1:
		var turn_power = parent.get_turn_power()
		var current_speed = parent.linear_velocity.length()
		
		var turn_direction = parent.get_turn_direction(wheel_is_left, rotation_input)
		
		if current_speed < parent.min_turn_speed:
			var current_angular_speed = parent.angular_velocity.length()
			
			if current_angular_speed < parent.max_turn_in_place_speed:
				var in_place_force = turn_power * turn_direction * turn_force_multiplier
				parent.apply_force(accel_dir * in_place_force, point - parent.global_position)
			else:
				var maintenance_force = turn_power * turn_direction * turn_force_multiplier * 0.3
				parent.apply_force(accel_dir * maintenance_force, point - parent.global_position)
		else:
			var is_turning_right = rotation_input > 0
			var is_external_wheel = (is_turning_right and wheel_is_left) or (not is_turning_right and not wheel_is_left)
			
			if is_external_wheel:
				var external_multiplier = 1.3
				var force = turn_power * turn_direction * external_multiplier * turn_force_multiplier
				parent.apply_force(accel_dir * force, point - parent.global_position)
			else:
				var internal_multiplier = 0.7
				
				if forward_velocity > 1.0:
					var brake_factor = clamp(forward_velocity / parent.max_speed, 0.1, 0.5)
					internal_multiplier = 0.5 - brake_factor * 0.3
				
				var force = turn_power * turn_direction * internal_multiplier * turn_force_multiplier
				parent.apply_force(accel_dir * force, point - parent.global_position)

func apply_braking(collision_point, forward_velocity: float):
	if abs(forward_velocity) > 0.5:
		var accel_dir = -global_basis.z
		var brake_power = parent.get_brake_power() * brake_strength
		var brake_force = -accel_dir * forward_velocity * brake_power * parent.mass / 10.0
		var point = Vector3(collision_point.x, collision_point.y + wheel_radius, collision_point.z)
		parent.apply_force(brake_force, point - parent.global_position)

func set_wheel_position(new_pos_y: float):
	wheel.position.y = lerp(wheel.position.y, new_pos_y, 0.6)
	var index_wheel = get_index()
	var bone = skeletal.get_bone_pose_position(index_wheel + 1)
	bone.y = wheel.position.y - 1.2
	skeletal.set_bone_pose_position(index_wheel + 1, bone)

func apply_x_force(delta:float, collision_point) -> void:
	var dir: Vector3 = global_basis.x
	var state := PhysicsServer3D.body_get_direct_state(parent.get_rid())
	var tire_world_vel := state.get_velocity_at_local_position(global_position - parent.global_position)
	var lateral_vel: float = dir.dot(tire_world_vel)
	
	var grip_multiplier = 1.0 + (parent.get_brake_power() * 0.5)
	var grip = parent.mass * 20 * grip_multiplier
	var desired_vel_change = -lateral_vel * grip
	var x_force = desired_vel_change * delta
	
	parent.apply_force(dir * x_force, collision_point - parent.global_position)

func apply_z_force(collision_point):
	var dir: Vector3 = global_basis.z
	var state := PhysicsServer3D.body_get_direct_state(parent.get_rid())
	var tire_world_vel := state.get_velocity_at_local_position(global_position - parent.global_position)
	
	var drag_multiplier = 1.0 + (parent.get_brake_power() * 0.3)
	var z_force = dir.dot(tire_world_vel) * parent.mass / 20 * drag_multiplier
	
	parent.apply_force(-dir * z_force, collision_point - parent.global_position)

func suspension(delta: float, collision_point):
	var susp_dir = global_basis.y
	var raycast_origin = global_position
	var raycast_dest = collision_point
	var distance = raycast_dest.distance_to(raycast_origin)
	
	var contact = collision_point - parent.global_position
	var spring_length = clamp(distance - wheel_radius, 0, suspension_rest_dist)
	var spring_force = spring_strength * (suspension_rest_dist - spring_length)
	var spring_velocity = (previous_spring_length - spring_length) / delta 
	
	var damper_forge = spring_damper * spring_velocity
	
	var suspension_force = basis.y * (spring_force + damper_forge)
	previous_spring_length = spring_length
	
	var point = Vector3(collision_point.x, collision_point.y + wheel_radius, collision_point.z)
	
	parent.apply_force(susp_dir + suspension_force, point - parent.global_position)
