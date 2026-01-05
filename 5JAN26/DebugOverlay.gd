# scripts/ui/DebugOverlay.gd
extends CanvasLayer

func _ready():
	visible = false  # Hide by default, toggle with key

func _input(event):
	if event.is_action_pressed("toggle_debug"):
		visible = !visible

func _draw():
	if not visible:
		return
	
	# Draw umpire vision circles
	var umpire_positions = MatchDirector.umpire_positions
	var vision_range = MatchDirector.umpire_vision_range * 16  # Convert to pixels
	
	for umpire_pos in umpire_positions:
		var pixel_pos = Vector2(umpire_pos.x * 16, umpire_pos.y * 16)
		draw_circle(pixel_pos, vision_range, Color(1, 0, 0, 0.1))
		draw_circle(pixel_pos, 4, Color.RED)
