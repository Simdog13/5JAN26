# autoloads/Debug.gd
# ============================================
# PURPOSE: Centralized logging and debugging tools.
# Access globally via: Debug.log_info("Message")
# ============================================

extends Node

# Log levels control the verbosity of output.
enum LOG_LEVEL {ERROR, WARN, INFO, DEBUG}
@export var current_log_level: LOG_LEVEL = LOG_LEVEL.INFO

# Can be turned off to disable all logs instantly.
@export var logging_enabled: bool = true

# Color codes for better readability in the Godot output panel.
const COLORS = {
	LOG_LEVEL.ERROR: "#FF5555", # Red
	LOG_LEVEL.WARN: "#FFAA55",  # Orange
	LOG_LEVEL.INFO: "#55AAFF",  # Blue
	LOG_LEVEL.DEBUG: "#AAAAAA"  # Grey
}

static func log_error(context: String, message: String):
	_log(LOG_LEVEL.ERROR, context, message)

static func log_warn(context: String, message: String):
	_log(LOG_LEVEL.WARN, context, message)

static func log_info(context: String, message: String):
	_log(LOG_LEVEL.INFO, context, message)

static func log_debug(context: String, message: String):
	_log(LOG_LEVEL.DEBUG, context, message)

# Internal method that handles the formatting and conditional printing.
static func _log(level: int, context: String, message: String):
	# 1. Get the singleton instance.
	var debug_instance: Debug = _get_instance()
	if not debug_instance:
		return

	# 2. Check if we should print based on settings.
	if not debug_instance.logging_enabled or level > debug_instance.current_log_level:
		return

	# 3. Format the message with time, context, and color.
	var time_string = "[%s]" % Time.get_time_string_from_system()
	var formatted_message = "[%s] [%s] %s" % [time_string, context, message]
	var color = debug_instance.COLORS.get(level, "#FFFFFF")

	# 4. Print using Godot's built-in method which supports BBCode for color.
	print_rich("[color=%s]%s[/color]" % [color, formatted_message])

# Safely retrieves the autoloaded instance. Crucial for static method access.
static func _get_instance() -> Debug:
	# This is the correct pattern for a singleton in Godot 4.
	return Engine.get_main_loop().root.get_node_or_null("/root/Debug") as Debug

# === DEBUG TOOLS ===
# Example: Draw a debug point on the grid for 1 second.
static func draw_debug_point(world_position: Vector2, color: Color = Color.RED, duration: float = 1.0):
	var instance = _get_instance()
	if instance and instance.has_node("/root/Main/AFL_Grid"):
		var canvas = instance.get_node("/root/Main/AFL_Grid")
		# Use `canvas.draw_...` methods in a `draw` callback. (Implementation expanded if needed).
		Debug.log_debug("DebugDraw", "Requested point at %s" % world_position)
