# autoloads/UnitFactory.gd
# ============================================
# PURPOSE: Factory for creating, configuring, and placing game units.
# PRINCIPLE: Centralizes all unit creation logic. Knows about unit scenes,
# stats, and the grid, but NOT about UI.
# ============================================

extends Node

# Preload the unit scene to avoid runtime path lookup.
const _UNIT_SCENE = preload("res://scenes/units/UnitVisualizer.tscn")

# Configuration: Default stats for different positions.
# This can later be loaded from JSON or a database.
const _POSITION_CONFIG = {
	"Midfielder": {"speed_base": 60, "kick_accuracy": 50, "marking": 55},
	"Forward": {"speed_base": 65, "kick_accuracy": 70, "marking": 45},
	"Defender": {"speed_base": 55, "kick_accuracy": 40, "marking": 75}
}

func _ready():
	Debug.log_info("UnitFactory", "Ready.")
	# Connect to the UIManager's signals.
	# We wait a frame to ensure UIManager is loaded.
	await get_tree().process_frame
	_connect_to_ui_signals()

func _connect_to_ui_signals():
	"""Connects this factory to listen for UI requests."""
	var ui_manager = get_node_or_null("/root/UIManager")
	if ui_manager:
		ui_manager.ui_add_unit_requested.connect(_on_ui_add_unit_requested)
		Debug.log_info("UnitFactory", "Connected to UIManager signals.")
	else:
		Debug.log_error("UnitFactory", "UIManager not found. Cannot connect UI signals.")

# === PUBLIC API ===add_unit
# Other systems (like AI or debug commands) can call these directly.

func create_and_place_unit(team: int, position_type: String = "Midfielder", unit_name: String = "") -> Node2D:
	"""Main factory method. Creates a unit, configures it, and attempts to place it on the grid. Returns the created unit node if successful, null otherwise."""
	Debug.log_info("UnitFactory", "Creating unit. Team: %d, Position: %s" % [team, position_type])
	
	# 1. INSTANTIATE
	var new_unit: Node2D = _UNIT_SCENE.instantiate()
	if not new_unit:
		Debug.log_error("UnitFactory", "Failed to instantiate unit scene.")
		return null
	
	# 2. CONFIGURE STATS
	_configure_unit(new_unit, team, position_type, unit_name)
	
	# 3. PLACE ON GRID
	var placement_success = _attempt_grid_placement(new_unit)
	if not placement_success:
		Debug.log_warn("UnitFactory", "Failed to place unit on grid. Destroying instance.")
		new_unit.queue_free()
		return null
	
	# 4. NOTIFY GAME MANAGER & RETURN
	GameManager.register_new_unit(new_unit)
	Debug.log_info("UnitFactory", "Successfully created unit: '%s'" % new_unit.unit_name)
	return new_unit

# === INTERNAL METHODS ===

func _configure_unit(unit_node: Node2D, team: int, position_type: String, custom_name: String):
	"""Applies all properties and stats to a unit instance."""
	var config = _POSITION_CONFIG.get(position_type, _POSITION_CONFIG["Midfielder"])
	
	# Basic Identity
	unit_node.unit_name = custom_name if custom_name != "" else _generate_unit_name(team, position_type)
	unit_node.team = team
	unit_node.player_position = position_type
	
	# Core Stats (from configuration)
	unit_node.speed_base = config.get("speed_base", 50)
	unit_node.kick_accuracy = config.get("kick_accuracy", 50)
	unit_node.marking = config.get("marking", 50)
	
	# Derived Stats (full stamina, conscious)
	unit_node.current_stamina = unit_node.stamina
	unit_node.consciousness = 100
	
	Debug.log_debug("UnitFactory", "Configured unit '%s' with stats: %s" % [unit_node.unit_name, config])

func _attempt_grid_placement(unit_node: Node2D) -> bool:
	"""Finds the GridManager and requests placement at a VALID, EMPTY position."""
	var grid = get_tree().root.get_node_or_null("Main/AFL_Grid")
	if not grid or not grid.has_method("place_unit"):
		Debug.log_error("UnitFactory", "GridManager not found or missing 'place_unit' method.")
		return false
	
	# Determine team side: Team 0 (left), Team 1 (right)
	var team_side = unit_node.team
	var base_x = 10 if team_side == 0 else 30  # Different base X for each team
	var base_y = 10
	
	# Try a 3x3 area around the base position to find an empty spot
	for x_offset in range(-1, 2):  # -1, 0, 1
		for y_offset in range(-1, 2):  # -1, 0, 1
			var try_x = base_x + x_offset
			var try_y = base_y + y_offset
			
			Debug.log_debug("UnitFactory", "Attempting placement at grid (%d, %d) for team %d" % [try_x, try_y, team_side])
			if grid.place_unit(unit_node, try_x, try_y):
				Debug.log_info("UnitFactory", "Placed unit at (%d, %d)" % [try_x, try_y])
				return true
	
	# If all spots in the 3x3 area are occupied, log an error.
	Debug.log_error("UnitFactory", "Could not find empty placement spot for team %d near base (%d, %d)." % [team_side, base_x, base_y])
	return false

func _generate_unit_name(team: int, position: String) -> String:
	"""Generates a unique, descriptive name for a unit."""
	var team_letter = "A" if team == 0 else "B"
	# Use the GameManager's count to ensure uniqueness.
	var count = GameManager.registered_units.size() + 1
	return "%s-%s-%03d" % [team_letter, position.substr(0, 3), count]

# === UI SIGNAL HANDLER ===
func _on_ui_add_unit_requested():
	"""Called when the UI 'Add Unit' button is pressed."""
	Debug.log_info("UnitFactory", "UI requested a new unit.")
	# Default: create a midfielder for team 0.
	create_and_place_unit(0, "Midfielder")
