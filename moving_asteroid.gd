@tool
extends Node2D

@export var origin: Vector2

@export_tool_button("Set Origin", "KeyPosition") var btn_origin = func():
	origin = global_position
	
@export_tool_button("Reset", "UndoRedo") var btn_reset = func():
	global_position = origin
	
@export var move:= false
	
func _process(delta: float) -> void:
	if move:
		global_position += $RoxyVector2D.global_direction * delta
