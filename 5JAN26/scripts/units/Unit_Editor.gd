# Unit_Editor.gd - Edits units in real-time
extends Control

@onready var unit : AFLPlayerUnit = null
@onready var stat_sliders = {}

func _ready():
	# Create UI dynamically for any selected unit
	create_editor_ui()

func create_editor_ui():
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	# Unit selection dropdown
	var unit_select = OptionButton.new()
	for u in get_tree().get_nodes_in_group("units"):
		unit_select.add_item(u.unit_name)
	unit_select.connect("item_selected", _on_unit_selected)
	vbox.add_child(unit_select)
	
	# Create sliders for all exported stats
	var stats = ["consciousness", "stamina", "speed_base", "kick_accuracy", 
				 "marking", "leap", "hands", "iq", "physical_build", "stress"]
	
	for stat in stats:
		var hbox = HBoxContainer.new()
		var label = Label.new()
		label.text = stat.capitalize()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var slider = HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.value = unit.get(stat) if unit else 50
		slider.connect("value_changed", _on_stat_changed.bind(stat))
		
		var value_label = Label.new()
		value_label.text = str(slider.value)
		
		stat_sliders[stat] = {"slider": slider, "label": value_label}
		
		hbox.add_child(label)
		hbox.add_child(slider)
		hbox.add_child(value_label)
		vbox.add_child(hbox)

func _on_unit_selected(index):
	var units = get_tree().get_nodes_in_group("units")
	if index < units.size():
		unit = units[index]
		update_sliders()

func update_sliders():
	print("Updating sliders")
	# Placeholder

func _on_stat_changed(value, stat_name):
	if unit:
		unit.set_stat(stat_name, value)
		stat_sliders[stat_name].label.text = str(value)
