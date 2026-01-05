extends Node2D

@export var umpire_index: int = 0
@export var move_speed: float = 2.0

func _ready():
	# Set a unique color for each umpire
	var colors = [Color.RED, Color.BLUE, Color.GREEN]
	if umpire_index < colors.size():
		$Sprite2D.modulate = colors[umpire_index]

func _process(delta):
	# Get umpire position from MatchDirector
	var umpire_positions = MatchDirector.umpire_positions
	if umpire_index < umpire_positions.size():
		var target_pos = umpire_positions[umpire_index]
		# Convert grid position to pixel position (adjust based on your grid)
		var pixel_pos = Vector2(target_pos.x * 32, target_pos.y * 32)  # Assuming 16px cells
		# Smooth movement
		position = position.lerp(pixel_pos, move_speed * delta)
