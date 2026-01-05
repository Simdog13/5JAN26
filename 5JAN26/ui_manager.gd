# autoloads/UIManager.gd
# ============================================
# PURPOSE: Connects UI elements to game logic. Handles all UI signals.
# PRINCIPLE: This is a "dumb" router. It knows about UI nodes but NOT about game logic.
# ============================================

extends Node

# Reference to the main UI panel node. Set during initialization.
var control_panel: Control = null

# Signal emitted when a UI action occurs. Other systems (like GameManager) listen to these.
signal ui_add_unit_requested
signal ui_simulation_control_requested(action) # action: "play", "pause", "stop"

func _ready():
	Debug.log_info("UIManager", "Ready. Setting up UI connections...")
	
	# Wait for the ControlPanel node itself to be ready and in the tree
	await get_tree().process_frame
	
	# Get the ControlPanel from the Main scene
	var main_scene = get_tree().root.get_node_or_null("Main")
	if not main_scene:
		Debug.log_error("UIManager", "Main scene not found.")
		return
	
	control_panel = main_scene.get_node_or_null("ControlPanel")
	if not control_panel:
		Debug.log_error("UIManager", "ControlPanel node not found.")
		return
	
	# Wait one more frame to ensure ControlPanel's children (HBoxContainer, Buttons) are ready
	await get_tree().process_frame
	
	# Now connect the buttons
	initialize_ui_connections()

	# Connect to MatchDirector signals for UI updates
	await get_tree().process_frame
	var match_director = get_node_or_null("/root/MatchDirector")
	if match_director:
		match_director.match_state_changed.connect(_on_match_state_changed)
		match_director.score_updated.connect(_on_score_updated)
		match_director.quarter_updated.connect(_on_quarter_updated)

func _on_match_state_changed(new_state):
	var status_label = get_node_or_null("ControlPanel/MatchStatusLabel")
	if status_label:
		var state_name = MatchDirector.MatchState.keys()[new_state].replace("_", " ").title()
		status_label.text = "Match: %s" % state_name

func _on_score_updated(team_0_score, team_1_score):
	var status_label = get_node_or_null("ControlPanel/MatchStatusLabel")
	if status_label:
		# Update or add a score label
		pass # You can implement a proper scoreboard here

func _on_quarter_updated(current_quarter, time_remaining):
	var status_label = get_node_or_null("ControlPanel/MatchStatusLabel")
	if status_label:
		var minutes = int(time_remaining) / 60
		var seconds = int(time_remaining) % 60
		status_label.text = "Q%d - %02d:%02d" % [current_quarter, minutes, seconds]

func initialize_ui_connections():
	"""Finds the ControlPanel in the scene and connects its buttons."""
	var main_scene = get_tree().root.get_node_or_null("Main")
	if not main_scene:
		Debug.log_error("UIManager", "Main scene not found. Cannot connect UI.")
		return

	control_panel = main_scene.get_node_or_null("ControlPanel")
	if not control_panel:
		Debug.log_error("UIManager", "ControlPanel node not found in Main scene.")
		return

	Debug.log_info("UIManager", "ControlPanel found. Connecting buttons...")
	_connect_button("AddUnitButton", _on_add_unit_pressed)
	_connect_button("PlayButton", _on_play_pressed)
	_connect_button("PauseButton", _on_pause_pressed)
	_connect_button("StopButton", _on_stop_pressed)
	_connect_button("ResetButton", _on_stop_pressed) # Reset currently same as Stop
	_connect_button("StartMatchButton", _on_start_match_pressed)

func _connect_button(button_name: String, callable: Callable):
	"""Helper to safely connect a button from the HBoxContainer."""
	if not control_panel:
		Debug.log_warn("UIManager", "Cannot connect button: ControlPanel reference is null.")
		return

	var button_path = "HBoxContainer/%s" % button_name
	var button: Button = control_panel.get_node_or_null(button_path)
	
	if button:
		# Disconnect first to prevent duplicate connections
		if button.pressed.is_connected(callable):
			button.pressed.disconnect(callable)
		
		button.pressed.connect(callable)
		Debug.log_debug("UIManager", "✓ Connected button: %s" % button_name)
		
		# Optional: Clear any previous configuration warning
		button.set("_configuration_warning", "")
	else:
		Debug.log_error("UIManager", "✗ Button not found at path: %s" % button_path)
		# This helps you debug in the editor - will show a warning icon on ControlPanel
		control_panel.set("_configuration_warning", "Missing button: %s" % button_name)

# === UI SIGNAL HANDLERS ===
# These handlers are minimal: they only emit semantic signals.
func _on_add_unit_pressed():
	Debug.log_info("UIManager", "'Add Unit' button pressed.")
	emit_signal("ui_add_unit_requested")

func _on_play_pressed():
	Debug.log_info("UIManager", "'Play' button pressed.")
	emit_signal("ui_simulation_control_requested", "play")

func _on_pause_pressed():
	Debug.log_info("UIManager", "'Pause' button pressed.")
	emit_signal("ui_simulation_control_requested", "pause")

func _on_stop_pressed():
	Debug.log_info("UIManager", "'Stop/Reset' button pressed.")
	emit_signal("ui_simulation_control_requested", "stop")

func _on_start_match_pressed():
	Debug.log_info("UIManager", "'Start Match' button pressed.")
	# Call the MatchDirector to begin the full match
	MatchDirector.start_match()
