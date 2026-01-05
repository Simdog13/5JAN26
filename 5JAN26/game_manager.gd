# autoloads/GameManager.gd
# ============================================
# PURPOSE: Central authority for game state and simulation flow.
# PRINCIPLE: This is the "brain" of the simulation. It manages state,
#            coordinates systems, and provides a clean API for all other code.
# IMPORTANT: This script is an Autoload singleton. Access it globally as:
#            `GameManager.function_name()` from any other script.
# ============================================

extends Node

# === SIGNALS ===
# Emit these to allow other systems to react to game events without direct coupling.
# Other scripts connect to these like: `GameManager.simulation_state_changed.connect(my_function)`

# Emitted when the main simulation state (Playing, Paused, etc.) changes.
# Parameter: The new SimState enum value.
signal simulation_state_changed(new_state)

# Emitted when a new unit is successfully registered with the game.
# Parameter: The unit node (AFLPlayerUnit) that was registered.
signal unit_registered(unit_node)

# Emitted when a full game reset is completed.
signal game_reset_completed

# Emitted each time the simulation advances by one turn.
# Parameter: The new current turn number.
signal turn_advanced(new_turn_number)

# === ENUMERATIONS (Data Types) ===

# Defines the possible high-level states of the simulation.
enum SimState {
	STOPPED,    # No simulation running, fresh state.
	PLAYING,    # Simulation is actively running at normal speed.
	PAUSED,     # Simulation is halted but can be resumed.
	FAST_FORWARD # Simulation is running at an increased speed.
}

# Defines the specific AFL actions a unit can perform during its turn.
# Add or remove actions here as you develop the game mechanics.
enum AFL_Action {
	MOVE,       # Move to an adjacent grid square.
	KICK,       # Kick the ball.
	HANDBALL,   # Handpass to a nearby unit.
	MARK,       # Attempt to catch the ball.
	TACKLE,     # Attempt to dispossess an opponent.
	STAND       # Do nothing; recover stamina.
}

# === PUBLIC & MANAGED PROPERTIES ===
# These variables hold the core state of the game. They often use 'setters' to automatically
# trigger side effects (like emitting signals) when their values change.

# The current simulation state. Use the provided API functions (play, pause, stop)
# to change this safely.
var current_state: SimState = SimState.STOPPED:
	set(value):
		# This 'setter' function runs automatically every time 'current_state' is assigned a new value.
		if current_state != value:
			var old_state = current_state
			current_state = value
			# Emit a signal so other systems (like the UI) can react to the state change.
			simulation_state_changed.emit(current_state)
			# Log the change for debugging.
			Debug.log_info("GameManager", "State changed: %s -> %s" %
				[SimState.keys()[old_state], SimState.keys()[current_state]])

# Simulation speed multiplier. 1.0 = real-time. Used in `_process(delta)`.
var game_speed: float = 1.0

# The current turn number in the simulation. Increments as the simulation advances.
var current_turn: int = 0:
	set(value):
		if current_turn != value:
			current_turn = value
			# Notify any system that cares about turn progression.
			turn_advanced.emit(current_turn)
			# Log every 10th turn to avoid spamming the output.
			if current_turn % 10 == 0:
				Debug.log_debug("GameManager", "Turn advanced to: %d" % current_turn)

# Array holding references to all active units in the game.
# The GameManager is the sole authority for adding/removing units.
var registered_units: Array = []

# === INITIALIZATION ===

func _ready():
	"""Called automatically when the GameManager autoload is loaded by Godot."""
	Debug.log_info("GameManager", "Core manager initializing...")
	await get_tree().process_frame
	
	# Wait for MatchDirector to be ready if starting match immediately
	if MatchDirector.current_state != MatchDirector.MatchState.PRE_MATCH:
		await get_tree().process_frame

		# CONNECT: Link to the UIManager to receive button press events from the UI.
	_connect_to_ui_signals()

		# RESET: Put the simulation into a clean, known starting state.
	reset_simulation()

	Debug.log_info("GameManager", "Initialization complete. Awaiting commands.")

# === PUBLIC API - SIMULATION CONTROL ===
# These functions are the primary, safe way for other systems to interact with the game state.

func request_simulation_start() -> void:
	"""Request to start or resume the simulation. Called by UI or other systems."""
	Debug.log_info("GameManager", "Request received: START simulation.")

	# Validate: Can only start from STOPPED or PAUSED states.
	if current_state == SimState.STOPPED or current_state == SimState.PAUSED:
		current_state = SimState.PLAYING
		Debug.log_info("GameManager", "Simulation is now RUNNING.")
	else:
		# Log a warning if the request is invalid (e.g., trying to start while already playing).
		Debug.log_warn("GameManager",
			"Cannot start simulation from current state: %s" % SimState.keys()[current_state])

func request_simulation_pause() -> void:
	"""Request to pause the simulation."""
	Debug.log_info("GameManager", "Request received: PAUSE simulation.")

	# Validate: Can only pause from PLAYING or FAST_FORWARD states.
	if current_state == SimState.PLAYING or current_state == SimState.FAST_FORWARD:
		current_state = SimState.PAUSED
		Debug.log_info("GameManager", "Simulation is now PAUSED.")
	else:
		Debug.log_warn("GameManager",
			"Cannot pause simulation from current state: %s" % SimState.keys()[current_state])

func request_simulation_stop() -> void:
	"""Request to stop the simulation and reset all data."""
	Debug.log_info("GameManager", "Request received: STOP simulation.")
	# The 'STOPPED' state is set automatically by its setter, which will log the change.
	current_state = SimState.STOPPED
	# Perform a full reset to clear units, turn count, etc.
	reset_simulation()

func request_fast_forward(enable: bool) -> void:
	"""Request to enable or disable fast-forward mode."""
	if enable and current_state == SimState.PLAYING:
		current_state = SimState.FAST_FORWARD
		game_speed = 3.0 # Example multiplier
		Debug.log_info("GameManager", "Fast-forward ENABLED (speed: %dx)." % game_speed)
	elif not enable and current_state == SimState.FAST_FORWARD:
		current_state = SimState.PLAYING
		game_speed = 1.0
		Debug.log_info("GameManager", "Fast-forward DISABLED.")

# === PUBLIC API - UNIT MANAGEMENT ===

func register_new_unit(unit_node: Node) -> bool:
	"""
	Register a fully-created unit with the game.
	This should be called by the UnitFactory after a unit is instantiated and configured.

	Parameters:
		unit_node (Node): The unit node (AFLPlayerUnit) to register.

	Returns:
		bool: True if registration was successful, False if it failed.
	"""
	Debug.log_info("GameManager", "Attempting to register unit: %s" % unit_node.name)

	# 1. VALIDATE THE REQUEST
	# Prevent adding units while the simulation is actively running.
	if current_state == SimState.PLAYING or current_state == SimState.FAST_FORWARD:
		Debug.log_warn("GameManager", "Cannot register units while simulation is running.")
		return false

	# Ensure the unit node is valid and has not been deleted.
	if not is_instance_valid(unit_node):
		Debug.log_error("GameManager", "Cannot register invalid or freed unit node.")
		return false

	# Check if this unit is already in our registry to avoid duplicates.
	if unit_node in registered_units:
		Debug.log_warn("GameManager", "Unit '%s' is already registered." % unit_node.name)
		return true  # Already registered, so treat as a success.

	# 2. REGISTER THE UNIT
	registered_units.append(unit_node)
	Debug.log_info("GameManager", "Unit '%s' successfully registered. Total units: %d" %
		[unit_node.unit_name, registered_units.size()])

	# 3. NOTIFY OTHER SYSTEMS
	unit_registered.emit(unit_node)
	return true

# === CORE SIMULATION LOOP ===

func _process(delta: float):
	"""
	Main game loop. Called automatically every frame by Godot.
	`delta` is the time in seconds since the last frame.

	This function checks the current simulation state and advances the game logic
	when the state is PLAYING or FAST_FORWARD.
	"""
	match current_state:
		SimState.PLAYING, SimState.FAST_FORWARD:
			# Simulation is active. Advance the game logic.
			# `delta * game_speed` adjusts for the fast-forward multiplier.
			_advance_simulation(delta * game_speed)

		SimState.PAUSED, SimState.STOPPED:
			# Simulation is paused or stopped. Do nothing this frame.
			pass

# === TURN PROCESSING LOGIC ===

func _advance_simulation(delta_time: float):
	"""
	Advances the simulation by processing one logical turn.
	This is where the core AFL game logic is driven forward.

	Parameters:
		delta_time (float): The scaled time passed since the last frame.
	"""
	# TODO: Replace this with actual AFL turn logic based on time or ticks.
	# For now, we increment the turn counter as a simple placeholder.
	# In a complete system, you might have a fixed 'turn duration' or an action point system.
	current_turn += 1

	# Process AI decisions and actions for each registered unit.
	for unit in registered_units:
		_process_unit_turn(unit, delta_time)

	# Optional: Periodically save game state for potential rewind functionality.
	if current_turn % 5 == 0: # Save every 5th turn.
		_save_simulation_state()

func _process_unit_turn(unit: Node, delta_time: float):
	"""
	Process a single unit's turn. This decides and executes what the unit does.

	Parameters:
		unit (Node): The AFLPlayerUnit node to process.
		delta_time (float): The scaled time passed.
	"""
	# 1. Validate the unit is still active and usable.
	if not is_instance_valid(unit):
		return

	# 2. Choose an action for this unit based on its state, position, and AI.
	var chosen_action = _choose_unit_action(unit)

	# 3. Execute the chosen AFL action.
	match chosen_action:
		AFL_Action.MOVE:
			_execute_move_action(unit)
		AFL_Action.KICK:
			_execute_kick_action(unit)
		AFL_Action.HANDBALL:
			_execute_handball_action(unit)
		AFL_Action.MARK:
			_execute_mark_action(unit)
		AFL_Action.TACKLE:
			_execute_tackle_action(unit)
		AFL_Action.STAND:
			_execute_stand_action(unit)
		_:
			Debug.log_warn("GameManager", "Unit %s chose an unknown action." % unit.unit_name)

	# 4. Update the unit's state (e.g., stamina) based on the action taken.
	_unit_stamina_update(unit, chosen_action)

func _choose_unit_action(unit: Node) -> AFL_Action:
	"""
	Simple AI to choose an action for a unit. This is a placeholder.
	Replace this with sophisticated AFL decision logic (based on position, ball, teammates).

	Parameters:
		unit (Node): The unit deciding on an action.

	Returns:
		AFL_Action: The chosen action enum.
	"""
	# This is a very basic random selector.
	# TODO: Implement proper AFL AI here (e.g., forwards try to score, defenders tackle).
	var roll = randf() # Random number between 0.0 and 1.0

	if roll < 0.6:       # 60% chance to move.
		return AFL_Action.MOVE
	elif roll < 0.8:     # 20% chance to kick (80% - 60%).
		return AFL_Action.KICK
	else:                # 20% chance to stand.
		return AFL_Action.STAND

# === AFL ACTION EXECUTION FUNCTIONS ===
# These functions contain the logic for each specific AFL action.

func _execute_move_action(unit: Node):
	"""Move the unit to a random adjacent grid cell."""
	Debug.log_debug("GameManager", "Unit %s attempts to move." % unit.unit_name)

	# Get the unit's current grid position (stored in the unit's 'hex_position').
	var current_pos = unit.hex_position

	# Define possible movement directions: Right, Left, Down, Up.
	var possible_moves = [
		Vector2(current_pos.x + 1, current_pos.y),     # Right
		Vector2(current_pos.x - 1, current_pos.y),     # Left
		Vector2(current_pos.x, current_pos.y + 1),     # Down
		Vector2(current_pos.x, current_pos.y - 1),     # Up
	]

	# Try to move to each possible new position, in order.
	for move_pos in possible_moves:
		# Get a reference to the grid in the main scene.
		var grid = get_tree().root.get_node_or_null("Main/AFL_Grid")
		# Check if the grid exists and has the method we need.
		if grid and grid.has_method("place_unit"):
			# The 'place_unit' method handles collision checking and actual movement.
			# If successful, it updates the unit's visual position and its 'hex_position'.
			if grid.place_unit(unit, int(move_pos.x), int(move_pos.y)):
				Debug.log_info("GameManager", "Unit %s moved to %s." % [unit.unit_name, move_pos])
				return # Exit after the first successful move.

	# If the loop finishes without returning, all moves were blocked.
	Debug.log_debug("GameManager", "Unit %s could not move (all adjacent cells blocked)." % unit.unit_name)

func _execute_kick_action(unit: Node):
	"""The unit attempts a kick. Success is based on its 'kick_accuracy' stat."""
	Debug.log_info("GameManager", "Unit %s attempts a kick." % unit.unit_name)

	# Get the unit's kicking skill, defaulting to 50 if the property doesn't exist.
	var kick_skill = unit.kick_accuracy if "kick_accuracy" in unit else 50
	# Convert the skill (0-100) into a success probability (0.0 to 1.0).
	var success_chance = kick_skill / 100.0

	# Determine success with a random roll.
	if randf() < success_chance:
		Debug.log_info("GameManager", "Unit %s SUCCESSFULLY kicks the ball!" % unit.unit_name)
		# TODO: Implement ball physics/trajectory, scoring logic, or pass targeting here.
	else:
		Debug.log_info("GameManager", "Unit %s shanks the kick." % unit.unit_name)
		# TODO: Implement outcomes for a missed kick (turnover, out of bounds).

func _execute_handball_action(unit: Node):
	"""Placeholder: The unit attempts a handpass."""
	Debug.log_info("GameManager", "Unit %s attempts a handball." % unit.unit_name)
	# TODO: Implement handball logic - a quick, short pass to a nearby teammate.
	# This should be more accurate but shorter range than a kick.

func _execute_mark_action(unit: Node):
	"""Placeholder: The unit attempts to mark (catch) the ball."""
	Debug.log_info("GameManager", "Unit %s goes for a mark!" % unit.unit_name)
	# TODO: Implement mark contest logic. Success should be based on the unit's
	# 'marking' and 'leap' stats versus an opponent's.

func _execute_tackle_action(unit: Node):
	# ... tackle logic ...
	# Check for high tackle
	if randf() < 0.3: # 30% chance of illegal tackle
		if MatchDirector.check_for_infraction(unit, "HIGH_TACKLE"):
			return # Free kick awarded, tackle fails

func _execute_stand_action(unit: Node):
	"""The unit stands still, recovering stamina."""
	Debug.log_debug("GameManager", "Unit %s stands still." % unit.unit_name)
	# Standing is a rest action. Its stamina recovery is handled in '_unit_stamina_update'.

# === SUPPORTING SYSTEMS ===

func _unit_stamina_update(unit: Node, action: AFL_Action):
	"""
	Updates a unit's stamina based on the action it just performed.
	This is a core resource management system for your AFL simulator.

	Parameters:
		unit (Node): The AFLPlayerUnit whose stamina will change.
		action (AFL_Action): The action enum that was just performed.
	"""
	# Safety check: Ensure the unit has the 'current_stamina' property.
	if not "current_stamina" in unit:
		return

	# Define how much stamina each action costs (negative) or recovers (positive).
	var stamina_cost = {
		AFL_Action.MOVE: 15,      # Moving is tiring.
		AFL_Action.KICK: 25,      # Kicking requires significant effort.
		AFL_Action.HANDBALL: 10,  # Handballing is less strenuous than a kick.
		AFL_Action.MARK: 20,      # Jumping and contesting a mark is demanding.
		AFL_Action.TACKLE: 30,    # Tackling is the most physically draining action.
		AFL_Action.STAND: -5      # Negative cost means RESTING and recovering stamina.
	}

	# Get the cost for this action. Default to 10 if the action isn't in the dictionary.
	var cost = stamina_cost.get(action, 10)

	# Apply the cost: subtract it from current stamina, then clamp between 0 and 100.
	unit.current_stamina = clamp(unit.current_stamina - cost, 0, 100)

	# Log a warning if the unit has become exhausted.
	if unit.current_stamina <= 0:
		Debug.log_warn("GameManager", "Unit %s is EXHAUSTED!" % unit.unit_name)

func _connect_to_ui_signals():
	"""
	Connects this GameManager to listen for control requests from the UIManager.
	This function creates the vital link between the user interface and the game logic.
	"""
	# Get a reference to the UIManager autoload singleton.
	var ui_manager = get_node_or_null("/root/UIManager")

	if ui_manager:
		# Connect the UIManager's 'ui_simulation_control_requested' signal to our handler.
		ui_manager.ui_simulation_control_requested.connect(_on_ui_simulation_control_requested)
		Debug.log_info("GameManager", "Connected to UIManager control signals.")
	else:
		# This error is critical. Without this connection, the Play/Pause/Stop buttons won't work.
		Debug.log_error("GameManager", "UIManager not found. UI controls will not work.")

func _on_ui_simulation_control_requested(action: String):
	"""
	The signal handler for UI control requests. This is the bridge between a button
	press in the UI and the actual game logic.

	Parameters:
		action (String): The control command sent by the UIManager ("play", "pause", "stop").
	"""
	Debug.log_info("GameManager", "UI control request received: '%s'" % action)

	# Translate the string command from the UI into a call to our public API functions.
	match action:
		"play":
			request_simulation_start()
		"pause":
			request_simulation_pause()
		"stop":
			request_simulation_stop()
		# You could add more commands here later, like "fast_forward" or "step_turn".
		_:
			Debug.log_warn("GameManager", "Unknown UI action requested: %s" % action)

# === RESET & DIAGNOSTICS ===

func reset_simulation():
	"""
	Resets all simulation data to a clean, initial state.
	Called when starting a new game or after pressing Stop.
	"""
	Debug.log_info("GameManager", "Performing full simulation reset.")

	# 1. Reset core simulation variables.
	current_turn = 0
	game_speed = 1.0

	# 2. Clear the unit registry.
	# Count units before clearing for the log message.
	var unit_count = registered_units.size()
	registered_units.clear()

	Debug.log_info("GameManager", "Reset complete. Cleared %d unit(s)." % unit_count)

	# 3. Notify other systems that a reset has happened.
	#    (e.g., a future visual effect or UI could listen to this).
	game_reset_completed.emit()

func _save_simulation_state():
	"""
	Placeholder: Saves the current game state.
	This is for implementing future features like 'Rewind' or 'Save/Load'.
	"""
	# TODO: Implement proper state serialization for rewind/save functionality.
	# For now, it just logs for debugging.
	Debug.log_debug("GameManager", "Game state saved for turn %d." % current_turn)

func get_diagnostics() -> Dictionary:
	"""
	Captures a complete snapshot of the current game state.
	Excellent for debugging, in-game consoles, or saving analytics.

	Returns:
		Dictionary: A structured report of all key simulation data.
	"""
	return {
		"state": SimState.keys()[current_state],
		"turn": current_turn,
		"speed": game_speed,
		"unit_count": registered_units.size(),
		# Creates a list of unit names, handling invalid units safely.
		"unit_names": registered_units.map(
			func(u): return u.unit_name if is_instance_valid(u) else "<invalid>"
		)
	}

func print_diagnostics():
	"""
	Prints the current game diagnostics to the debug output in a readable format.
	Call this from the Godot debug console or a hotkey for instant insights.
	"""
	var diag = get_diagnostics()
	Debug.log_info("GameManager", "=== CURRENT GAME DIAGNOSTICS ===")
	# Iterate through the diagnostic dictionary and print each key-value pair.
	for key in diag:
		Debug.log_info("GameManager", "  %s: %s" % [key, diag[key]])
