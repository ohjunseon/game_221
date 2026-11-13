extends Node3D
## 물류센터 전체: 마당, 창고 4동, 소품, "와르르" 이벤트.

const WAREHOUSE_DISTANCE := 40.0
const GROUND_SIZE := 220.0
const WAREUREU_TOYS := 240
const WAREUREU_PER_FRAME := 3

var warehouses: Array[Warehouse] = []

var _wareureu_left: int = 0


func _ready() -> void:
	_build_ground()
	_build_warehouses()
	_build_props()
	EventBus.warehouse_unlocked.connect(_on_warehouse_unlocked)


func _process(_delta: float) -> void:
	if _wareureu_left <= 0:
		return
	var source := warehouses[3]
	var outward := source.global_basis.z
	var sideways := source.global_basis.x
	for i in mini(WAREUREU_PER_FRAME, _wareureu_left):
		var toy := Warehouse.make_toy(true) as RigidBody3D
		add_child(toy)
		toy.global_position = (
			source.door_outside_position()
			+ sideways * randf_range(-1.5, 1.5)
			+ Vector3.UP * randf_range(-0.8, 1.5)
		)
		toy.linear_velocity = (
			outward * randf_range(4.0, 12.0)
			+ sideways * randf_range(-3.0, 3.0)
			+ Vector3.UP * randf_range(1.0, 5.0)
		)
		_wareureu_left -= 1
	EventBus.shake_requested.emit(0.8)


## 1만 개 달성: 창고 4의 문이 열리며 장난감이 마당으로 쏟아진다.
func start_wareureu() -> void:
	GameState.wareureu_done = true
	warehouses[3].set_door_open(true)
	_wareureu_left = WAREUREU_TOYS
	EventBus.message_shown.emit("와르르~~~! 창고 4에서 장난감이 쏟아집니다!")
	EventBus.shake_requested.emit(2.5)
	Sfx.play("rumble")


func _on_warehouse_unlocked(warehouse_id: int) -> void:
	Sfx.play("unlock")
	EventBus.shake_requested.emit(0.6)
	EventBus.message_shown.emit("창고 %d 개방!" % warehouse_id)
	if warehouse_id == 4 and not GameState.wareureu_done:
		start_wareureu()


func _build_ground() -> void:
	_box(
		Vector3(GROUND_SIZE, 1.0, GROUND_SIZE), Vector3(0.0, -0.5, 0.0), Color(0.36, 0.38, 0.4), true
	)
	# 노란 차선
	for i in 4:
		var line := _box(Vector3(0.3, 0.02, 24.0), Vector3(0.0, 0.01, -14.0), Color(0.95, 0.8, 0.2), false)
		line.rotation.y = i * PI / 2.0
		line.position = Vector3(0.0, 0.01, -14.0).rotated(Vector3.UP, i * PI / 2.0)


func _build_warehouses() -> void:
	# 문(로컬 +Z)이 마당 가운데를 향하도록 돌려 놓는다.
	var placements: Array = [
		[Vector3(0.0, 0.0, -WAREHOUSE_DISTANCE), 0.0],
		[Vector3(WAREHOUSE_DISTANCE, 0.0, 0.0), -PI / 2.0],
		[Vector3(0.0, 0.0, WAREHOUSE_DISTANCE), PI],
		[Vector3(-WAREHOUSE_DISTANCE, 0.0, 0.0), PI / 2.0],
	]
	for i in placements.size():
		var warehouse := Warehouse.new()
		warehouse.name = "Warehouse%d" % (i + 1)
		warehouse.warehouse_id = i + 1
		warehouse.position = placements[i][0]
		warehouse.rotation.y = placements[i][1]
		add_child(warehouse)
		warehouses.append(warehouse)


func _build_props() -> void:
	# 팔레트와 박스 더미
	var spots: Array[Vector3] = [
		Vector3(8.0, 0.0, -8.0), Vector3(-9.0, 0.0, -7.0), Vector3(10.0, 0.0, 9.0),
		Vector3(-8.0, 0.0, 10.0), Vector3(16.0, 0.0, -16.0), Vector3(-16.0, 0.0, 16.0),
	]
	for spot in spots:
		_box(Vector3(1.4, 0.15, 1.2), spot + Vector3(0.0, 0.075, 0.0), Color(0.6, 0.45, 0.25), true)
		for level in 1 + randi() % 3:
			_box(
				Vector3(1.0, 0.8, 0.9),
				spot + Vector3(randf_range(-0.1, 0.1), 0.55 + 0.8 * level, 0.0),
				Color(0.78, 0.6, 0.38),
				true
			)


func _box(size: Vector3, at: Vector3, color: Color, collide: bool) -> Node3D:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	if not collide:
		mesh.position = at
		add_child(mesh)
		return mesh
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.add_child(mesh)
	body.position = at
	add_child(body)
	return body
