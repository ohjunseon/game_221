extends Node3D
## 물류센터 전체: 마당, 창고 4동, 소품, "와르르" 이벤트.

const WAREHOUSE_DISTANCE := 26.0
const GROUND_SIZE := 220.0
const PLAZA_SIZE := 72.0
const MODEL_DIR := "res://assets/models/factory/"
const WAREUREU_TOYS := 240
const WAREUREU_PER_FRAME := 3

var warehouses: Array[Warehouse] = []

var _wareureu_left: int = 0


func _ready() -> void:
	_build_ground()
	_build_warehouses()
	_build_props()
	_build_scenery()
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
	# 충돌은 큰 판 하나(윗면 y=0). 보이는 것은 잔디와 그 위의 포장된 마당이다.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(GROUND_SIZE, 1.0, GROUND_SIZE)
	shape.shape = box_shape
	body.add_child(shape)
	body.position = Vector3(0.0, -0.5, 0.0)
	add_child(body)
	_deco(
		Vector3(GROUND_SIZE, 0.1, GROUND_SIZE), Vector3(0.0, -0.1, 0.0),
		Look.grid(Color(0.6, 0.84, 0.5), Color(0.54, 0.79, 0.46), 4.0)
	)
	_deco(
		Vector3(PLAZA_SIZE + 1.0, 0.1, PLAZA_SIZE + 1.0), Vector3(0.0, -0.08, 0.0),
		Look.matte(Color(0.97, 0.96, 0.92))
	)
	_deco(
		Vector3(PLAZA_SIZE, 0.1, PLAZA_SIZE), Vector3(0.0, -0.06, 0.0),
		Look.grid(Color(0.7, 0.73, 0.82), Color(0.62, 0.65, 0.75), 2.0)
	)
	# 노란 차선
	for i in 4:
		var line := _box(Vector3(0.3, 0.02, 14.0), Vector3(0.0, 0.01, -10.0), Color(0.95, 0.8, 0.2), false)
		line.rotation.y = i * PI / 2.0
		line.position = Vector3(0.0, 0.01, -10.0).rotated(Vector3.UP, i * PI / 2.0)


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
	# 컨베이어 라인 2개: 벨트 3칸, 위에 박스, 스캐너, 끝에 로봇 팔
	for side: float in [1.0, -1.0]:
		var z := -11.0 * side
		for i in 3:
			_prop("conveyor-long-stripe-sides", Vector3((7.0 + 3.0 * i) * side, 0.0, z))
		_solid(Vector3(9.0, 0.6, 1.5), Vector3(10.0 * side, 0.0, z))
		for x: float in [6.4, 8.8, 11.6, 13.6]:
			_prop("box-small", Vector3(x * side, 0.6, z), x, 0.9)
		_prop("scanner-high", Vector3(10.2 * side, 0.0, z), PI / 2.0)
		_prop("robot-arm-a" if side > 0.0 else "robot-arm-b", Vector3(15.6 * side, 0.0, z), 0.0, 1.8)
		_solid(Vector3(1.4, 1.8, 1.4), Vector3(15.6 * side, 0.0, z))

	# 크레인과 기계
	_prop("crane", Vector3(-12.0, 0.0, -12.0), PI / 4.0, 1.8)
	_solid(Vector3(2.4, 6.0, 2.4), Vector3(-12.0, 0.0, -12.0))
	_prop("machine-window", Vector3(12.0, 0.0, 12.0), -PI / 4.0, 2.0)
	_solid(Vector3(2.4, 2.6, 3.0), Vector3(12.0, 0.0, 12.0), -PI / 4.0)
	_prop("screen-wide", Vector3(9.0, 0.0, 14.5), -PI / 4.0, 1.6)
	_prop("cog-a", Vector3(14.5, 0.3, 9.0), 0.4, 1.4)

	# 박스 더미
	var stacks: Array[Vector3] = [
		Vector3(-6.0, 0.0, -6.5), Vector3(-15.5, 0.0, -6.0), Vector3(-6.5, 0.0, -15.5),
		Vector3(6.0, 0.0, 6.5), Vector3(6.5, 0.0, -5.5), Vector3(-15.5, 0.0, 6.5),
		Vector3(16.0, 0.0, -16.0), Vector3(-16.0, 0.0, 16.0),
	]
	var models: Array[String] = ["box-large", "box-wide", "box-long", "box-small"]
	for index in stacks.size():
		var levels := 1 + index % 3
		for level in levels:
			_prop(
				models[(index + level) % models.size()],
				stacks[index] + Vector3(0.0, 0.6 * level, 0.0),
				index * 0.7 + level * 0.3,
				1.1
			)
		_solid(Vector3(1.2, 0.6 * levels, 1.1), stacks[index])

	# 문마다 양옆에 경고등과 고깔
	for i in warehouses.size():
		for lateral: float in [-1.0, 1.0]:
			var angle := -i * PI / 2.0
			var wall := WAREHOUSE_DISTANCE - Warehouse.DEPTH / 2.0
			_prop(
				"warning-traffic",
				Vector3(3.3 * lateral, 0.0, -wall + 0.9).rotated(Vector3.UP, angle), angle, 1.5
			)
			_prop("cone", Vector3(2.8 * lateral, 0.0, -wall + 2.2).rotated(Vector3.UP, angle), 0.0, 1.6)


## 마당 밖 풍경: 나무와 구름 (충돌 없음)
func _build_scenery() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 221
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.26
	trunk_mesh.height = 1.8
	trunk_mesh.radial_segments = 6
	var leaf_mesh := SphereMesh.new()
	leaf_mesh.radial_segments = 7
	leaf_mesh.rings = 4
	var trunk := Look.matte(Color(0.56, 0.4, 0.27))
	var greens: Array[Color] = [Color(0.38, 0.72, 0.42), Color(0.5, 0.8, 0.42), Color(0.3, 0.64, 0.44)]
	for side in 4:
		for i in 12:
			var tree := Node3D.new()
			tree.position = Vector3(
				-44.0 + 8.0 * i + random.randf_range(-1.5, 1.5),
				0.0,
				PLAZA_SIZE / 2.0 + random.randf_range(3.0, 10.0)
			).rotated(Vector3.UP, side * PI / 2.0)
			tree.scale = Vector3.ONE * random.randf_range(1.0, 1.8)
			add_child(tree)
			var stem := MeshInstance3D.new()
			stem.mesh = trunk_mesh
			stem.material_override = trunk
			stem.position.y = 0.9
			tree.add_child(stem)
			var green := Look.matte(greens[random.randi() % greens.size()])
			for puff: Array in [[2.4, 2.6], [3.6, 1.8]]:
				var leaf := MeshInstance3D.new()
				leaf.mesh = leaf_mesh
				leaf.material_override = green
				leaf.position.y = puff[0]
				leaf.scale = Vector3(puff[1], puff[1] * 0.85, puff[1])
				tree.add_child(leaf)

	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(1.0, 1.0, 1.0)
	white.disable_fog = true
	for i in 16:
		var cloud := Node3D.new()
		cloud.position = Vector3(
			random.randf_range(-160.0, 160.0), random.randf_range(45.0, 75.0),
			random.randf_range(-160.0, 160.0)
		)
		add_child(cloud)
		for part in 4:
			var puff := MeshInstance3D.new()
			puff.mesh = leaf_mesh
			puff.material_override = white
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			puff.position = Vector3(part * 6.0 - 9.0, random.randf_range(-1.0, 1.5), random.randf_range(-2.0, 2.0))
			puff.scale = Vector3(random.randf_range(9.0, 14.0), random.randf_range(4.0, 6.0), random.randf_range(7.0, 10.0))
			cloud.add_child(puff)


## Kenney Factory Kit 모델 하나를 놓는다 (충돌 없음, 필요하면 _solid를 따로 둔다).
func _prop(model: String, at: Vector3, yaw: float = 0.0, size: float = 1.5) -> Node3D:
	var scene: PackedScene = load(MODEL_DIR + model + ".glb")
	var node: Node3D = scene.instantiate()
	node.position = at
	node.rotation.y = yaw
	node.scale = Vector3.ONE * size
	add_child(node)
	return node


## 보이지 않는 충돌 상자. at은 바닥 가운데다.
func _solid(size: Vector3, at: Vector3, yaw: float = 0.0) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.position = at + Vector3(0.0, size.y / 2.0, 0.0)
	body.rotation.y = yaw
	add_child(body)


## 충돌 없는 장식용 상자
func _deco(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = material
	mesh.position = at
	add_child(mesh)
	return mesh


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
