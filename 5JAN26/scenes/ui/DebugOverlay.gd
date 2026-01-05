# scripts/ui/DebugOverlay.gd
extends CanvasLayer

@onready var draw_canvas = $DrawCanvas

func _ready():
	# Start hidden, toggle with F3 key
	visible = false
	Debug.log_info("DebugOverlay", "Debug overlay ready. Press F3 to toggle.")

func _input(event):
	# Toggle visibility with F3 key
	if event.is_action_pressed("toggle_debug"):
		visible = !visible
		Debug.log_info("DebugOverlay", "Debug overlay: %s" % ("VISIBLE" if visible else "HIDDEN"))
		# Force redraw when made visible
		if visible:
			draw_canvas.queue_redraw()

func _process(_delta):
	# Continuously redraw while visible (for moving umpires)
	if visible:
		draw_canvas.queue_redraw()

# Note: All drawing happens in the DrawCanvas node's _draw() function
