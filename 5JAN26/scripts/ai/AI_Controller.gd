# AI_Controller.gd - Basic decision making
class_name AI_Controller

const AI_Controller = preload("res://scripts/ai/AI_Controller.gd")

static func make_decision(unit, grid, ball):
	var decisions = []
	
	# Calculate ball distance
	var ball_distance = grid.hex_distance(unit.hex_position, ball.hex_position)
	
	# Position-specific behavior
	match unit.player_position:
		"Forward":
			decisions = forward_ai(unit, ball_distance)
		"Midfielder":
			decisions = midfielder_ai(unit, ball_distance)
		"Defender":
			decisions = defender_ai(unit, ball_distance)
		_:
			decisions = ["stand"]
		
	# Choose based on IQ and stress
	var decision_score = unit.iq - unit.stress
	if decision_score > 70 and decisions.size() > 1:
		return decisions[1]  # Smarter decision
	else:
		return decisions[0]  # Basic decision
		
static func defender_ai(unit, ball_distance):
	return ["tackle", "shepherd"] # Placeholder
	
static func forward_ai(unit, ball_distance):
	if ball_distance <= 3:
		return ["kick_goal", "mark"]
	elif ball_distance <= 6:
		return ["move_toward_ball", "position_forward"]
	else:
		return ["conserve_stamina", "position_forward"]

static func midfielder_ai(unit, ball_distance):
	if ball_distance <= 2:
		return ["handball", "tackle"]
	elif ball_distance <= 4:
		return ["move_toward_ball", "shepherd"]
	else:
		return ["zone_defense", "recover_stamina"]
