# GameController.gd - Controls the entire simulation
extends Node

enum GameState { STOPPED, PLAYING, PAUSED, FAST_FORWARD, REWIND }
var current_state = GameState.STOPPED
var game_speed = 1.0

# Game recording for rewind
var game_history = []
var current_turn = 0

@onready var units = get_tree().get_nodes_in_group("units")
@onready var ball = null
@onready var grid = get_parent().get_node("AFL_Grid")

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
	reset_game()

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
