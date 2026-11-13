extends Node3D
## 창고 한 층: 선반 줄을 세우고, 바닥에 흩어진 장난감을 일정 수로 유지한다.
## 장난감 전체 물량은 숫자로 관리하고, 바닥에는 toy_target 개만 보여 준다.

const TOY_SIZE := 0.25
const TOY_LAYER := 2
const TOY_COLORS: Array[Color] = [
	Color(0.95, 0.3, 0.3),
	Color(0.3, 0.6, 0.95),
	Color(0.35, 0.8, 0.4),
	Color(0.98, 0.8, 0.25),
	Color(0.75, 0.45, 0.9),
	Color(0.98, 0.55, 0.2),
]

@export var shelf_count: int = 10
@export var shelf_tier_capacity: int = 10
@export var shelf_spacing: float = 3.0
@export var shelf_row_z: float = -16.0
@export var toy_target: int = 150
@export var spawn_half_width: float = 14.0
@export var spawn_z_min: float = -11.0
@export var spawn_z_max: float = 15.0

var shelves: Array[Shelf] = []

var _toys: Node3D
var _toy_shape: BoxShape3D
var _toy_mesh: BoxMesh
var _toy_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	_build_shelves()
	_prepare_toy_resources()
	_toys = Node3D.new()
	_toys.name = "Toys"
	add_child(_toys)
	_refill()

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_refill)
	add_child(timer)


func _build_shelves() -> void:
	var start_x := -shelf_spacing * (shelf_count - 1) / 2.0
	for i in shelf_count:
		var shelf := Shelf.new()
		shelf.name = "Shelf%d" % (i + 1)
		shelf.tier_capacity = shelf_tier_capacity
		shelf.shelf_index = i
		shelf.position = Vector3(start_x + shelf_spacing * i, 0.0, shelf_row_z)
		add_child(shelf)
		shelves.append(shelf)


func _prepare_toy_resources() -> void:
	_toy_shape = BoxShape3D.new()
	_toy_shape.size = Vector3.ONE * TOY_SIZE
	_toy_mesh = BoxMesh.new()
	_toy_mesh.size = Vector3.ONE * TOY_SIZE
	for color in TOY_COLORS:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		_toy_materials.append(material)


func _refill() -> void:
	var alive := 0
	for toy in _toys.get_children():
		if not toy.is_queued_for_deletion():
			alive += 1
	for i in toy_target - alive:
		_spawn_toy()


func _spawn_toy() -> void:
	var index := randi() % TOY_COLORS.size()
	var toy := StaticBody3D.new()
	toy.collision_layer = TOY_LAYER
	toy.collision_mask = 0
	toy.add_to_group("toy")
	toy.set_meta("color", TOY_COLORS[index])

	var shape := CollisionShape3D.new()
	shape.shape = _toy_shape
	toy.add_child(shape)

	var mesh := MeshInstance3D.new()
	mesh.mesh = _toy_mesh
	mesh.material_override = _toy_materials[index]
	toy.add_child(mesh)

	toy.position = Vector3(
		randf_range(-spawn_half_width, spawn_half_width),
		TOY_SIZE / 2.0,
		randf_range(spawn_z_min, spawn_z_max)
	)
	toy.rotation.y = randf() * TAU
	_toys.add_child(toy)
