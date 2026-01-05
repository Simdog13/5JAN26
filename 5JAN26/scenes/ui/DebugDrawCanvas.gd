extends Node2D

func _draw():
	if not get_parent().visible:
		return
	
	var PIXELS_PER_GRID = 32.0
	
	if MatchDirector:
		var umpire_positions = MatchDirector.umpire_positions
		var vision_range = MatchDirector.umpire_vision_range * PIXELS_PER_GRID
		
		for i in range(umpire_positions.size()):
			var umpire_pos = umpire_positions[i]
			var pixel_pos = Vector2(umpire_pos.x * PIXELS_PER_GRID, umpire_pos.y * PIXELS_PER_GRID)
			
			draw_circle(pixel_pos, vision_range, Color(1, 0, 0, 0.1))
			draw_circle(pixel_pos, 6, Color.RED)
			
			var text_pos = pixel_pos + Vector2(-4, 4)
			draw_string(ThemeDB.fallback_font, text_pos, str(i + 1), 12)
	
	if BallManager:
		var ball_pos = BallManager.get_ball_grid_position() * PIXELS_PER_GRID
		var ball_color = Color.YELLOW if BallManager.is_ball_loose() else Color.GREEN
		draw_circle(ball_pos, 8, ball_color)
		
		var ball_info = BallManager.get_possession_info()
		var ball_state = ball_info.get("state", "UNKNOWN")
		draw_string(ThemeDB.fallback_font, ball_pos + Vector2(-20, -15), ball_state, 10)
