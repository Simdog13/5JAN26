# autoloads/MatchDirector.gd
# ============================================
# PURPOSE: The "referee" and "producer" of the match.
# PRINCIPLE: Enforces rules, tracks time/score, triggers events, and controls match flow.
#            This script REACTS to simulation events and DIRECTS other managers.
# ACCESS: Global singleton via `MatchDirector`.
# ============================================

extends Node

# === SIGNALS ===
# These signals are the primary way the UI (scoreboard, clock) and game systems are updated.
signal match_state_changed(new_state) # e.g., "QUARTER_BREAK", "PLAYING"
signal score_updated(team_0_score, team_1_score)
signal quarter_updated(current_quarter, time_remaining_seconds)
signal match_time_paused(paused) # For UI to show "PAUSED" label
signal random_event_triggered(event_name, description)

# === CORE MATCH STATES ===
enum MatchState {
	PRE_MATCH,      # Teams are set, game plan chosen.
	QUARTER_1,      # First quarter is active.
	QUARTER_BREAK_1, # Break after Q1.
	QUARTER_2,
	HALF_TIME,
	QUARTER_3,
	QUARTER_BREAK_3,
	QUARTER_4,
	POST_MATCH      # Final siren, winner declared.
}

# === PUBLIC MATCH PROPERTIES ===
# These are the key variables that define the current state of the match.
var current_state: MatchState = MatchState.PRE_MATCH:
	set(value):
		if current_state != value:
			current_state = value
			match_state_changed.emit(current_state)
			Debug.log_info("MatchDirector", "Match state changed to: %s" % MatchState.keys()[current_state])

var scores = {0: 0, 1: 0} # Dictionary: Team Number -> Total Score
var current_quarter: int = 1
var quarter_time_remaining: float = 5.0 * 60.0 # Start with 5 SIMULATION minutes (300 seconds)
var is_match_clock_running: bool = false

# Game flow modifiers from your design.
var momentum_swing_lock: bool = false # Prevents momentum flip-flopping too quickly.
var next_random_event_minute: float = 2.0 # First random event at ~2 mins into a quarter.

# Pre-game selected strategy.
var selected_game_plan: String = "BALANCED" # "CORRIDOR_ATTACK", "PRESSING_FLOOD", "DEFENSIVE_GRIND"

# === INITIALIZATION & MATCH FLOW ===

func _ready():
	"""Called when the MatchDirector autoload loads. Sets up initial match state."""
	Debug.log_info("MatchDirector", "Initializing match...")
	current_state = MatchState.PRE_MATCH
	_setup_quarter_timer()
	_setup_umpires()
	_connect_to_managers()
	Debug.log_info("MatchDirector", "Match ready. Awaiting start command.")

func start_match():
	"""Call this from a 'Start Match' button in your UI."""
	if current_state != MatchState.PRE_MATCH:
		Debug.log_warn("MatchDirector", "Cannot start match from state: %s" % MatchState.keys()[current_state])
		return

	Debug.log_info("MatchDirector", "=== MATCH STARTING ===")
	Debug.log_info("MatchDirector", "Selected Game Plan: %s" % selected_game_plan)
	_apply_game_plan_to_ai()
	_advance_to_next_quarter() # This will move state to QUARTER_1 and start the clock.

func _advance_to_next_quarter():
	"""Moves the match to the next logical state (e.g., QUARTER_1 -> QUARTER_BREAK_1)."""
	match current_state:
		MatchState.PRE_MATCH:
			current_state = MatchState.QUARTER_1
		MatchState.QUARTER_1:
			current_state = MatchState.QUARTER_BREAK_1
		MatchState.QUARTER_BREAK_1:
			current_state = MatchState.QUARTER_2
		MatchState.QUARTER_2:
			current_state = MatchState.HALF_TIME
		MatchState.HALF_TIME:
			current_state = MatchState.QUARTER_3
		MatchState.QUARTER_3:
			current_state = MatchState.QUARTER_BREAK_3
		MatchState.QUARTER_BREAK_3:
			current_state = MatchState.QUARTER_4
		MatchState.QUARTER_4:
			current_state = MatchState.POST_MATCH
			_end_match()
			return # Don't start the clock after the match.

	# If we've entered a playing quarter (1, 2, 3, 4), start the clock.
	if _is_quarter_active_state(current_state):
		_start_quarter()
	else:
		# We're in a break or half-time. Pause the simulation.
		GameManager.request_simulation_stop()
		Debug.log_info("MatchDirector", "--- %s ---" % MatchState.keys()[current_state])
		# Schedule the next quarter to start automatically after a delay.
		var break_duration = 30.0 if "BREAK" in MatchState.keys()[current_state] else 90.0 # Sim seconds for break/halftime
		await get_tree().create_timer(break_duration).timeout
		_advance_to_next_quarter()

func _start_quarter():
	"""Resets quarter clock, starts the simulation, and triggers quarter-start events."""
	_setup_quarter_timer()
	is_match_clock_running = true
	GameManager.request_simulation_start()
	
	# Place ball in centre for bounce
	BallManager.reset_ball(true)
	
	Debug.log_info("MatchDirector", "=== QUARTER %d START ===" % current_quarter)
	quarter_updated.emit(current_quarter, quarter_time_remaining)

func _setup_quarter_timer():
	"""Configures the timer for the current quarter. Adjust these numbers to control total match length."""
	match current_quarter:
		1, 3:
			quarter_time_remaining = 5.0 * 60.0  # 5 simulation minutes
		2, 4:
			quarter_time_remaining = 6.0 * 60.0  # 6 simulation minutes (longer last quarter for drama)
		_:
			quarter_time_remaining = 5.0 * 60.0

# === FRAME-BY-FRAME MATCH PROCESSING ===
# This is where you harness frame-based time control.

func _process(delta):
	"""
	Called every frame. Drives the match clock and checks for time-based events.
	`delta` is real-world time since last frame (e.g., ~0.0167s at 60 FPS).
	"""
	if not is_match_clock_running:
		return

	# 1. ADVANCE THE MATCH CLOCK
	# This is your core pacing control. `delta` is real time. Multiply by a scale factor
	# to control how many simulation seconds pass per real second.
	var simulation_time_scale = 10.0 # CRITICAL: 1 real second = 10 sim seconds.
	var sim_delta = delta * simulation_time_scale
	quarter_time_remaining -= sim_delta

	# Emit signal for UI updates (throttled to avoid spamming).
	if int(quarter_time_remaining) != int(quarter_time_remaining + sim_delta):
		quarter_updated.emit(current_quarter, quarter_time_remaining)

	# 2. CHECK FOR QUARTER END
	if quarter_time_remaining <= 0:
		_end_quarter()
		return

	# 3. CHECK FOR RANDOM EVENTS (based on simulation time, not frame count)
	next_random_event_minute -= sim_delta / 60.0 # Convert sim_delta to minutes
	if next_random_event_minute <= 0:
		_trigger_random_event()
		# Schedule next event between 2-4 sim minutes from now
		next_random_event_minute = randf_range(2.0, 4.0)

	# 4. DYNAMIC TIME DILATION - A SUPERIOR FRAME-BASED EFFECT
	# Example: Slow down time when ball is in scoring position for dramatic tension.
	_apply_dynamic_time_dilation()

	# Update umpire positions to follow play
	_update_umpire_positions()

func _apply_dynamic_time_dilation():
	"""Adjusts GameManager.game_speed based on exciting match situations."""
	var target_speed = 1.0 # Normal speed

	# Example Effect 1: "Goal-mouth scramble" slowdown
	var ball_pos = BallManager.get_ball_grid_position()
	var scoring_check = BallManager.is_position_in_scoring_area(ball_pos)
	if scoring_check.in_area and BallManager.is_ball_loose():
		target_speed = 0.5 # Slow down 50% for drama

	# Example Effect 2: "Last minute of close quarter" slowdown
	if quarter_time_remaining < 60.0 and abs(scores[0] - scores[1]) <= 12: # Close game, last minute
		target_speed = 0.75

	# Smoothly interpolate to the target speed (frame-by-frame smoothness).
	GameManager.game_speed = lerp(GameManager.game_speed, target_speed, 0.05)

# === HELPER FUNCTIONS ===
func _is_quarter_active_state(state: MatchState) -> bool:
	return state in [MatchState.QUARTER_1, MatchState.QUARTER_2, MatchState.QUARTER_3, MatchState.QUARTER_4]

func _apply_game_plan_to_ai():
	"""Placeholder: Modifies global AI decision weights based on selected_game_plan."""
	Debug.log_info("MatchDirector", "Applying game plan: %s" % selected_game_plan)
	# This will connect to your AI_Controller's decision weights.
	# Example: if selected_game_plan == "CORRIDOR_ATTACK":
	#     AI_Controller.corridor_kick_bias = 1.3

# === SCORING, MOMENTUM & RULES ENFORCEMENT ===

# Umpire settings
var umpire_count: int = 3
var umpire_positions: Array = [] # Array of Vector2 grid positions
var umpire_vision_range: int = 8 # Grid squares an umpire can "see"
var umpire_decision_accuracy: float = 0.85 # Base chance to make correct call (85%)

func _setup_umpires():
	"""Plays umpires at strategic field positions at quarter start."""
	umpire_positions.clear()
	# Classic AFL field positioning: 1 center, 2 wings
	var field_center = Vector2(20, 10)
	var wing_left = Vector2(10, 5)
	var wing_right = Vector2(30, 15)
	
	umpire_positions.append(field_center)
	umpire_positions.append(wing_left)
	umpire_positions.append(wing_right)
	
	Debug.log_info("MatchDirector", "Umpires deployed at positions: %s" % umpire_positions)

# === SCORING & MOMENTUM ===
func register_score(scoring_team: int, score_type: String, grid_position: Vector2):
	"""
	Called by BallManager when ball enters a scoring area.
	score_type: "GOAL" (6 points) or "BEHIND" (1 point)
	"""
	# 1. UMPIRE REVIEW SYSTEM - Did they actually see it correctly?
	var call_is_correct = _umpire_make_call("SCORING_REVIEW", grid_position)
	var awarded_score_type = score_type
	
	if not call_is_correct:
		# Umpire made a mistake! 50/50 chance they call the opposite.
		if randf() < 0.5:
			awarded_score_type = "BEHIND" if score_type == "GOAL" else "GOAL"
			Debug.log_info("MatchDirector", "UMPIRE ERROR! Changed %s to %s for Team %d" % 
				[score_type, awarded_score_type, scoring_team])
	
	# 2. AWARD POINTS
	var points = 6 if awarded_score_type == "GOAL" else 1
	scores[scoring_team] += points
	
	Debug.log_info("MatchDirector", "Team %d scores a %s! (%d points)" % [scoring_team, awarded_score_type, points])
	score_updated.emit(scores[0], scores[1])
	
	# 3. MOMENTUM CALCULATION (with rubber-banding)
	var is_big_play = (awarded_score_type == "GOAL")
	_update_momentum_after_score(scoring_team, is_big_play, points)
	
	# 4. BALL RESET
	BallManager.reset_ball(true) # Back to center
	_pause_match_clock_for_stoppage(5.0) # 5 sim seconds for celebration/setup

func _update_momentum_after_score(scoring_team: int, is_big_play: bool, points_awarded: int):
	"""
	Implements your 'diminishing returns' and 'comeback' mechanics.
	Scoring gives you momentum, but not too much if you're already dominant.
	"""
	if momentum_swing_lock:
		return
		
	# Calculate base momentum shift
	var base_shift = 0.15 if is_big_play else 0.08
	
	# COMEBACK MECHANIC: Team that's behind gets a bigger momentum boost
	var score_diff = scores[scoring_team] - scores[1 - scoring_team]
	if score_diff < 0: # If the scoring team was behind
		base_shift *= 1.5 # 50% bigger momentum shift for comebacks
		Debug.log_debug("MatchDirector", "Comeback boost applied for Team %d" % scoring_team)
	
	# DIMINISHING RETURNS: If a team is way ahead, they get less momentum
	if score_diff > 18: # More than 3 goals ahead
		base_shift *= 0.5 # Halve the momentum gain
		Debug.log_debug("MatchDirector", "Diminishing returns applied for Team %d" % scoring_team)
	
	# Apply the shift via BallManager (which will adjust crowd noise too)
	BallManager.update_momentum(scoring_team, base_shift)
	
	# Brief lock to prevent flip-flopping
	momentum_swing_lock = true
	await get_tree().create_timer(2.0).timeout # 2 sim seconds
	momentum_swing_lock = false

# === UMPIRE DECISION SYSTEM ===
func _umpire_make_call(call_type: String, event_position: Vector2) -> bool:
	"""
	Simulates an umpire making a decision. Returns TRUE if call is correct.
	Factors: Distance, visibility, game speed, pressure.
	"""
	# 1. FIND NEAREST UMPIRE
	var nearest_umpire_distance = INF
	var nearest_umpire_index = -1
	
	for i in range(umpire_positions.size()):
		var dist = umpire_positions[i].distance_to(event_position)
		if dist < nearest_umpire_distance:
			nearest_umpire_distance = dist
			nearest_umpire_index = i
	
	# 2. CALCULATE DECISION ACCURACY
	var accuracy = umpire_decision_accuracy
	
	# Distance penalty: umpires further away are less accurate
	var distance_penalty = clamp(nearest_umpire_distance / umpire_vision_range, 0.0, 1.0)
	accuracy *= (1.0 - distance_penalty * 0.4) # Up to 40% penalty at max distance
	
	# Game speed penalty: fast play is harder to judge
	var speed_penalty = GameManager.game_speed * 0.1 # 10% penalty at 1.0x, more if faster
	accuracy *= (1.0 - speed_penalty)
	
	# Crowd pressure penalty: loud crowds can influence decisions
	var crowd_penalty = BallManager.crowd_noise_level * 0.05
	accuracy *= (1.0 - crowd_penalty)
	
	# 3. MAKE THE CALL
	var is_correct = randf() < accuracy
	
	if not is_correct:
		Debug.log_info("MatchDirector", 
			"UMPIRE BLUNDER! Type: %s at %s. Distance: %0.1f, Accuracy was: %0.1f%%" % 
			[call_type, event_position, nearest_umpire_distance, accuracy * 100])
	
	return is_correct

func _update_umpire_positions():
	"""Umpires move during play to follow the ball (simplified)."""
	var ball_pos = BallManager.get_ball_grid_position()
	
	for i in range(umpire_positions.size()):
		# Simple movement: umpires slowly drift toward the ball's general area
		var target = ball_pos + Vector2(randf_range(-5, 5), randf_range(-3, 3))
		var move_vector = (target - umpire_positions[i]).normalized() * 0.3 # Slow drift
		umpire_positions[i] += move_vector

# === RULES ENFORCEMENT ===
func check_for_infraction(unit: Node, action: String) -> bool:
	"""
	Called when a unit performs a questionable action (tackle, push, etc.).
	Returns TRUE if the umpire calls a free kick against them.
	"""
	var ball_pos = BallManager.get_ball_grid_position()
	var call_correct = _umpire_make_call("INFRACTION_" + action, ball_pos)
	
	# If the umpire SAW an infraction (correctly or not), award free kick
	if not call_correct:
		# Wrong call! The innocent team gets penalized
		var victim_team = 1 - unit.team
		Debug.log_info("MatchDirector", "WRONG CALL! Free kick to Team %d for imaginary %s" % [victim_team, action])
		_award_free_kick(victim_team, ball_pos)
		return true
	elif action in ["HIGH_TACKLE", "PUSH_IN_BACK"]:
		# Correct call for real infraction
		var victim_team = 1 - unit.team
		Debug.log_info("MatchDirector", "Free kick to Team %d for %s" % [victim_team, action])
		_award_free_kick(victim_team, ball_pos)
		return true
	
	return false # No infraction called

func _award_free_kick(to_team: int, position: Vector2):
	"""Sets up a free kick situation."""
	# Stop play
	_pause_match_clock_for_stoppage(3.0)
	
	# Position ball at infringement spot
	BallManager.set_ball_position(position, BallManager.BallState.WITH_UMPIRE)
	
	# Give possession to the team
	var nearest_unit = BallManager.get_nearest_unit_to_ball(
		GameManager.registered_units.filter(func(u): return u.team == to_team)
	)
	if nearest_unit:
		BallManager.grant_possession(nearest_unit, BallManager.PossessionType.CLEAN)
	
	Debug.log_info("MatchDirector", "Free kick awarded to Team %d at %s" % [to_team, position])

# === TIME CONTROL FOR STOPPAGES ===
func _pause_match_clock_for_stoppage(sim_seconds: float):
	"""Pauses the match clock for set periods (goals, free kicks, out-of-bounds)."""
	is_match_clock_running = false
	match_time_paused.emit(true)
	
	# Also slow down the simulation for dramatic effect
	var original_speed = GameManager.game_speed
	GameManager.game_speed = 0.3 # Slow-mo during stoppage setup
	
	await get_tree().create_timer(sim_seconds * 0.5).timeout # Real-time wait
	
	GameManager.game_speed = original_speed
	is_match_clock_running = true
	match_time_paused.emit(false)
# === RANDOM EVENTS SYSTEM ===
func _trigger_random_event():
	"""
	Triggers a random match event based on game state.
	Events should feel organic, not purely random.
	"""
	var event_pool = []
	
	# 1. WEATHER-RELATED EVENTS
	if BallManager.moisture_factor > 0.7:
		event_pool.append("HEAVY_DEW")
	if BallManager.wind_speed > 0.6:
		event_pool.append("GUSTING_WIND")
	
	# 2. FATIGUE-RELATED EVENTS (Darkest Dungeon style)
	var exhausted_units = GameManager.registered_units.filter(
		func(u): return u.current_stamina < 20
	)
	if exhausted_units.size() > 2:
		event_pool.append("FATIGUE_SETTING_IN")
	
	# 3. CROWD/MOMENTUM EVENTS
	if abs(BallManager.momentum_factor) > 0.7:
		event_pool.append("CROWD_ERUPTS")
	if scores[0] - scores[1] > 24: # Big lead
		event_pool.append("COMFORTABLE_LEAD")
	
	# 4. ALWAYS AVAILABLE EVENTS
	event_pool.append_array([
		"BALL_GOES_FLAT", 
		"MINOR_SCUFFLE", 
		"BRILLIANT_SOLO_EFFORT",
		"TACTICAL_SHIFT"
	])
	
	# Select and execute an event
	if event_pool.is_empty():
		return
		
	var selected_event = event_pool[randi() % event_pool.size()]
	_execute_random_event(selected_event)

func _execute_random_event(event_name: String):
	"""Executes the effects of a random event."""
	var description = ""
	var duration = 60.0 # Default: affects 1 sim minute
	
	match event_name:
		"HEAVY_DEW":
			description = "Heavy dew settles on the oval. The ball becomes slippery."
			BallManager.moisture_factor = 0.9
			Debug.log_info("MatchDirector", "Event: Ball moisture increased to 90%")
			
		"GUSTING_WIND":
			description = "Gusting wind swirls around the ground."
			BallManager.wind_speed = 0.8
			BallManager.wind_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			Debug.log_info("MatchDirector", "Event: Wind now %s at %0.1f strength" % 
				[BallManager.wind_direction, BallManager.wind_speed])
			
		"FATIGUE_SETTING_IN":
			description = "Players are feeling the pace. Stamina drains faster."
			duration = 120.0 # 2 minutes
			# Apply a stamina drain multiplier to all units
			for unit in GameManager.registered_units:
				if unit.has_method("apply_fatigue_event"):
					unit.apply_fatigue_event()
			Debug.log_info("MatchDirector", "Event: All units receive fatigue penalty")
			
		"CROWD_ERUPTS":
			var leading_team = 0 if scores[0] > scores[1] else 1
			description = "The crowd is roaring! The home team feeds off the energy."
			BallManager.crowd_noise_level = 0.9
			# Give the leading team a temporary accuracy boost
			# This would connect to your AI_Controller
			Debug.log_info("MatchDirector", "Event: Crowd noise at 90%, Team %d boosted" % leading_team)
			
		"BALL_GOES_FLAT":
			description = "The ball goes flat! It's replaced but behaves unpredictably."
			# Add random variance to all kick distances
			BallManager.execute_kick_variance_multiplier = 1.5
			duration = 30.0
			Debug.log_info("MatchDirector", "Event: Kick variance increased 50%")
			
		"TACTICAL_SHIFT":
			description = "Coaches make tactical adjustments. Play styles shift."
			# Toggle between aggressive and conservative AI
			selected_game_plan = "DEFENSIVE_GRIND" if selected_game_plan == "CORRIDOR_ATTACK" else "CORRIDOR_ATTACK"
			_apply_game_plan_to_ai()
			Debug.log_info("MatchDirector", "Event: Game plan switched to %s" % selected_game_plan)
			
		_:
			description = "Something unusual happens..."
	
	Debug.log_info("MatchDirector", "RANDOM EVENT: %s" % event_name)
	random_event_triggered.emit(event_name, description)
	
	# Schedule event cleanup
	await get_tree().create_timer(duration).timeout
	_end_random_event(event_name)

func _end_random_event(event_name: String):
	"""Cleans up after a random event expires."""
	match event_name:
		"BALL_GOES_FLAT":
			BallManager.execute_kick_variance_multiplier = 1.0
		"HEAVY_DEW":
			BallManager.moisture_factor = 0.5 # Return to average
		"GUSTING_WIND":
			BallManager.wind_speed = 0.3
	# ... other cleanups

# === MATCH CONCLUSION ===
func _end_quarter():
	"""Called when quarter time expires."""
	is_match_clock_running = false
	GameManager.request_simulation_stop()
	
	Debug.log_info("MatchDirector", "=== QUARTER %d END ===" % current_quarter)
	Debug.log_info("MatchDirector", "Score: Team 0: %d, Team 1: %d" % [scores[0], scores[1]])
	
	# Small momentum reset at quarter breaks
	BallManager.momentum_factor *= 0.5 # Halve momentum between quarters
	
	# Advance to next state (break or next quarter)
	await get_tree().create_timer(2.0).timeout # Brief pause
	_advance_to_next_quarter()

func _end_match():
	"""Final match cleanup and winner declaration."""
	is_match_clock_running = false
	GameManager.request_simulation_stop()
	
	Debug.log_info("MatchDirector", "=== MATCH END ===")
	Debug.log_info("MatchDirector", "FINAL SCORE: Team 0: %d, Team 1: %d" % [scores[0], scores[1]])
	
	var winner = 0 if scores[0] > scores[1] else 1 if scores[1] > scores[0] else -1
	if winner == -1:
		Debug.log_info("MatchDirector", "RESULT: Draw!")
	else:
		Debug.log_info("MatchDirector", "RESULT: Team %d wins by %d points!" % 
			[winner, abs(scores[0] - scores[1])])
	
	# Emit a final signal for UI to show match summary
	# match_concluded.emit(winner, scores[0], scores[1])

# === INTEGRATION HOOKS ===
func _connect_to_managers():
	"""Connects MatchDirector to other managers' signals. Call this in _ready()."""
	# Connect to BallManager scoring detection
	if BallManager.ball_entered_scoring_area.is_connected(_on_ball_entered_scoring_area):
		BallManager.ball_entered_scoring_area.disconnect(_on_ball_entered_scoring_area)
	BallManager.ball_entered_scoring_area.connect(_on_ball_entered_scoring_area)
	
	# Connect to GameManager for infraction checks
	# (You'll need to add a signal in GameManager when tackles occur)
	# GameManager.unit_attempted_tackle.connect(_on_unit_attempted_tackle)
	
	Debug.log_info("MatchDirector", "Connected to manager signals")

func _on_ball_entered_scoring_area(area_name: String):
	"""Handler for when BallManager detects scoring area entry."""
	# Determine score type based on area
	var score_type = "GOAL" if area_name == "GOAL_SQUARE" else "BEHIND"
	var scoring_team = 0 if area_name.contains("Team0") else 1 # Your area logic
	
	# Get current ball position for umpire review
	var ball_pos = BallManager.get_ball_grid_position()
	
	# Process the score with umpire review
	register_score(scoring_team, score_type, ball_pos)

# === DIAGNOSTICS & DEBUG ===
func print_match_summary():
	"""Prints comprehensive match status to debug console."""
	Debug.log_info("MatchDirector", "=== MATCH SUMMARY ===")
	Debug.log_info("MatchDirector", "State: %s, Quarter: %d" % 
		[MatchState.keys()[current_state], current_quarter])
	Debug.log_info("MatchDirector", "Time Remaining: %0.1f sec" % quarter_time_remaining)
	Debug.log_info("MatchDirector", "Score: Team 0: %d, Team 1: %d" % [scores[0], scores[1]])
	Debug.log_info("MatchDirector", "Clock Running: %s" % is_match_clock_running)
	
	# Ball status via BallManager
	BallManager.print_ball_status()
	
	# Momentum & Weather
	Debug.log_info("MatchDirector", "Momentum: %0.2f, Crowd: %0.2f" % 
		[BallManager.momentum_factor, BallManager.crowd_noise_level])
	Debug.log_info("MatchDirector", "Game Plan: %s" % selected_game_plan)
