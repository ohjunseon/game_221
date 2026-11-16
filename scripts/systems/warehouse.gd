class_name Warehouse
extends Node3D
## 창고 한 동: 벽, 문, 2개 층(뒷벽 경사로), 층마다 통로 양쪽에 선 선반 줄, 문 앞 입고장에 흩어진 장난감.
## 창고마다 한 층의 선반 수(GameState.SHELVES_PER_FLOOR)가 달라서 크기도 다르다.
## 문은 로컬 +Z 방향에 있다.

## 문이 있는 앞벽이 마당 가운데에서 떨어진 거리 (창고 크기와 상관없이 같다)
const DOOR_DISTANCE := 19.0
## 실제 창고식 배치: 통로가 문에서 안쪽으로 뻗고, 통로 양쪽에 선반 줄이 통로를 보고 선다.
## 이웃한 통로의 선반 줄은 등을 맞댄다. 통로 하나의 선반 수는 GameState.SHELVES_PER_AISLE.
const SHELF_PITCH := 2.1
const AISLE_WIDTH := 2.6
## 통로 가운데에서 다음 통로 가운데까지 (통로 폭 + 등 맞댄 선반 두 줄 + 틈)
const AISLE_PITCH := 3.7
## 한 줄의 선반이 이보다 많으면 줄 가운데에 가로 통로를 둔다
const CROSS_AISLE_BAYS := 5
const CROSS_AISLE_WIDTH := 2.6
const MIN_WIDTH := 14.0
const SIDE_MARGIN := 0.5
## 뒷벽에서 선반 줄 끝까지 (경사로 자리 포함)
const BACK_ZONE := 4.0
## 선반 줄 앞 끝에서 문이 있는 앞벽까지 (입고장: 장난감이 흩어지는 자리)
const FRONT_ZONE := 8.5
const WALL_HEIGHT := 8.0
const FLOOR_HEIGHT := 4.0
const DOOR_WIDTH := 4.0
const DOOR_HEIGHT := 3.5
const WALL_THICKNESS := 0.4
const SLAB_THICKNESS := 0.3
## 경사로: 뒷벽을 따라 +X(아래)에서 -X(위)로 올라간다
const RAMP_HALF_RUN := 5.0
const RAMP_DEPTH := 2.5
const TOY_TARGET := 90
const TOY_COLLIDER := 0.3
const TOY_LAYER := 2
## 장난감이 흩어지는 자리: 앞벽에서 1m ~ 7m 사이, 좌우는 벽에서 1.5m 안쪽(최대 ±9m)
const SPAWN_FROM_FRONT := 1.0
const SPAWN_DEPTH := 6.0
const SPAWN_MAX_HALF_X := 9.0
## 더미: 한 층에 보이는 장난감은 최대 TOY_TARGET개(8×6 + 6×4 + 4×3 + 2×3). 총량은 바닥 재고로 따로 센다
const HEAP_LAYERS: Array[Vector2i] = [Vector2i(8, 6), Vector2i(6, 4), Vector2i(4, 3), Vector2i(2, 3)]
const HEAP_SPACING := 0.42
const HEAP_LAYER_HEIGHT := 0.26
const WALL_COLORS := {
	1: Color(0.56, 0.76, 0.96),
	2: Color(0.6, 0.88, 0.7),
	3: Color(1.0, 0.82, 0.5),
	4: Color(0.98, 0.66, 0.74),
}

static var _toy_shape: BoxShape3D

var warehouse_id: int = 1
## 창고 크기(m). 선반 수에 맞춰 _ready에서 정해진다
var width: float = MIN_WIDTH
var depth: float = 16.0
## 새로 만드는 장난감이 황금일 확률. 테스트는 0으로 고정한다.
static var golden_chance: float = 0.01

var is_open: bool = false
var shelves: Array[Shelf] = []

var _door: StaticBody3D
var _door_material: StandardMaterial3D
var _status_label: Label3D
var _gate: StaticBody3D
var _toy_roots: Array[Node3D] = []
## 층별 더미 자리에 놓인 장난감 (빈 자리는 null)
var _heaps: Array = []
var _lights: Array[OmniLight3D] = []
var _door_tween: Tween


## 창고 번호의 통로 수
static func aisles_of(warehouse_id: int) -> int:
	@warning_ignore("integer_division")
	return GameState.shelves_per_floor(warehouse_id) / GameState.SHELVES_PER_AISLE[warehouse_id]


## 통로 한쪽 줄의 선반 수
static func bays_of(warehouse_id: int) -> int:
	@warning_ignore("integer_division")
	return GameState.SHELVES_PER_AISLE[warehouse_id] / 2


## 줄 가운데 가로 통로의 폭 (줄이 짧으면 0)
static func cross_aisle_of(warehouse_id: int) -> float:
	return CROSS_AISLE_WIDTH if bays_of(warehouse_id) > CROSS_AISLE_BAYS else 0.0


## 창고 번호의 크기: x = 가로, y = 세로(깊이). 통로 수와 줄 길이에서 정해진다.
static func size_of(warehouse_id: int) -> Vector2:
	var wide := maxf(MIN_WIDTH, aisles_of(warehouse_id) * AISLE_PITCH + 2.0 * SIDE_MARGIN)
	var deep := (
		BACK_ZONE + bays_of(warehouse_id) * SHELF_PITCH
		+ cross_aisle_of(warehouse_id) + FRONT_ZONE
	)
	return Vector2(wide, deep)


## 통로 가운데에서 선반 줄 가운데까지의 거리.
## 통로가 하나뿐인 창고(창고 1)는 선반 줄을 양쪽 벽에 붙인다.
static func row_offset(warehouse_id: int) -> float:
	if aisles_of(warehouse_id) == 1:
		return size_of(warehouse_id).x / 2.0 - WALL_THICKNESS / 2.0 - Shelf.DEPTH / 2.0 - 0.05
	return (AISLE_WIDTH + Shelf.DEPTH) / 2.0


## 통로 가운데의 로컬 x
static func aisle_x(warehouse_id: int, aisle: int) -> float:
	return (aisle - (aisles_of(warehouse_id) - 1) / 2.0) * AISLE_PITCH


## 바닥에 놓이는 장난감 하나. rigid면 물리로 굴러다닌다(와르르용). type이 -1이면 무작위.
static func make_toy(rigid: bool, type: int = -1, allow_golden: bool = true) -> CollisionObject3D:
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
	if allow_golden and randf() < golden_chance:
		gild_toy(body)
	return body


## 황금 장난감으로 만든다. 이 장난감이 든 박스는 코인을 10배로 준다.
static func gild_toy(toy: Node3D) -> void:
	toy.set_meta("golden", true)
	Toys.gild(toy)


func _ready() -> void:
	var size := size_of(warehouse_id)
	width = size.x
	depth = size.y
	_build_shell()
	_build_upper_floor()
	_build_shelves()
	_build_markings()
	_build_door()
	_build_signs()
	_build_lights()
	for floor_index in GameState.FLOORS_PER_WAREHOUSE:
		var root := Node3D.new()
		root.name = "Toys%d" % (floor_index + 1)
		add_child(root)
		_toy_roots.append(root)
		_heaps.append([])

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
	return to_global(Vector3(0.0, 1.5, depth / 2.0 + 1.0))


func _on_shelf_completed(completed_warehouse: int, _floor_index: int, _shelf_index: int) -> void:
	if completed_warehouse == warehouse_id:
		_refresh()


func _refresh() -> void:
	var unlocked := GameState.is_warehouse_unlocked(warehouse_id)
	_door_material.albedo_color = Color(0.45, 0.86, 0.56) if unlocked else Color(0.96, 0.46, 0.46)
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


## 창고가 크고 조명이 많아서, 플레이어가 가까이 있을 때만 켠다 (창고 밖 14m까지).
func _update_lights() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var local := to_local(camera.global_position)
	var near := absf(local.x) < width / 2.0 + 14.0 and absf(local.z) < depth / 2.0 + 14.0
	for light in _lights:
		light.visible = near


func _refill() -> void:
	_update_lights()
	for floor_index in _toy_roots.size():
		var root := _toy_roots[floor_index]
		var active := (
			GameState.is_floor_active(warehouse_id, floor_index)
			and not GameState.is_floor_complete(warehouse_id, floor_index)
		)
		if not active:
			for toy in root.get_children():
				toy.remove_from_group("toy")
				toy.queue_free()
			_heaps[floor_index] = []
			continue
		_update_heap(floor_index, root)


## 더미 자리: 층층이 쌓은 봉우리 모양. 아래 층부터 순서대로 놓이고, 맨 위부터 줄어든다.
func _heap_slots() -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var center_z := depth / 2.0 - SPAWN_FROM_FRONT - SPAWN_DEPTH / 2.0
	for layer in HEAP_LAYERS.size():
		var grid: Vector2i = HEAP_LAYERS[layer]
		for row in grid.y:
			for column in grid.x:
				slots.append(Vector3(
					(column - (grid.x - 1) / 2.0) * HEAP_SPACING,
					layer * HEAP_LAYER_HEIGHT,
					center_z + (row - (grid.y - 1) / 2.0) * HEAP_SPACING
				))
	return slots


## 바닥에 남은 장난감만큼만 더미를 쌓는다. 장난감이 집혀 빈 자리가 생기면 맨 위 장난감이 내려와 메운다.
func _update_heap(floor_index: int, root: Node3D) -> void:
	var key := GameState.floor_key(warehouse_id, floor_index)
	var slots := _heap_slots()
	var heap: Array = _heaps[floor_index]
	heap.resize(slots.size())
	for i in heap.size():
		var toy: Variant = heap[i]
		if toy != null and (not is_instance_valid(toy) or toy.is_queued_for_deletion() or not (toy as Node).is_in_group("toy")):
			heap[i] = null
	var heap_target := clampi(
		GameState.ground_toys(warehouse_id, floor_index) - int(GameState.dropped_toys.get(key, 0)),
		0, mini(TOY_TARGET, slots.size())
	)
	var count := heap.count(null)
	var alive := heap.size() - count
	# 재고보다 많이 놓여 있으면(자동 정리로 줄었을 때) 맨 위부터 치운다
	var top := heap.size() - 1
	while alive > heap_target and top >= 0:
		if heap[top] != null:
			(heap[top] as Node).remove_from_group("toy")
			(heap[top] as Node).queue_free()
			heap[top] = null
			alive -= 1
		top -= 1
	# 빈 자리는 맨 위 장난감이 내려와 메운다
	var hole := 0
	top = heap.size() - 1
	while true:
		while hole < heap.size() and heap[hole] != null:
			hole += 1
		while top >= 0 and heap[top] == null:
			top -= 1
		if hole >= top:
			break
		var moved := heap[top] as Node3D
		heap[hole] = moved
		heap[top] = null
		moved.create_tween().tween_property(
			moved, "position", slots[hole] + Vector3.UP * floor_index * FLOOR_HEIGHT, 0.25
		)
	# 재고가 남아 있는데 더미가 모자라면(처음, 또는 버린 장난감을 다시 주웠을 때) 위에 채운다
	for i in heap.size():
		if alive >= heap_target:
			break
		if heap[i] != null:
			continue
		var toy := make_toy(false)
		toy.position = slots[i] + Vector3(
			randf_range(-0.05, 0.05), floor_index * FLOOR_HEIGHT, randf_range(-0.05, 0.05)
		)
		toy.rotation.y = randf() * TAU
		toy.set_meta("floor_key", key)
		root.add_child(toy)
		heap[i] = toy
		alive += 1
	_heaps[floor_index] = heap


func _build_shell() -> void:
	var color: Color = WALL_COLORS.get(warehouse_id, Color(0.7, 0.7, 0.7))
	var wall := Look.grid(color, color.darkened(0.1), 2.0)
	var floor_material := Look.grid(Color(0.74, 0.7, 0.66), Color(0.64, 0.6, 0.57), 1.0)
	_box(Vector3(width + 2.0, 0.2, depth + 2.0), Vector3(0.0, -0.1, 0.0), floor_material)

	var half_h := WALL_HEIGHT / 2.0
	_box(Vector3(width, WALL_HEIGHT, WALL_THICKNESS), Vector3(0.0, half_h, -depth / 2.0), wall)
	_box(Vector3(WALL_THICKNESS, WALL_HEIGHT, depth), Vector3(-width / 2.0, half_h, 0.0), wall)
	_box(Vector3(WALL_THICKNESS, WALL_HEIGHT, depth), Vector3(width / 2.0, half_h, 0.0), wall)

	var side_width := (width - DOOR_WIDTH) / 2.0
	var side_x := DOOR_WIDTH / 2.0 + side_width / 2.0
	for x: float in [-side_x, side_x]:
		_box(Vector3(side_width, WALL_HEIGHT, WALL_THICKNESS), Vector3(x, half_h, depth / 2.0), wall)
	var lintel_height := WALL_HEIGHT - DOOR_HEIGHT
	_box(
		Vector3(DOOR_WIDTH, lintel_height, WALL_THICKNESS),
		Vector3(0.0, DOOR_HEIGHT + lintel_height / 2.0, depth / 2.0),
		wall
	)

	# 지붕(안쪽은 밝은 천장), 지붕 테두리, 벽 아래·위 띠
	var cream := Look.matte(Color(0.97, 0.96, 0.92))
	var dark := Look.matte(color.darkened(0.4))
	_box(Vector3(width + 0.4, 0.3, depth + 0.4), Vector3(0.0, WALL_HEIGHT + 0.15, 0.0), cream)
	_deco(Vector3(width + 1.2, 0.25, depth + 1.2), Vector3(0.0, WALL_HEIGHT + 0.4, 0.0), dark)
	_band(0.3, 0.6, dark, false)
	_band(WALL_HEIGHT - 0.35, 0.5, cream, true)


## 벽을 따라 두르는 띠 장식. full_front면 문 위까지 앞면 전체를 두른다.
func _band(y: float, height: float, material: Material, full_front: bool) -> void:
	var thickness := WALL_THICKNESS + 0.12
	_deco(Vector3(width + 0.12, height, thickness), Vector3(0.0, y, -depth / 2.0), material)
	for x: float in [-width / 2.0, width / 2.0]:
		_deco(Vector3(thickness, height, depth + 0.12), Vector3(x, y, 0.0), material)
	if full_front:
		_deco(Vector3(width + 0.12, height, thickness), Vector3(0.0, y, depth / 2.0), material)
		return
	var side_width := (width - DOOR_WIDTH) / 2.0
	var side_x := DOOR_WIDTH / 2.0 + side_width / 2.0
	for x: float in [-side_x, side_x]:
		_deco(Vector3(side_width + 0.06, height, thickness), Vector3(x, y, depth / 2.0), material)


func _build_upper_floor() -> void:
	var slab := Look.grid(Color(0.7, 0.72, 0.78), Color(0.6, 0.62, 0.7), 1.0)
	var slab_y := FLOOR_HEIGHT - SLAB_THICKNESS / 2.0
	var ramp_front_z := -depth / 2.0 + RAMP_DEPTH
	var ramp_center_z := -depth / 2.0 + RAMP_DEPTH / 2.0
	# 경사로 구멍을 뺀 2층 바닥: 앞쪽 큰 판 + 뒷벽 양쪽 모서리
	var main_depth := depth / 2.0 - ramp_front_z
	_box(
		Vector3(width, SLAB_THICKNESS, main_depth),
		Vector3(0.0, slab_y, ramp_front_z + main_depth / 2.0),
		slab
	)
	var corner_width := width / 2.0 - RAMP_HALF_RUN
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
		Look.grid(Color(1.0, 0.84, 0.35), Color(0.92, 0.7, 0.22), 0.5)
	)
	ramp.rotation.z = -atan2(FLOOR_HEIGHT, run)

	_gate = _box(
		Vector3(0.2, 2.2, RAMP_DEPTH),
		Vector3(RAMP_HALF_RUN + 0.3, 1.1, ramp_center_z),
		Look.hazard(0.8)
	)
	var gate_label := Label3D.new()
	gate_label.outline_size = 16
	gate_label.text = "1층을 모두 정리하면\n2층이 열립니다"
	gate_label.font_size = 48
	gate_label.pixel_size = 0.005
	gate_label.position = Vector3(0.12, 0.2, 0.0)
	gate_label.rotation.y = PI / 2.0
	_gate.add_child(gate_label)


## 선반 번호는 통로 순서다: 통로 A의 왼쪽 줄(문 쪽 → 안쪽), 오른쪽 줄, 그다음 통로 B…
## 선반 앞면(로컬 +Z)은 통로를 본다.
func _build_shelves() -> void:
	var per_floor := GameState.shelves_per_floor(warehouse_id)
	var per_aisle: int = GameState.SHELVES_PER_AISLE[warehouse_id]
	var bays := bays_of(warehouse_id)
	var cross := cross_aisle_of(warehouse_id)
	var front_z := depth / 2.0 - FRONT_ZONE
	for floor_index in GameState.FLOORS_PER_WAREHOUSE:
		for shelf_index in per_floor:
			@warning_ignore("integer_division")
			var aisle := shelf_index / per_aisle
			var within := shelf_index % per_aisle
			var side := -1.0 if within < bays else 1.0
			var bay := within % bays
			var z := front_z - SHELF_PITCH * (bay + 0.5)
			@warning_ignore("integer_division")
			if bay >= bays / 2:
				z -= cross
			var shelf := Shelf.new()
			shelf.name = "Shelf_%d_%d" % [floor_index + 1, shelf_index + 1]
			shelf.warehouse_id = warehouse_id
			shelf.floor_index = floor_index
			shelf.shelf_index = shelf_index
			shelf.position = Vector3(
				aisle_x(warehouse_id, aisle) + side * row_offset(warehouse_id),
				floor_index * FLOOR_HEIGHT,
				z
			)
			shelf.rotation.y = -side * PI / 2.0
			add_child(shelf)
			shelves.append(shelf)


## 입고장 바닥선, 통로 바닥선, 통로 입구 표지판 (층마다)
func _build_markings() -> void:
	var yellow := Look.matte(Color(1.0, 0.82, 0.2))
	var line := 0.12
	var half_x := minf(width / 2.0 - 1.5, SPAWN_MAX_HALF_X) + 0.4
	var dock_front := depth / 2.0 - SPAWN_FROM_FRONT + 0.4
	var dock_back := dock_front - SPAWN_DEPTH - 0.8
	var rack_front := depth / 2.0 - FRONT_ZONE
	var rack_back := -depth / 2.0 + BACK_ZONE
	var rack_length := rack_front - rack_back
	for floor_index in GameState.FLOORS_PER_WAREHOUSE:
		var y := floor_index * FLOOR_HEIGHT + 0.01
		# 입고장 테두리
		for z: float in [dock_front, dock_back]:
			_deco(Vector3(half_x * 2.0, 0.02, line), Vector3(0.0, y, z), yellow)
		for x: float in [-half_x, half_x]:
			_deco(
				Vector3(line, 0.02, dock_front - dock_back),
				Vector3(x, y, (dock_front + dock_back) / 2.0), yellow
			)
		var dock_label := Label3D.new()
		dock_label.text = "입고장"
		dock_label.font_size = 96
		dock_label.pixel_size = 0.01
		dock_label.modulate = Color(1.0, 0.82, 0.2, 0.75)
		dock_label.outline_size = 0
		dock_label.rotation.x = -PI / 2.0
		dock_label.position = Vector3(0.0, y + 0.01, dock_back + 0.7)
		add_child(dock_label)

		for aisle in aisles_of(warehouse_id):
			var x := aisle_x(warehouse_id, aisle)
			# 통로 양쪽 바닥선
			for side: float in [-1.0, 1.0]:
				_deco(
					Vector3(line, 0.02, rack_length),
					Vector3(
						x + side * (row_offset(warehouse_id) - Shelf.DEPTH / 2.0 - 0.2),
						y, rack_back + rack_length / 2.0
					),
					yellow
				)
			# 통로 입구 표지판: 통로 글자와 이 통로가 맡는 장난감 종류
			var type := GameState.default_shelf_type(
				warehouse_id, floor_index, aisle * GameState.SHELVES_PER_AISLE[warehouse_id]
			)
			var sign_at := Vector3(x, floor_index * FLOOR_HEIGHT + 3.2, rack_front + 0.1)
			_deco(Vector3(2.5, 0.6, 0.06), sign_at, Look.matte(Toys.COLORS[type].darkened(0.45)))
			var sign := Label3D.new()
			sign.text = "%s · %s" % [char(65 + aisle), Toys.NAMES[type]]
			sign.font_size = 64
			sign.outline_size = 10
			sign.outline_modulate = Color(0.1, 0.12, 0.22)
			sign.pixel_size = 0.006
			sign.position = sign_at + Vector3(0.0, 0.0, 0.05)
			sign.visibility_range_end = 45.0
			add_child(sign)


func _build_door() -> void:
	# 셔터 문: 흰 바탕 무늬에 albedo_color로 초록(열 수 있음)·빨강(잠김)을 입힌다
	_door_material = Look.bands(Color.WHITE, Color(0.8, 0.8, 0.8), 0.4)
	_door = _box(
		Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.2),
		Vector3(0.0, DOOR_HEIGHT / 2.0, depth / 2.0),
		_door_material
	)
	_door.add_to_group("door")
	_door.set_meta("warehouse", self)

	# 안전 줄무늬 문틀
	var frame := Look.hazard(0.6)
	var frame_depth := WALL_THICKNESS + 0.2
	for x: float in [-DOOR_WIDTH / 2.0 - 0.15, DOOR_WIDTH / 2.0 + 0.15]:
		_deco(
			Vector3(0.3, DOOR_HEIGHT + 0.3, frame_depth),
			Vector3(x, (DOOR_HEIGHT + 0.3) / 2.0, depth / 2.0),
			frame
		)
	_deco(
		Vector3(DOOR_WIDTH + 0.6, 0.3, frame_depth),
		Vector3(0.0, DOOR_HEIGHT + 0.15, depth / 2.0),
		frame
	)


func _build_signs() -> void:
	# 간판: 흰 테두리 + 창고 색을 어둡게 한 판
	var color: Color = WALL_COLORS.get(warehouse_id, Color(0.7, 0.7, 0.7))
	var board_at := Vector3(0.0, DOOR_HEIGHT + 2.4, depth / 2.0 + 0.2)
	_deco(Vector3(6.4, 2.2, 0.16), board_at, Look.matte(Color(0.97, 0.96, 0.92)))
	_deco(Vector3(6.0, 1.8, 0.2), board_at, Look.matte(color.darkened(0.45)))

	var title := Label3D.new()
	title.text = "창고 %d" % warehouse_id
	title.font_size = 150
	title.outline_size = 20
	title.outline_modulate = Color(0.1, 0.12, 0.22)
	title.pixel_size = 0.011
	title.position = Vector3(0.0, DOOR_HEIGHT + 2.4, depth / 2.0 + 0.34)
	add_child(title)

	_status_label = Label3D.new()
	_status_label.font_size = 72
	_status_label.outline_size = 16
	_status_label.pixel_size = 0.01
	_status_label.position = Vector3(0.0, DOOR_HEIGHT + 0.9, depth / 2.0 + 0.3)
	add_child(_status_label)


func _build_lights() -> void:
	# 층마다 통로 위 천장에 길쭉한 전등을 줄지어 단다 (모양만, 한 통로에 한 덩어리)
	var lamp := Look.glow(Color(1.0, 0.96, 0.82), 3.0)
	var count_x := maxi(2, roundi(width / 9.0))
	var count_z := maxi(2, roundi(depth / 9.0))
	for floor_index in GameState.FLOORS_PER_WAREHOUSE:
		var ceiling := FLOOR_HEIGHT - SLAB_THICKNESS if floor_index == 0 else WALL_HEIGHT
		for aisle in aisles_of(warehouse_id):
			for j in count_z * 2:
				_deco(
					Vector3(0.4, 0.08, 2.4),
					Vector3(
						aisle_x(warehouse_id, aisle), ceiling - 0.05,
						-depth / 2.0 + depth * (j + 0.5) / (count_z * 2)
					),
					lamp
				)
		# 실제 조명은 약 9m 격자에서 하나 걸러 하나에만 단다
		for i in count_x:
			for j in count_z:
				var at := Vector3(
					-width / 2.0 + width * (i + 0.5) / count_x,
					ceiling - 0.05,
					-depth / 2.0 + depth * (j + 0.5) / count_z
				)
				if (i + j) % 2 != 0:
					continue
				var light := OmniLight3D.new()
				light.position = at + Vector3.DOWN * 0.75
				light.omni_range = 12.0
				light.light_energy = 1.1
				light.light_color = Color(1.0, 0.95, 0.85)
				add_child(light)
				_lights.append(light)


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
