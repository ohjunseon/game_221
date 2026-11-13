class_name Warehouse
extends Node3D
## 창고 한 동: 벽, 문, 2개 층(뒷벽 경사로), 층마다 양쪽 벽에 선반 5개씩, 바닥에 흩어진 장난감.
## 문은 로컬 +Z 방향에 있다.

const WIDTH := 18.0
const DEPTH := 14.0
const WALL_HEIGHT := 8.0
const FLOOR_HEIGHT := 4.0
const DOOR_WIDTH := 4.0
const DOOR_HEIGHT := 3.5
const WALL_THICKNESS := 0.4
const SLAB_THICKNESS := 0.3
## 경사로: 뒷벽을 따라 +X(아래)에서 -X(위)로 올라간다
const RAMP_HALF_RUN := 5.0
const RAMP_DEPTH := 2.5
const SHELF_SPACING := 2.2
const SHELF_FIRST_Z := 3.6
const SHELVES_PER_SIDE := 5
const TOY_TARGET := 90
const TOY_COLLIDER := 0.3
const TOY_LAYER := 2
const SPAWN_HALF_X := 6.5
const SPAWN_Z_MIN := -3.5
const SPAWN_Z_MAX := 6.0
const WALL_COLORS := {
	1: Color(0.55, 0.68, 0.85),
	2: Color(0.6, 0.8, 0.6),
	3: Color(0.9, 0.75, 0.5),
	4: Color(0.85, 0.55, 0.6),
}

static var _toy_shape: BoxShape3D

var warehouse_id: int = 1
var is_open: bool = false
var shelves: Array[Shelf] = []

var _door: StaticBody3D
var _door_material: StandardMaterial3D
var _status_label: Label3D
var _gate: StaticBody3D
var _toy_roots: Array[Node3D] = []
var _door_tween: Tween


## 바닥에 놓이는 장난감 하나. rigid면 물리로 굴러다닌다(와르르용). type이 -1이면 무작위.
static func make_toy(rigid: bool, type: int = -1) -> CollisionObject3D:
	if _toy_shape == null:
		_toy_shape = BoxShape3D.new()
		_toy_shape.size = Vector3.ONE * TOY_COLLIDER
	if type < 0:
		type = Toys.random_type()
	var body: CollisionObject3D
	if rigid:
		body = RigidBody3D.new()
		body.collision_mask = 1
	else:
		body = StaticBody3D.new()
		body.collision_mask = 0
	body.collision_layer = TOY_LAYER
	body.add_to_group("toy")
	body.set_meta("toy_type", type)

	var shape := CollisionShape3D.new()
	shape.shape = _toy_shape
	shape.position.y = TOY_COLLIDER / 2.0
	body.add_child(shape)
	body.add_child(Toys.make_visual(type))
	return body


func _ready() -> void:
	_build_shell()
	_build_upper_floor()
	_build_shelves()
	_build_door()
	_build_signs()
	_build_lights()
	for floor_index in GameState.FLOORS_PER_WAREHOUSE:
		var root := Node3D.new()
		root.name = "Toys%d" % (floor_index + 1)
		add_child(root)
		_toy_roots.append(root)

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_refill)
	add_child(timer)

	EventBus.warehouse_unlocked.connect(func(_id: int) -> void: _refresh())
	EventBus.shelf_completed.connect(_on_shelf_completed)
	if warehouse_id == 1:
		set_door_open(true, false)
	_refresh()
	_refill()


func toggle_door() -> void:
	if not GameState.is_warehouse_unlocked(warehouse_id):
		EventBus.message_shown.emit(
			"잠김: %s개 정리하면 열립니다" % Skills.fmt(GameState.unlock_threshold(warehouse_id))
		)
		Sfx.play("error")
		return
	set_door_open(not is_open)


func set_door_open(open: bool, animate: bool = true) -> void:
	is_open = open
	var target_y := DOOR_HEIGHT / 2.0 + (DOOR_HEIGHT - 0.1 if open else 0.0)
	if _door_tween != null:
		_door_tween.kill()
	if animate:
		_door_tween = create_tween()
		_door_tween.tween_property(_door, "position:y", target_y, 0.6)
		Sfx.play("door")
	else:
		_door.position.y = target_y
	if open:
		GameState.mark_door_opened(warehouse_id)
	EventBus.door_toggled.emit(warehouse_id, open)
	_refresh()


## 문 바로 바깥의 월드 좌표 (와르르에서 장난감이 쏟아지는 위치)
func door_outside_position() -> Vector3:
	return to_global(Vector3(0.0, 1.5, DEPTH / 2.0 + 1.0))


func _on_shelf_completed(completed_warehouse: int, _floor_index: int, _shelf_index: int) -> void:
	if completed_warehouse == warehouse_id:
		_refresh()


func _refresh() -> void:
	var unlocked := GameState.is_warehouse_unlocked(warehouse_id)
	_door_material.albedo_color = Color(0.3, 0.75, 0.4) if unlocked else Color(0.8, 0.25, 0.25)
	if not unlocked:
		_status_label.text = "잠김 · %s개 정리 필요" % Skills.fmt(
			GameState.unlock_threshold(warehouse_id)
		)
	elif GameState.is_floor_complete(warehouse_id, 1):
		_status_label.text = "정리 완료!"
	elif is_open:
		_status_label.text = "열림"
	else:
		_status_label.text = "닫힘 · 클릭해서 열기"
	if _gate != null and GameState.is_floor_complete(warehouse_id, 0):
		_gate.queue_free()
		_gate = null


func _refill() -> void:
	for floor_index in _toy_roots.size():
		var root := _toy_roots[floor_index]
		var active := (
			GameState.is_floor_active(warehouse_id, floor_index)
			and not GameState.is_floor_complete(warehouse_id, floor_index)
		)
		var alive := 0
		for toy in root.get_children():
			if toy.is_queued_for_deletion():
				continue
			if active:
				alive += 1
			else:
				toy.remove_from_group("toy")
				toy.queue_free()
		if not active:
			continue
		for i in TOY_TARGET - alive:
			var toy := make_toy(false)
			toy.position = Vector3(
				randf_range(-SPAWN_HALF_X, SPAWN_HALF_X),
				floor_index * FLOOR_HEIGHT,
				randf_range(SPAWN_Z_MIN, SPAWN_Z_MAX)
			)
			toy.rotation.y = randf() * TAU
			root.add_child(toy)


func _build_shell() -> void:
	var wall := _material(WALL_COLORS.get(warehouse_id, Color(0.7, 0.7, 0.7)))
	var floor_material := _material(Color(0.62, 0.62, 0.6))
	_box(Vector3(WIDTH + 2.0, 0.2, DEPTH + 2.0), Vector3(0.0, -0.1, 0.0), floor_material)

	var half_h := WALL_HEIGHT / 2.0
	_box(Vector3(WIDTH, WALL_HEIGHT, WALL_THICKNESS), Vector3(0.0, half_h, -DEPTH / 2.0), wall)
	_box(Vector3(WALL_THICKNESS, WALL_HEIGHT, DEPTH), Vector3(-WIDTH / 2.0, half_h, 0.0), wall)
	_box(Vector3(WALL_THICKNESS, WALL_HEIGHT, DEPTH), Vector3(WIDTH / 2.0, half_h, 0.0), wall)

	var side_width := (WIDTH - DOOR_WIDTH) / 2.0
	var side_x := DOOR_WIDTH / 2.0 + side_width / 2.0
	for x: float in [-side_x, side_x]:
		_box(Vector3(side_width, WALL_HEIGHT, WALL_THICKNESS), Vector3(x, half_h, DEPTH / 2.0), wall)
	var lintel_height := WALL_HEIGHT - DOOR_HEIGHT
	_box(
		Vector3(DOOR_WIDTH, lintel_height, WALL_THICKNESS),
		Vector3(0.0, DOOR_HEIGHT + lintel_height / 2.0, DEPTH / 2.0),
		wall
	)


func _build_upper_floor() -> void:
	var slab := _material(Color(0.5, 0.52, 0.56))
	var slab_y := FLOOR_HEIGHT - SLAB_THICKNESS / 2.0
	var ramp_front_z := -DEPTH / 2.0 + RAMP_DEPTH
	var ramp_center_z := -DEPTH / 2.0 + RAMP_DEPTH / 2.0
	# 경사로 구멍을 뺀 2층 바닥: 앞쪽 큰 판 + 뒷벽 양쪽 모서리
	var main_depth := DEPTH / 2.0 - ramp_front_z
	_box(
		Vector3(WIDTH, SLAB_THICKNESS, main_depth),
		Vector3(0.0, slab_y, ramp_front_z + main_depth / 2.0),
		slab
	)
	var corner_width := WIDTH / 2.0 - RAMP_HALF_RUN
	for side: float in [-1.0, 1.0]:
		_box(
			Vector3(corner_width, SLAB_THICKNESS, RAMP_DEPTH),
			Vector3(side * (RAMP_HALF_RUN + corner_width / 2.0), slab_y, ramp_center_z),
			slab
		)

	var run := RAMP_HALF_RUN * 2.0
	var ramp := _box(
		Vector3(sqrt(run * run + FLOOR_HEIGHT * FLOOR_HEIGHT), SLAB_THICKNESS, RAMP_DEPTH),
		Vector3(0.0, FLOOR_HEIGHT / 2.0 - SLAB_THICKNESS / 2.0, ramp_center_z),
		_material(Color(0.85, 0.7, 0.2))
	)
	ramp.rotation.z = -atan2(FLOOR_HEIGHT, run)

	_gate = _box(
		Vector3(0.2, 2.2, RAMP_DEPTH),
		Vector3(RAMP_HALF_RUN + 0.3, 1.1, ramp_center_z),
		_material(Color(0.8, 0.25, 0.25))
	)
	var gate_label := Label3D.new()
	gate_label.text = "1층을 모두 정리하면\n2층이 열립니다"
	gate_label.font_size = 48
	gate_label.pixel_size = 0.005
	gate_label.position = Vector3(0.12, 0.2, 0.0)
	gate_label.rotation.y = PI / 2.0
	_gate.add_child(gate_label)


## 선반 0~4는 왼쪽 벽, 5~9는 오른쪽 벽. 문에 가까운 쪽부터 작은 선반이다.
func _build_shelves() -> void:
	for floor_index in GameState.FLOORS_PER_WAREHOUSE:
		for shelf_index in GameState.SHELVES_PER_FLOOR:
			var on_left := shelf_index < SHELVES_PER_SIDE
			var slot := shelf_index % SHELVES_PER_SIDE
			var shelf := Shelf.new()
			shelf.name = "Shelf_%d_%d" % [floor_index + 1, shelf_index + 1]
			shelf.warehouse_id = warehouse_id
			shelf.floor_index = floor_index
			shelf.shelf_index = shelf_index
			shelf.position = Vector3(
				(-1.0 if on_left else 1.0) * (WIDTH / 2.0 - 0.7),
				floor_index * FLOOR_HEIGHT,
				SHELF_FIRST_Z - SHELF_SPACING * slot
			)
			# 선반 앞면(로컬 +Z)이 창고 안쪽을 보게 한다
			shelf.rotation.y = PI / 2.0 if on_left else -PI / 2.0
			add_child(shelf)
			shelves.append(shelf)


func _build_door() -> void:
	_door_material = StandardMaterial3D.new()
	_door = _box(
		Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.2),
		Vector3(0.0, DOOR_HEIGHT / 2.0, DEPTH / 2.0),
		_door_material
	)
	_door.add_to_group("door")
	_door.set_meta("warehouse", self)


func _build_signs() -> void:
	var title := Label3D.new()
	title.text = "창고 %d" % warehouse_id
	title.font_size = 160
	title.outline_size = 24
	title.pixel_size = 0.012
	title.position = Vector3(0.0, DOOR_HEIGHT + 2.4, DEPTH / 2.0 + 0.3)
	add_child(title)

	_status_label = Label3D.new()
	_status_label.font_size = 72
	_status_label.outline_size = 16
	_status_label.pixel_size = 0.01
	_status_label.position = Vector3(0.0, DOOR_HEIGHT + 0.9, DEPTH / 2.0 + 0.3)
	add_child(_status_label)


func _build_lights() -> void:
	for x: float in [-WIDTH / 4.0, WIDTH / 4.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, FLOOR_HEIGHT - 0.8, 1.0)
		light.omni_range = 14.0
		light.light_energy = 1.8
		add_child(light)


func _box(size: Vector3, at: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = material
	body.add_child(mesh)
	body.position = at
	add_child(body)
	return body


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
