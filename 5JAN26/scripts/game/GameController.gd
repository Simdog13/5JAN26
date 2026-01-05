# GameController.gd - Controls the entire simulation
extends Node

enum GameState { STOPPED, PLAYING, PAUSED, FAST_FORWARD, REWIND }
var current_state = GameState.STOPPED
var game_speed = 1.0
var current_turn = 0

# Game recording for rewind
var game_history = []

@onready var grid = get_node("AFL_Grid")
@onready var control_panel = get_node("ControlPanel")
@onready var ball = null # We'll add this later
@onready var units = get_tree().get_nodes_in_group("units")

func _ready():
	print("=== AFL Simulator Starting ===")
	print("GameController loaded")
	
	# Check grid connection
	if grid:
		print("✓ Grid found:", grid.name)
	else:
		print("✗ ERROR: Grid not found!")

	# Check if we can find units
	var units_found = get_tree().get_nodes_in_group("units")
	print("Units in group 'units':", units_found.size())

	for unit in units_found:
		print("  - ", unit.unit_name)
		
		# Connect the Add Unit button signal to a function in this controller
	var add_unit_button = get_node("ControlPanel/AddUnitButton")
	if add_unit_button:
		add_unit_button.pressed.connect(_on_add_unit_pressed)
	else:
		print("Warning: AddUnitButton not found. Check node name and path.")
	reset_game()

func _on_add_unit_pressed():
	print("Add Unit button pressed!") # Good for debugging
	
	# 1. Load the unit scene
	var unit_scene = preload("res://scenes/units/UnitVisualizer.tscn")
	# 2. Create an instance (a new unit) from it
	var new_unit = unit_scene.instantiate()
	
	# 3. Add it as a child of the Main scene so it appears
	get_parent().add_child(new_unit)
	
	# 4. Configure the new unit
	new_unit.unit_name = "TestPlayer"
	new_unit.team = 0
	new_unit.player_position = "Midfielder"
	
	# 5. Try to place it on the grid at a specific position
	var grid_x = 20 # Example: somewhere near the center (adjust for your grid size)
	var grid_y = 10
	if grid.place_unit(new_unit, grid_x, grid_y):
		print("Successfully placed unit at grid (", grid_x, ", ", grid_y, ")")
	else:
		print("Failed to place unit.")

func _process(delta):
	match current_state:
		GameState.PLAYING, GameState.FAST_FORWARD:
			var actual_delta = delta * game_speed
			simulate_turn(actual_delta)
			if current_state == GameState.FAST_FORWARD:
				game_speed = 3.0
			else:
				game_speed = 1.0
			
		GameState.REWIND:
			rewind_step(delta)
			
		GameState.PAUSED, GameState.STOPPED:
			pass

func simulate_turn(delta):
	# Save state for rewind
	if current_turn % 5 == 0:  # Save every 5 frames
		save_game_state()
	
	# AI makes decisions
	for unit in units:
		if unit.team == current_turn % 2:  # Alternate teams
			var ai_decision = AI_Controller.make_decision(unit, grid, ball)
			execute_decision(unit, ai_decision)

	current_turn += 1

func execute_decision(unit, decision):
	print(unit.unit_name, " executes: ", decision)
	# Placeholder - will fill later
	
func load_game_state(state):
	print("Loading game state")
	# Placeholder

func save_game_state():
	var state = {
		"turn": current_turn,
		"units": [],
		"ball": ball.position
	}
	
	for unit in units:
		state.units.append({
			"position": unit.hex_position,
			"stamina": unit.current_stamina,
			"consciousness": unit.consciousness
		})
	
	game_history.append(state)

func rewind_step(delta):
	if game_history.size() > 1:
		game_history.pop_back()  # Remove current
		var prev_state = game_history[-1]
		load_game_state(prev_state)
		current_turn -= 1

# === UI CONTROL FUNCTIONS ===
func play():
	current_state = GameState.PLAYING
	game_speed = 1.0

func pause():
	current_state = GameState.PAUSED

func stop():
	current_state = GameState.STOPPED
	reset_game()

func fast_forward():
	current_state = GameState.FAST_FORWARD
	game_speed = 3.0

func rewind():
	current_state = GameState.REWIND

func reset_game():
	current_turn = 0
	game_history.clear()
	# Reset all units to starting positions
	for unit in units:
		unit.current_stamina = unit.stamina
		unit.consciousness = 100
		# Position based on team and role
		place_unit_by_position(unit)

func place_unit_by_position(unit):
	# Simple positioning logic
	var positions = {
		"Forward": Vector2(6, 0) if unit.team == 0 else Vector2(-6, 0),
		"Midfielder": Vector2(0, 0),
		"Defender": Vector2(-6, 0) if unit.team == 0 else Vector2(6, 0)
	}
	unit.hex_position = positions.get(unit.position, Vector2.ZERO)
