@tool
extends Node3D

@export_group("Target")
@export var target: MultiMeshInstance3D:
	get:
		return _target
	set(value):
		_switch_target(value)

@export_group("Brush")
@export_range(1, 200, 1) var instances_per_stamp := 16
@export_range(0.05, 50.0, 0.05) var brush_radius := 1.5
@export_range(0.05, 50.0, 0.05) var erase_radius := 1.75
@export_range(0.0, 100.0, 0.1) var minimum_spacing := 0.18
@export var allow_overpaint := false
@export_range(1.0, 120.0, 1.0) var max_slope_degrees := 45.0
@export var surface_offset := 0.0

@export_group("Variation")
@export var random_y_rotation := true
@export var align_to_normal := true
@export_range(0.0, 45.0, 0.1) var tilt_variance := 8.0
@export var random_scale := true
@export_range(0.01, 10.0, 0.01) var scale_min := 0.75
@export_range(0.01, 10.0, 0.01) var scale_max := 1.25

@export_group("Natural Noise")
@export var use_scale_noise := true
@export var noise_seed := 1337
@export_range(0.0001, 2.0, 0.0001) var noise_frequency := 0.16
@export_range(0.0, 1.0, 0.01) var noise_strength := 0.45
@export_range(0.01, 10.0, 0.01) var noise_scale_min := 0.7
@export_range(0.01, 10.0, 0.01) var noise_scale_max := 1.25
@export var use_density_noise := true
@export_range(0.0, 1.0, 0.01) var density_noise_min := 0.45
@export_range(0.0, 1.0, 0.01) var density_noise_max := 0.95

@export_group("Actions")
@export var clear_instances := false:
	set(value):
		if value and Engine.is_editor_hint():
			_clear()
		clear_instances = false

var erase_mode := false
var _xforms: Array[Transform3D] = []
var _undo_redo: EditorUndoRedoManager
var _target: MultiMeshInstance3D
var _loaded := false
var _noise := FastNoiseLite.new()
var _flush_queued := false

func _ready() -> void:
	call_deferred("_initialize")

func _initialize() -> void:
	if not Engine.is_editor_hint() or _loaded:
		return
	_loaded = true
	_make_multimesh_unique()
	if is_instance_valid(_target) and _target.multimesh:
		_import_multimesh()

func set_undo_redo(value: EditorUndoRedoManager) -> void:
	_undo_redo = value

func get_transform_data() -> PackedFloat32Array:
	return _encode_transform_data()

func paint(camera: Camera3D, screen_pos: Vector2) -> bool:
	if not _check_target():
		return false
	var hit := _raycast(camera, screen_pos)
	if hit.is_empty():
		return false
	if erase_mode:
		_erase(hit.position)
	else:
		for i in instances_per_stamp:
			_add_instance(hit.position)
		_queue_flush()
	return true

func commit_edit(action_name: String, before: PackedFloat32Array) -> void:
	var after := get_transform_data()
	if before == after:
		return
	if _undo_redo:
		_undo_redo.create_action(action_name)
		_undo_redo.add_do_method(self, "_apply_transform_data", after)
		_undo_redo.add_undo_method(self, "_apply_transform_data", before)
		_undo_redo.commit_action(false)
	else:
		_apply_transform_data(after)

func _apply_transform_data(data: PackedFloat32Array) -> void:
	_decode_transform_data(data)
	_flush()

func _switch_target(value: MultiMeshInstance3D) -> void:
	if value == _target:
		return
	_target = value
	if not is_inside_tree():
		return
	_xforms.clear()
	if is_instance_valid(_target) and _target.multimesh:
		_make_multimesh_unique()
		_import_multimesh()

func _make_multimesh_unique() -> void:
	if is_instance_valid(_target) and _target.multimesh:
		_target.multimesh = _target.multimesh.duplicate(true) as MultiMesh

func _add_instance(center: Vector3) -> void:
	var angle := randf() * TAU
	var distance := sqrt(randf()) * brush_radius
	var sample := center + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	if use_density_noise and randf() > _density_at(sample):
		return
	var hit := _drop_to_surface(sample)
	if hit.is_empty() or hit.normal.angle_to(Vector3.UP) > deg_to_rad(max_slope_degrees):
		return
	var local_position := _target.to_local(hit.position + hit.normal * surface_offset)
	if not allow_overpaint:
		for existing in _xforms:
			if existing.origin.distance_squared_to(local_position) < minimum_spacing * minimum_spacing:
				return
	var basis := Basis.IDENTITY
	if align_to_normal:
		var local_normal: Vector3 = _target.global_transform.basis.inverse() * (hit.normal as Vector3)
		basis = _normal_basis(local_normal)
	if random_y_rotation:
		basis = basis.rotated(basis.y.normalized(), randf() * TAU)
	if tilt_variance > 0.0:
		basis = basis.rotated(basis.x.normalized(), deg_to_rad(randf_range(-tilt_variance, tilt_variance)))
		basis = basis.rotated(basis.z.normalized(), deg_to_rad(randf_range(-tilt_variance, tilt_variance)))
	var scale_factor := 1.0
	if random_scale:
		scale_factor *= randf_range(min(scale_min, scale_max), max(scale_min, scale_max))
	if use_scale_noise:
		scale_factor *= lerp(1.0, _scale_noise_at(hit.position), noise_strength)
	basis = basis.scaled(Vector3.ONE * scale_factor)
	_xforms.append(Transform3D(basis, local_position))

func _erase(global_center: Vector3) -> void:
	var local_center := _target.to_local(global_center)
	var radius_squared := erase_radius * erase_radius
	var kept: Array[Transform3D] = []
	for transform in _xforms:
		if transform.origin.distance_squared_to(local_center) > radius_squared:
			kept.append(transform)
	if kept.size() != _xforms.size():
		_xforms = kept
		_queue_flush()

func _clear() -> void:
	if not _check_target(): return
	var before := get_transform_data()
	_xforms.clear()
	_flush()
	commit_edit("Clear Foliage", before)

func _flush() -> void:
	if not is_instance_valid(_target) or not _target.multimesh:
		return
	var multimesh := _target.multimesh
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = _xforms.size()
	for i in _xforms.size():
		multimesh.set_instance_transform(i, _xforms[i])
	multimesh.emit_changed()
	_target.notify_property_list_changed()

func _queue_flush() -> void:
	if _flush_queued:
		return
	_flush_queued = true
	call_deferred("_flush_deferred")

func _flush_deferred() -> void:
	_flush_queued = false
	_flush()

func _encode_transform_data() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(_xforms.size() * 12)
	var offset := 0
	for transform in _xforms:
		var b := transform.basis
		for value in [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, transform.origin.x, transform.origin.y, transform.origin.z]:
			data[offset] = value
			offset += 1
	return data

func _scale_noise_at(world_position: Vector3) -> float:
	_noise.seed = noise_seed
	_noise.frequency = noise_frequency
	var amount := (_noise.get_noise_2d(world_position.x, world_position.z) + 1.0) * 0.5
	return lerp(min(noise_scale_min, noise_scale_max), max(noise_scale_min, noise_scale_max), amount)

func _density_at(world_position: Vector3) -> float:
	_noise.seed = noise_seed + 7919
	_noise.frequency = noise_frequency
	var amount := (_noise.get_noise_2d(world_position.x, world_position.z) + 1.0) * 0.5
	return lerp(min(density_noise_min, density_noise_max), max(density_noise_min, density_noise_max), amount)

func _decode_transform_data(data: PackedFloat32Array) -> void:
	_xforms.clear()
	if data.size() % 12 != 0:
		push_error("FoliageFlow: undo data is corrupt.")
		return
	for offset in range(0, data.size(), 12):
		var basis := Basis(Vector3(data[offset], data[offset + 1], data[offset + 2]), Vector3(data[offset + 3], data[offset + 4], data[offset + 5]), Vector3(data[offset + 6], data[offset + 7], data[offset + 8]))
		_xforms.append(Transform3D(basis, Vector3(data[offset + 9], data[offset + 10], data[offset + 11])))

func _import_multimesh() -> void:
	for i in _target.multimesh.instance_count:
		_xforms.append(_target.multimesh.get_instance_transform(i))

func _raycast(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var state := get_world_3d().direct_space_state
	var result := state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * 10000.0))
	return {} if result.is_empty() else {"position": result.position}

func _drop_to_surface(point: Vector3) -> Dictionary:
	var state := get_world_3d().direct_space_state
	var result := state.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 500.0, point + Vector3.DOWN * 1000.0))
	return {} if result.is_empty() else {"position": result.position, "normal": result.normal}

func _check_target() -> bool:
	if not is_instance_valid(_target) or not _target.multimesh or not _target.multimesh.mesh:
		push_warning("FoliageFlow: Target requires a MultiMeshInstance3D with a MultiMesh and Mesh.")
		return false
	return true

func _normal_basis(normal: Vector3) -> Basis:
	var up := normal.normalized()
	var tangent := Vector3.FORWARD.cross(up)
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.RIGHT.cross(up)
	tangent = tangent.normalized()
	return Basis(tangent, up, tangent.cross(up).normalized())
