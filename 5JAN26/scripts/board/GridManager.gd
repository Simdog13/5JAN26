extends Node2D

@export var grid_size_x: int = 40
@export var grid_size_y: int = 20
@export var cell_size: Vector2 = Vector2(16, 16)
@export var oval_width_ratio: float = 0.8
@export var oval_height_ratio: float = 0.9

# This 2D array will store what unit (if any) is in each cell.
var board_grid = []

func _ready():
	initialize_grid()
	queue_redraw()  # This tells Godot to call the _draw() function

func initialize_grid():
	board_grid = []
	for x in range(grid_size_x):
		var column = []
		for y in range(grid_size_y):
			# Initialize each cell with null (empty)
			column.append(null)
		board_grid.append(column)

func is_in_oval(x: int, y: int) -> bool:
	var center_x = grid_size_x / 2.0
	var center_y = grid_size_y / 2.0
	var dx = (x - center_x) / (grid_size_x / 2.0 * oval_width_ratio)
	var dy = (y - center_y) / (grid_size_y / 2.0 * oval_height_ratio)
	return (dx*dx + dy*dy) <= 1.0

func _draw():
	for x in range(grid_size_x):
		for y in range(grid_size_y):
			if is_in_oval(x, y):
				var rect = Rect2(Vector2(x, y) * cell_size, cell_size)
				var color = Color(0.3, 0.6, 0.3) if (x + y) % 2 == 0 else Color(0.4, 0.7, 0.4)
				draw_rect(rect, color, false)

# Call this from GameController to place a unit on the grid
func place_unit(unit_node: Node2D, grid_x: int, grid_y: int) -> bool:
	if not is_in_oval(grid_x, grid_y):
		print("Position is outside the oval field!")
		return false
	if board_grid[grid_x][grid_y] != null:
		print("Position already occupied!")
		return false
		
	board_grid[grid_x][grid_y] = unit_node
	unit_node.position = Vector2(grid_x, grid_y) * cell_size
	unit_node.hex_position = Vector2(grid_x, grid_y) # Update unit's internal grid coord
	return true

# Convert grid coordinates to pixel position (for Unit.gd to call)
func grid_to_pixel(grid_coord: Vector2) -> Vector2:
	return grid_coord * cell_size
