extends Node2D

@export var grid_size_x: int = 100
@export var grid_size_y: int = 50
@export var cell_size: Vector2 = Vector2(16, 16)
@export var oval_width_ratio: float = 0.8
@export var oval_height_ratio: float = 0.9

func _ready():
	pass

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
				draw_rect(rect, Color(0.5, 0.5, 0.5, 0.5), false)

func grid_to_pixel(grid_coord: Vector2) -> Vector2:
	return Vector2(grid_coord.x * cell_size.x, grid_coord.y * cell_size.y)
	
