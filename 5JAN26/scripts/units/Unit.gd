# Unit.gd - Complete unit with all AFL properties
extends Node2D

class_name AFLPlayerUnit

# === EDITABLE STATS (Visible in Inspector) ===
@export_category("Unit Identity")
@export var unit_name : String = "Player"
@export var team : int = 0  # 0 = Team A, 1 = Team B
@export var player_position : String = "Midfielder"

@export_category("Core Stats")
@export_range(0, 100) var consciousness : float = 100  # 0 = unconscious
@export_range(0, 100) var stamina : float = 100
@export_range(0, 100) var speed_base : float = 50
@export_range(0, 100) var kick_accuracy : float = 50
@export_range(0, 100) var marking : float = 50
@export_range(0, 100) var leap : float = 50
@export_range(0, 100) var hands : float = 50
@export_range(0, 100) var iq : float = 50
@export_range(0, 100) var physical_build : float = 50
@export_range(0, 100) var stress : float = 0

@export_category("Derived Stats")
@export var current_stamina : float = 100
@export var current_speed : float = 50
@export var hex_position : Vector2 = Vector2.ZERO

# Movement states
enum MovementState { STANDING, WALKING, JOGGING, RUNNING, SPRINTING }
var movement_state : MovementState = MovementState.STANDING

# === REAL-TIME UPDATES ===
func _process(delta):
	if consciousness <= 0:
		# Unit is unconscious
		modulate = Color(0.5, 0.5, 0.5, 0.5)
		return
	
	# Stamina recovery/depletion
	match movement_state:
		MovementState.STANDING:
			current_stamina = min(100, current_stamina + 5.0 * delta)
		MovementState.WALKING:
			current_stamina = min(100, current_stamina + 2.0 * delta)
		MovementState.JOGGING:
			current_stamina = max(0, current_stamina - 1.0 * delta)
		MovementState.RUNNING:
			current_stamina = max(0, current_stamina - 3.0 * delta)
		MovementState.SPRINTING:
			current_stamina = max(0, current_stamina - 8.0 * delta)
	
	# Speed affected by stamina and stress
	var stamina_factor = current_stamina / 100.0
	var stress_factor = 1.0 - (stress / 200.0)  # Stress reduces speed
	current_speed = speed_base * stamina_factor * stress_factor
	
	# Visual feedback
	update_visuals()

func update_visuals():
	# Color based on stamina
	var stamina_color = Color(1, current_stamina/100, current_stamina/100)
	$Sprite2D.modulate = stamina_color
	
	# Size based on physical build
	var scale_factor = 0.5 + (physical_build / 200.0)
	$Sprite2D.scale = Vector2(scale_factor, scale_factor)

# === ACTION SYSTEM (D20 BASED) ===
func attempt_kick(target_hex, distance):
	if consciousness <= 0 or current_stamina < 10:
		return false
	
	var roll = randi() % 20 + 1  # D20
	var modifier = kick_accuracy / 10.0  # 50 kick = +5 modifier
	
	# Distance penalty
	var distance_penalty = distance * 2  # Each hex adds -2
	
	# Stress penalty
	var stress_penalty = stress / 20.0
	
	var total = roll + modifier - distance_penalty - stress_penalty
	
	current_stamina -= 15  # Kicking costs stamina
	movement_state = MovementState.STANDING  # Reset movement
	
	return total >= 10  # DC 10 for basic success

# Function to call from editor
func set_stat(stat_name, value):
	set(stat_name, value)
	update_visuals()
