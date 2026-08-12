@tool
extends EditorPlugin

const roxyvector2d_settings = preload("res://addons/RoxyVector2D/roxyvector2D_settings.gd")

# Icon displayed at the handle position in the 2D viewport overlay
var handleIcon: Texture2D

# Currently selected RoxyVector2D node, null if none
var selectedVector: RoxyVector2D = null

# True when the user is dragging the direction handle
var grabbed: bool = false

# True when the user is dragging the node itself along its arrow
var moveGrabbed: bool = false

# Offset between the mouse and the node's origin at the moment of grab (world space)
var mouseOffset: Vector2

# Stores the previous value before a drag, used for undo/redo
var oldPos: Vector2

# Store the current snap value from the projet settings
var grid_snap: Vector2


func _enable_plugin() -> void:
	pass

func _handles(object: Object) -> bool:
	return object is RoxyVector2D


func _disable_plugin() -> void:
	pass


var editorSelectionObj: EditorSelection

func _enter_tree() -> void:
	# Check and init project settings
	if !ProjectSettings.has_setting(roxyvector2d_settings.PROJECT_SETTINGS_DEFAULT_WIDTH):
		ProjectSettings.set_setting(roxyvector2d_settings.PROJECT_SETTINGS_DEFAULT_WIDTH, roxyvector2d_settings.PROJECT_SETTINGS_DEFAULT_WIDTH_VALUE)
	ProjectSettings.set_initial_value(roxyvector2d_settings.PROJECT_SETTINGS_DEFAULT_WIDTH, roxyvector2d_settings.PROJECT_SETTINGS_DEFAULT_WIDTH_VALUE)
	
	if !ProjectSettings.has_setting(roxyvector2d_settings.PROJECT_SETTINGS_GRID_SNAP_STEP):
		ProjectSettings.set_setting(roxyvector2d_settings.PROJECT_SETTINGS_GRID_SNAP_STEP, roxyvector2d_settings.PROJECT_SETTINGS_GRID_SNAP_STEP_VALUE)
	ProjectSettings.set_initial_value(roxyvector2d_settings.PROJECT_SETTINGS_GRID_SNAP_STEP, roxyvector2d_settings.PROJECT_SETTINGS_GRID_SNAP_STEP_VALUE)
	_update_grid_snap()
	
	ProjectSettings.settings_changed.connect(_on_project_settings_update)
	
	# Load the standard editor handle icon from the editor theme
	handleIcon = EditorInterface.get_base_control().get_theme_icon("EditorHandle", "EditorIcons")
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
		var handleScreenPos := (selectedVector.get_viewport().get_screen_transform() * selectedVector.to_global(selectedVector.direction))
		# Offset by the overlay's position to get local overlay coordinates
		var pos = handleScreenPos - viewport_control.global_position
		# Draw centered on the tip
		viewport_control.draw_texture(handleIcon, pos - handleIcon.get_size() / 2)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if selectedVector:
		var mouseEv = event as InputEventMouseButton
		if mouseEv and mouseEv.button_index == MOUSE_BUTTON_LEFT:
			if mouseEv.pressed:
				var handleScreenPos := (selectedVector.get_viewport().get_screen_transform() * selectedVector.to_global(selectedVector.direction))
				var dist = handleScreenPos.distance_squared_to(mouseEv.global_position)
				var worldPos: Vector2 = EditorInterface.get_editor_viewport_2d().get_screen_transform().affine_inverse() * mouseEv.global_position

				if dist < 150:
					# Click is close enough to the handle: start direction drag
					grabbed = true
					moveGrabbed = false
					oldPos = selectedVector.direction
				elif _point_on_arrow(worldPos, selectedVector):
					# Click is on the arrow segment: start position drag
					moveGrabbed = true
					grabbed = false
					oldPos = selectedVector.position
					# Store offset so the node doesn't snap to the mouse origin
					mouseOffset = worldPos - selectedVector.global_position

				return grabbed or moveGrabbed or _check_select_vectors(mouseEv.global_position)
			else:
				# Mouse released: commit undo/redo action if a drag was active
				if grabbed and selectedVector.direction != oldPos:
					var undo = get_undo_redo()
					undo.create_action("Change direction of %s to %s" % [selectedVector.name, selectedVector.direction])
					undo.add_do_property(selectedVector, "direction", selectedVector.direction)
					undo.add_undo_property(selectedVector, "direction", oldPos)
					undo.commit_action(false)
				elif moveGrabbed and selectedVector.position != oldPos:
					var undo = get_undo_redo()
					undo.create_action("Change position of %s to %s" % [selectedVector.name, selectedVector.position])
					undo.add_do_property(selectedVector, "position", selectedVector.position)
					undo.add_undo_property(selectedVector, "position", oldPos)
					undo.commit_action(false)
					
				moveGrabbed = false
				grabbed = false
				return false

		if grabbed or moveGrabbed:
			mouseEv = event as InputEventMouseMotion
			if mouseEv:
				if grabbed:
					# Update direction — snap to 4px grid when Ctrl/Cmd is held
					var newPos = selectedVector.get_viewport().get_screen_transform().affine_inverse() * mouseEv.global_position
					if mouseEv.is_command_or_control_pressed():
						selectedVector.direction = selectedVector.to_local(newPos.snapped(grid_snap))
					else:
						selectedVector.direction = selectedVector.to_local(newPos)
				else: # or moveGrabbed
					# Update position — snap to 4px grid when Ctrl/Cmd is held
					var newPos = (selectedVector.get_viewport().get_screen_transform().affine_inverse() * mouseEv.global_position) - mouseOffset
					selectedVector.global_position = newPos if !mouseEv.is_command_or_control_pressed() else newPos.snapped(grid_snap)
	elif event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		# No vector selected: try to select one by clicking on its arrow
		return _check_select_vectors(event.global_position)

	return false


func _input(event: InputEvent) -> void:
	# When no vector is selected, listen for clicks in the 2D viewport
	# to allow selecting a vector by clicking on its arrow
	if !selectedVector:
		var mouseEv = event as InputEventMouseButton
		if mouseEv and mouseEv.pressed and mouseEv.button_index == MOUSE_BUTTON_LEFT and EditorInterface.get_editor_viewport_2d().get_parent().get_global_rect().has_point(mouseEv.global_position):
			if _check_select_vectors(mouseEv.global_position):
				grabbed = false
				moveGrabbed = false
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
		if is_node_editable(v) and _point_on_arrow(worldPos, v):
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(v)
			return true

	return false
	
func _point_on_arrow(point: Vector2, v: RoxyVector2D) -> bool:
	var arrow_scale_avg = (absf(v.global_scale.x) + absf(v.global_scale.y))/2.0
	return Geometry2D.get_closest_point_to_segment(point, v.global_position, v.to_global(v.direction)).distance_squared_to(point) < (pow(v.real_arrow_width()*arrow_scale_avg,2)*1.5)

func _on_project_settings_update() -> void:
	_redraw_scene_vectors()
	
func _update_grid_snap() ->void:
	if ProjectSettings.has_setting(roxyvector2d_settings.PROJECT_SETTINGS_GRID_SNAP_STEP):
		grid_snap = ProjectSettings.get_setting_with_override(roxyvector2d_settings.PROJECT_SETTINGS_GRID_SNAP_STEP)
	else:
		grid_snap = roxyvector2d_settings.PROJECT_SETTINGS_GRID_SNAP_STEP_VALUE

func _redraw_scene_vectors() -> void:
	var sceneRoot := EditorInterface.get_edited_scene_root() as Node
	if !sceneRoot:
		return
	var roxyVectors = sceneRoot.find_children("*", "RoxyVector2D", true)

	# Include the root node itself if it is a RoxyVector2D
	if sceneRoot is RoxyVector2D:
		roxyVectors.push_front(sceneRoot)

	for rawv in roxyVectors:
		var v = rawv as CanvasItem
		v.queue_redraw()

func _exit_tree() -> void:
	editorSelectionObj.selection_changed.disconnect(_on_selection_changed)
	ProjectSettings.settings_changed.disconnect(_on_project_settings_update)
	if is_instance_valid(selectedVector):
		selectedVector.direction_changed.disconnect(update_overlays)
	
# Check if node is in editable scene instance or owe to the current scene
func is_node_editable(node: Node) -> bool:
	var scene_root = EditorInterface.get_edited_scene_root()
	var current = node
	while current != scene_root and current != null:
		if current.scene_file_path != "":
			# current is the root of an instiate scene
			return scene_root.is_editable_instance(current)
		current = current.get_parent()
	return true # node own to current edited scene
