# autoloads/BallManager.gd
# ============================================
# PURPOSE: Central authority for the ball's state, physics, and possession.
# PRINCIPLE: The ball is a first-class game entity with complex behavior.
# ACCESS: Global singleton via `BallManager`.
# ============================================

extends Node

# === SIGNALS ===
# The ball's state changes are critical for UI, AI, and game flow.
signal ball_state_changed(new_state, details)  # e.g., ("LOOSE", {})
signal ball_position_updated(grid_position)    # For visual updates and AI queries.
signal possession_changed(unit_node, team, quality) # Who has it and how well.
signal ball_entered_scoring_area(area_name)    # "GoalSquare", "BehindPost", "OutOfBounds"

# === BALL STATE ENUMS ===
# These define every possible state the ball can be in.
enum BallState {
	WITH_UMPIRE,        # At centre bounce or after a goal.
	LOOSE_GROUND,       # On the ground, free for anyone.
	LOOSE_AIR,          # In the air from a kick/handball.
	HELD_CLEAN,         # Firmly in a player's possession.
	HELD_CONTESTED,     # In a pack, being fought for.
	OUT_OF_BOUNDS,      # Over the boundary line.
	DEAD_BALL           # Play has stopped.
}

enum PossessionType {
	CLEAN,      # Perfect control.
	AWKWARD,    # Difficult pickup or mark.
	JUGGLED,    # Being knocked around in a contest.
	POOR        # Slippery, about to be dropped.
}

# === CORE BALL PROPERTIES ===
# These are the main variables describing the ball at any moment.
var current_state: BallState = BallState.WITH_UMPIRE
var current_possession_type: PossessionType = PossessionType.CLEAN

# Where the ball is in the game world.
var grid_position: Vector2 = Vector2.ZERO
# Who currently has control of it. `null` if loose or with umpire.
var possessing_unit: Node = null
var possessing_team: int = -1 # -1 for no team, 0/1 for teams.

# Physical properties affecting its movement.
var velocity: Vector2 = Vector2.ZERO
var rotation: float = 0.0 # Affects bounce angles.
var moisture_factor: float = 0.0 # 0.0 (dry) to 1.0 (soggy). Affects grip and bounce.

# === ENVIRONMENTAL & GAME SYSTEMS ===
# These external factors influence ball physics and unit decisions.

# WEATHER SYSTEM - Affects ball handling and movement.
var wind_speed: float = 0.0 # 0.0 (calm) to 1.0 (gale force)
var wind_direction: Vector2 = Vector2.RIGHT # Normalized vector
var humidity: float = 0.5 # 0.0 (dry) to 1.0 (soaking). Affects moisture_factor.

# GAME MOMENTUM & CROWD - Abstract "pressure" affecting performance.
var momentum_factor: float = 0.0 # -1.0 (all momentum with opposition) to +1.0 (all momentum with us)
var crowd_noise_level: float = 0.5 # 0.0 (silent) to 1.0 (deafening). Affects unit stress.

# FIELD ZONES - For positioning logic (Forward, Centre, Back).
# Defined as grid coordinate ranges. Adjust based on your grid size (40x20).
var _field_zones = {
	"DEFENSIVE": {"x_range": [0, 13], "team": 0},   # Team 0's backline
	"CENTRE": {"x_range": [14, 26]},                # Midfield (neutral)
	"FORWARD": {"x_range": [27, 40], "team": 0},    # Team 0's forward line
}
# Note: For Team 1, these zones are mirrored. Logic handled in `get_zone_for_position`.

# === INITIALIZATION ===
func _ready():
	Debug.log_info("BallManager", "Initializing ball systems...")
	reset_ball()
	# Start with a random, gentle breeze.
	_update_weather(randf_range(0.0, 0.3), Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized())
	Debug.log_info("BallManager", "Ready. Ball at: %s, Wind: %s" % [grid_position, wind_direction * wind_speed])

# === PUBLIC API - ENVIRONMENT CONTROL ===
func _update_weather(new_wind_speed: float, new_wind_direction: Vector2):
	"""Called by a future WeatherManager or at quarter breaks."""
	wind_speed = clamp(new_wind_speed, 0.0, 1.0)
	wind_direction = new_wind_direction.normalized()
	# Humidity affects how quickly the ball gets wet/dry.
	moisture_factor = lerp(moisture_factor, humidity, 0.1)
	Debug.log_info("BallManager", "Weather updated. Wind: %s at strength %0.2f" % [wind_direction, wind_speed])

func update_momentum(team_scored: int, big_play: bool = false):
	"""
	Adjusts the game's momentum based on events.
	Parameters:
		team_scored: 0 or 1. Which team just scored or made a big play.
		big_play: If true, causes a larger momentum shift (e.g., a goal vs. a behind).
	"""
	var shift = 0.2 if big_play else 0.1
	# Shift momentum towards the team that made the play.
	if team_scored == 0:
		momentum_factor = clamp(momentum_factor + shift, -1.0, 1.0)
	else:
		momentum_factor = clamp(momentum_factor - shift, -1.0, 1.0)
	
	# Crowd noise reacts to momentum.
	crowd_noise_level = clamp(0.5 + (momentum_factor * 0.3), 0.2, 0.8)
	Debug.log_info("BallManager", "Momentum shifted to %0.2f for Team %d." % [momentum_factor, 0 if momentum_factor > 0 else 1])

# === ZONE LOGIC ===
func get_zone_for_position(pos: Vector2, for_team: int) -> String:
	"""
	Determines which field zone (Forward, Centre, Back) a grid position belongs to,
	from the perspective of a given team.
	"""
	var adjusted_x = pos.x
	# For Team 1, mirror the x-coordinate so their "forward" is on the right.
	if for_team == 1:
		adjusted_x = 40 - pos.x # Assuming grid_size_x = 40

	if adjusted_x < _field_zones.DEFENSIVE.x_range[1]:
		return "DEFENSIVE"
	elif adjusted_x < _field_zones.FORWARD.x_range[0]:
		return "CENTRE"
	else:
		return "FORWARD"

func is_position_in_scoring_area(pos: Vector2) -> Dictionary:
	"""Checks if a position is in a goal square, behind post area, or out of bounds."""
	var result = {"in_area": false, "area_name": "", "team": -1}
	
	# Team 0 scores from the right side (x > 38), Team 1 from the left (x < 2)
	if pos.x > 38 and pos.y > 8 and pos.y < 12:  # Right goal area - Team 0 scores here
		result = {"in_area": true, "area_name": "GOAL_SQUARE", "team": 0}  # Changed scoring_team to 0
	elif pos.x < 2 and pos.y > 8 and pos.y < 12:  # Left goal area - Team 1 scores here
		result = {"in_area": true, "area_name": "GOAL_SQUARE", "team": 1}  # Changed scoring_team to 1
	
	if result.in_area:
		ball_entered_scoring_area.emit(result.area_name, result.team)
	
	return result

# === BALL PHYSICS & POSSESSION LOGIC ===

func reset_ball(place_at_centre: bool = true):
	"""Resets the ball to a default state, typically after a goal or to start a quarter."""
	Debug.log_info("BallManager", "Resetting ball.")
	current_state = BallState.WITH_UMPIRE
	current_possession_type = PossessionType.CLEAN
	possessing_unit = null
	possessing_team = -1
	velocity = Vector2.ZERO
	rotation = 0.0

	if place_at_centre:
		# Place at centre of your grid (adjust 20, 10 to your grid's centre).
		grid_position = Vector2(20, 10)
		ball_position_updated.emit(grid_position)

	ball_state_changed.emit(current_state, {"reason": "reset"})

func set_ball_position(new_grid_pos: Vector2, new_state: BallState):
	"""
	Primary method to move the ball. Applies environmental effects and updates state.
	"""
	var old_pos = grid_position
	grid_position = new_grid_pos

	# 1. APPLY WIND DRIFT
	if wind_speed > 0.01 and current_state in [BallState.LOOSE_AIR, BallState.LOOSE_GROUND]:
		var wind_effect = wind_direction * wind_speed * 0.5 # Scale factor
		grid_position += wind_effect
		Debug.log_debug("BallManager", "Wind drifted ball by %s" % wind_effect)

	# 2. CHECK FOR SCORING AREAS
	var scoring_check = is_position_in_scoring_area(grid_position)
	if scoring_check.in_area:
		MatchDirector.register_score(scoring_check.team, "GOAL", grid_position)

	# 3. CHECK BOUNDARIES (Simple rectangular check for now)
	if grid_position.x < 0 or grid_position.x > 40 or grid_position.y < 0 or grid_position.y > 20:
		current_state = BallState.OUT_OF_BOUNDS
		Debug.log_info("BallManager", "Ball went out of bounds at %s" % grid_position)

	# 4. UPDATE STATE AND NOTIFY
	current_state = new_state
	ball_position_updated.emit(grid_position)
	var state_details = {
		"from_position": old_pos,
		"to_position": grid_position,
		"wind_affected": wind_speed > 0.01
	}
	ball_state_changed.emit(current_state, state_details)
	Debug.log_debug("BallManager", "Ball moved to %s, State: %s" % [grid_position, BallState.keys()[current_state]])

func execute_kick(kicking_unit: Node, target_grid_pos: Vector2, kick_power: float):
	"""
	Simulates a unit kicking the ball towards a target.
	This is a key action you will call from GameManager._execute_kick_action.
	"""
	if not is_instance_valid(kicking_unit):
		return

	Debug.log_info("BallManager", "Unit %s kicks towards %s" % [kicking_unit.unit_name, target_grid_pos])

	# 1. CALCULATE BASE ACCURACY
	var unit_skill = kicking_unit.kick_accuracy / 100.0
	# Momentum affects confidence: positive momentum helps, negative hurts.
	var momentum_effect = 1.0 + (momentum_factor if kicking_unit.team == 0 else -momentum_factor) * 0.1
	# Wet ball is harder to kick accurately.
	var moisture_penalty = 1.0 - (moisture_factor * 0.3)

	var total_accuracy = unit_skill * momentum_effect * moisture_penalty

	# 2. DETERMINE ACTUAL LANDING POSITION (Skill + Random Variance)
	var variance = (1.0 - total_accuracy) * 10.0 # Max grids of error
	var actual_target = target_grid_pos + Vector2(randf_range(-variance, variance), randf_range(-variance, variance))

	# 3. SET BALL STATE AND POSITION
	possessing_unit = null
	possessing_team = -1
	current_state = BallState.LOOSE_AIR
	current_possession_type = PossessionType.CLEAN
	# Give the ball some velocity for visual prediction (future feature).
	velocity = (actual_target - grid_position).normalized() * kick_power

	set_ball_position(actual_target, BallState.LOOSE_AIR)

	# 4. APPLY SPIN (Affects future bounce)
	rotation = randf_range(-PI, PI) # Random spin for now

func attempt_possession(attempting_unit: Node) -> bool:
	"""
	Simulates a unit trying to grab the loose ball. Called when a unit moves onto the ball's square.
	Returns true if they gain possession.
	"""
	Debug.log_info("BallManager", "Unit %s attempts to take possession." % attempting_unit.unit_name)

	# Can only possess a loose ball.
	if current_state not in [BallState.LOOSE_GROUND, BallState.LOOSE_AIR]:
		Debug.log_debug("BallManager", "  - Failed: Ball is not loose.")
		return false

	# 1. BASE CHANCE: Unit's "hands" or "marking" stat.
	var unit_skill = attempting_unit.hands if current_state == BallState.LOOSE_GROUND else attempting_unit.marking
	var base_chance = unit_skill / 100.0

	# 2. MODIFIERS
	# Wet ball is slippery.
	var moisture_penalty = 1.0 - (moisture_factor * 0.4)
	# Crowd pressure affects concentration.
	var crowd_factor = 1.0 - (crowd_noise_level * 0.2)
	# Fatigue matters.
	var stamina_factor = attempting_unit.current_stamina / 100.0

	var total_chance = base_chance * moisture_penalty * crowd_factor * stamina_factor

	# 3. DETERMINE OUTCOME
	if randf() < total_chance:
		# SUCCESS
		grant_possession(attempting_unit, PossessionType.CLEAN)
		return true
	else:
		# FAILURE - Ball might spill, be juggled, etc.
		var spill_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var spill_distance = randf_range(0.5, 2.0)
		var new_pos = grid_position + spill_direction * spill_distance
		set_ball_position(new_pos, BallState.LOOSE_GROUND)
		current_possession_type = PossessionType.JUGGLED
		Debug.log_info("BallManager", "  - Failed! Ball spills to %s" % new_pos)
		return false

func grant_possession(unit: Node, quality: PossessionType):
	"""Grants clean possession of the ball to a unit."""
	possessing_unit = unit
	possessing_team = unit.team
	current_state = BallState.HELD_CLEAN
	current_possession_type = quality
	grid_position = unit.hex_position # Ball snaps to unit's position.

	ball_position_updated.emit(grid_position)
	possession_changed.emit(unit, unit.team, quality)
	Debug.log_info("BallManager", "Unit %s takes %s possession." % [unit.unit_name, PossessionType.keys()[quality]])
# === INTEGRATION & HELPER METHODS ===

func process_ball_turn():
	"""
	Called by GameManager each simulation turn to process the ball's natural state.
	For example, a ball in the air should descend, a bouncing ball should move.
	"""
	match current_state:
		BallState.LOOSE_AIR:
			# A ball in the air is affected by gravity (simplified as downward drift).
			var downward_drift = Vector2(0, 0.5) * (1.0 + moisture_factor) # Wet ball drops faster?
			var new_pos = grid_position + downward_drift
			set_ball_position(new_pos, BallState.LOOSE_AIR)
			
			# If it's low enough, it becomes a ground ball.
			if randf() < 0.3: # Chance to hit the ground this turn.
				current_state = BallState.LOOSE_GROUND
				Debug.log_debug("BallManager", "Ball hits the ground at %s." % grid_position)
				
		BallState.LOOSE_GROUND:
			# A ball on the ground with velocity (from a bounce or spill) may roll.
			if velocity.length() > 0.1:
				# Apply friction and move.
				velocity *= (0.8 - moisture_factor * 0.2) # Wet grass is stickier.
				var new_pos = grid_position + velocity
				set_ball_position(new_pos, BallState.LOOSE_GROUND)
				
				# Check for a natural stop.
				if velocity.length() < 0.2:
					velocity = Vector2.ZERO
					Debug.log_debug("BallManager", "Ball comes to a rest.")
			# A stationary ball on the ground does nothing.
			pass
			
		BallState.HELD_CLEAN, BallState.HELD_CONTESTED:
			# The ball moves with the possessing unit. Update its grid position.
			if is_instance_valid(possessing_unit):
				grid_position = possessing_unit.hex_position
				ball_position_updated.emit(grid_position)
			else:
				# Safety: if unit is invalid, drop the ball.
				Debug.log_warn("BallManager", "Possessing unit invalid. Dropping ball.")
				current_state = BallState.LOOSE_GROUND
				possessing_unit = null
				possessing_team = -1
		# Other states (WITH_UMPIRE, OUT_OF_BOUNDS, DEAD_BALL) don't process movement.
		_:
			pass

# === PUBLIC QUERY API ===
# These functions allow other systems (GameManager, Unit AI) to safely ask about the ball.

func is_ball_loose() -> bool:
	"""Returns true if the ball is free to be won (on ground or in air)."""
	return current_state in [BallState.LOOSE_GROUND, BallState.LOOSE_AIR]

func is_ball_with_umpire() -> bool:
	return current_state == BallState.WITH_UMPIRE

func get_ball_grid_position() -> Vector2:
	"""Returns the current grid position of the ball. Safe for AI pathfinding."""
	return grid_position

func get_possession_info() -> Dictionary:
	"""Returns a snapshot of who has the ball and how."""
	return {
		"state": BallState.keys()[current_state],
		"possessing_unit": possessing_unit,
		"possessing_team": possessing_team,
		"possession_type": PossessionType.keys()[current_possession_type],
		"position": grid_position
	}

func get_nearest_unit_to_ball(units_array: Array) -> Node:
	"""
	Finds which unit in the provided array is closest to the ball's current position.
	Useful for AI to find who should go for the ball.
	"""
	if units_array.is_empty():
		return null
		
	var nearest_unit = null
	var nearest_distance = INF
	
	for unit in units_array:
		if not is_instance_valid(unit):
			continue
		# Simple distance calculation. Use grid coordinates.
		var dist = unit.hex_position.distance_to(grid_position)
		if dist < nearest_distance:
			nearest_distance = dist
			nearest_unit = unit
	
	return nearest_unit

# === DEBUG & DIAGNOSTICS ===

func print_ball_status():
	"""Prints the current ball status to the debug console."""
	var status = get_possession_info()
	Debug.log_info("BallManager", "=== BALL STATUS ===")
	for key in status:
		var value = status[key]
		if is_instance_valid(value):
			value = value.name if "name" in value else value
		Debug.log_info("BallManager", "  %s: %s" % [key, value])
	Debug.log_info("BallManager", "  Wind: %s (Speed: %0.2f)" % [wind_direction, wind_speed])
	Debug.log_info("BallManager", "  Moisture: %0.2f, Momentum: %0.2f" % [moisture_factor, momentum_factor])
