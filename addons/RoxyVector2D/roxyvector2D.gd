@tool
extends EditorPlugin

# Icon displayed at the handle position in the 2D viewport overlay
var handleIcon: Texture2D

# Currently selected RoxyVector2D node, null if none
var selectedVector: RoxyVector2D = null

# Handle position in screen space (used for click detection and drawing)
var handleScreenPos: Vector2

# True when the user is dragging the direction handle
var grabbed: bool = false

# True when the user is dragging the node itself along its arrow
var moveGrabbed: bool = false

# Offset between the mouse and the node's origin at the moment of grab (world space)
var mouseOffset: Vector2

# Stores the previous value before a drag, used for undo/redo
var oldPos: Vector2


func _enable_plugin() -> void:
	pass


func _handles(object: Object) -> bool:
	# Always return true so _forward_canvas_gui_input is called regardless of selection
	return object is RoxyVector2D


func _disable_plugin() -> void:
	pass


var editorSelectionObj: EditorSelection

func _enter_tree() -> void:
	# Load the standard editor handle icon from the editor theme
	handleIcon = get_editor_interface().get_base_control().get_theme_icon("EditorHandle", "EditorIcons")
	editorSelectionObj = EditorInterface.get_selection()
	editorSelectionObj.selection_changed.connect(_on_selection_changed)


func _on_selection_changed():
	# Filter selected nodes to keep only RoxyVector2D instances
	var selectedVectorFilter = editorSelectionObj.get_selected_nodes().filter(func (e: Node):
		return e is RoxyVector2D
	)

	if selectedVectorFilter.size() > 0:
		var newSelectedVector = selectedVectorFilter.front() as RoxyVector2D

		# Swap the direction_changed signal connection to the newly selected node
		if selectedVector:
			if newSelectedVector != selectedVector:
				selectedVector.direction_changed.disconnect(update_overlays)
				newSelectedVector.direction_changed.connect(update_overlays)
		else:
			newSelectedVector.direction_changed.connect(update_overlays)

		selectedVector = newSelectedVector
		update_overlays()
	elif selectedVector:
		# Nothing selected anymore: disconnect and clear
		selectedVector.direction_changed.disconnect(update_overlays)
		selectedVector = null


func _forward_canvas_draw_over_viewport(viewport_control: Control) -> void:
	if selectedVector and selectedVector.get_viewport():
		# Compute the handle screen position (tip of the direction arrow)
		handleScreenPos = (selectedVector.get_viewport().get_screen_transform() * (selectedVector.global_position + selectedVector.direction))
		# Offset by the overlay's position to get local overlay coordinates
		var pos = handleScreenPos - viewport_control.global_position
		# Draw centered on the tip
		viewport_control.draw_texture(handleIcon, pos - handleIcon.get_size() / 2)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if selectedVector:
		var mouseEv = event as InputEventMouseButton
		if mouseEv and mouseEv.button_index == MOUSE_BUTTON_LEFT:
			if mouseEv.pressed:
				var dist = handleScreenPos.distance_squared_to(mouseEv.global_position)
				var worldPos: Vector2 = EditorInterface.get_editor_viewport_2d().get_screen_transform().affine_inverse() * mouseEv.global_position

				if dist < 150:
					# Click is close enough to the handle: start direction drag
					grabbed = true
					moveGrabbed = false
					oldPos = selectedVector.direction
				elif Geometry2D.get_closest_point_to_segment(worldPos, selectedVector.global_position, selectedVector.global_position + selectedVector.direction).distance_squared_to(worldPos) < selectedVector.width * 2:
					# Click is on the arrow segment: start position drag
					moveGrabbed = true
					grabbed = false
					oldPos = selectedVector.position
					# Store offset so the node doesn't snap to the mouse origin
					mouseOffset = worldPos - selectedVector.global_position

				return grabbed or _check_select_vectors(mouseEv.global_position)
			else:
				# Mouse released: commit undo/redo action if a drag was active
				if grabbed:
					grabbed = false
					var undo = get_undo_redo()
					undo.create_action("Change direction of %s to %s" % [selectedVector.name, selectedVector.direction])
					undo.add_do_property(selectedVector, "direction", selectedVector.direction)
					undo.add_undo_property(selectedVector, "direction", oldPos)
					undo.commit_action(false)
				elif moveGrabbed:
					moveGrabbed = false
					var undo = get_undo_redo()
					undo.create_action("Change position of %s to %s" % [selectedVector.name, selectedVector.position])
					undo.add_do_property(selectedVector, "position", selectedVector.position)
					undo.add_undo_property(selectedVector, "position", oldPos)
					undo.commit_action(false)
				return false

		if grabbed or moveGrabbed:
			mouseEv = event as InputEventMouseMotion
			if mouseEv:
				if grabbed:
					# Update direction — snap to 4px grid when Ctrl/Cmd is held
					var newPos = (selectedVector.get_viewport().get_screen_transform().affine_inverse() * mouseEv.global_position) - selectedVector.global_position
					selectedVector.direction = newPos if !mouseEv.is_command_or_control_pressed() else newPos.snapped(Vector2(4, 4))
				else:
					# Update position — snap to 4px grid when Ctrl/Cmd is held
					var newPos = (selectedVector.get_viewport().get_screen_transform().affine_inverse() * mouseEv.global_position) - mouseOffset
					selectedVector.global_position = newPos if !mouseEv.is_command_or_control_pressed() else newPos.snapped(Vector2(4, 4))

	elif event is InputEventMouseButton and event.is_pressed():
		# No vector selected: try to select one by clicking on its arrow
		return _check_select_vectors(event.global_position)

	return false


func _input(event: InputEvent) -> void:
	# When no vector is selected, listen for clicks in the 2D viewport
	# to allow selecting a vector by clicking on its arrow
	if !selectedVector:
		var mouseEv = event as InputEventMouseButton
		if mouseEv and mouseEv.pressed and EditorInterface.get_editor_viewport_2d().get_parent().get_global_rect().has_point(mouseEv.global_position):
			if _check_select_vectors(mouseEv.global_position):
				get_viewport().set_input_as_handled()


func _check_select_vectors(mouseGlobalPos: Vector2) -> bool:
	# Convert screen position to world position
	var worldPos: Vector2 = EditorInterface.get_editor_viewport_2d().get_screen_transform().affine_inverse() * mouseGlobalPos
	var sceneRoot := EditorInterface.get_edited_scene_root() as Node
	if !sceneRoot:
		return false
	var roxyVectors = sceneRoot.find_children("*", "RoxyVector2D", true)

	# Include the root node itself if it is a RoxyVector2D
	if sceneRoot is RoxyVector2D:
		roxyVectors.push_front(sceneRoot)

	for rawv in roxyVectors:
		var v = rawv as RoxyVector2D
		# Check if the click is close enough to the arrow segment
		if is_node_editable(v) and Geometry2D.get_closest_point_to_segment(worldPos, v.global_position, v.global_position + v.direction).distance_squared_to(worldPos) < v.width * 2:
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(v)
			return true

	return false


func _exit_tree() -> void:
	editorSelectionObj.selection_changed.disconnect(_on_selection_changed)
	
# Check if node is in editable scene instance or owe to the current scene
func is_node_editable(node: Node) -> bool:
	var scene_root = EditorInterface.get_edited_scene_root()
	var current = node
	while current != scene_root and current != null:
		if current.scene_file_path != "":
			# current est la racine d'une sous-scène instanciée
			return scene_root.is_editable_instance(current)
		current = current.get_parent()
	return true # la node appartient directement à la scène éditée
