class_name ToyField
extends Node3D
## 한 층의 바닥 장난감 전부. 재고 수만큼 자리를 만들어 MultiMesh로 한 번에 그리고,
## 플레이어가 조준하거나 자석으로 끌어올 때만 그 자리를 진짜 장난감 노드로 바꾼다.
## 자리 순서: 창고 안(아래 겹부터) → 문 밖 마당의 장난감 산(아래 겹부터).
## 재고가 줄면 마지막 자리(산 꼭대기)부터 사라진다.
## 창고(Warehouse)의 자식이라 좌표는 창고 로컬이다.

const SPACING := 0.32
const JITTER := 0.06
const LAYER_HEIGHT := 0.2
const TOY_HEIGHT := 0.3
const WALL_MARGIN := 0.4
## 선반 앞에 비워 두는 폭 (박스를 넣을 때 장난감이 가리지 않게)
const SHELF_CLEARANCE := 0.55
## 통로 바닥에 까는 겹 수
const CARPET_LAYERS := 3
## 입고장 더미 사이로 문에서 통로까지 낮게 남기는 길의 반폭
const LANE_HALF_WIDTH := 1.1
## 입고장·안쪽 더미: 가장자리에서 1m 들어갈 때마다 늘어나는 겹 수, 최대 겹 수 (천장 4m 아래)
const ZONE_SLOPE := 5.0
const ZONE_MAX_LAYERS := 17
## 마당 산: 문 앞에서 띄우는 거리, 가로/세로 비, 최대 겹 수
const YARD_GAP := 2.5
const YARD_ASPECT := 1.4
const YARD_MAX_LAYERS := 36
const CHUNK := 4.0
## 이 거리 안에서는 장난감 모양, 밖에서는 색 육면체로 그린다
const NEAR_RANGE := 16.0
const MAX_PROXIES := 64
const RAY_STEP := 0.12

const EMPTY := 0
const ON_FLOOR := 1
const AS_NODE := 2

static var all: Array[ToyField] = []

var warehouse_id: int = 1
var floor_index: int = 0
var key: String = ""
## 바닥에 있거나 노드로 바뀐 장난감 수 (= 바닥 재고와 맞춘다)
var alive: int = 0
var positions := PackedVector3Array()
var yaws := PackedFloat32Array()
var types := PackedByteArray()
var golden := PackedByteArray()
var state := PackedByteArray()
## 창고 안 자리 수 (그 뒤는 마당 산)
var inside_count: int = 0

var _columns: Dictionary = {}  # Vector2i -> PackedInt32Array (아래 겹부터)
var _chunk_of := PackedInt32Array()
var _mesh_index := PackedInt32Array()  # 모양 MultiMesh 안의 번호 (황금이면 -1)
var _far_index := PackedInt32Array()  # 육면체(또는 황금) MultiMesh 안의 번호
var _chunks: Array[Dictionary] = []
var _proxies: Array[Node3D] = []
var _proxy_slots := PackedInt32Array()
var _grid_origin := Vector2.ZERO
var _bounds := AABB()
var _top: int = -1


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


## count개 자리를 만들고 그린다. 크기는 창고 번호에서 정해진다.
func build(warehouse: int, floor_number: int, count: int) -> void:
	warehouse_id = warehouse
	floor_index = floor_number
	key = GameState.floor_key(warehouse_id, floor_index)
	var size := Warehouse.size_of(warehouse_id)
	_grid_origin = Vector2(-size.x / 2.0 + WALL_MARGIN, -size.y / 2.0 + WALL_MARGIN)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	_add_layers(_inside_columns(size), floor_index * Warehouse.FLOOR_HEIGHT, count, rng)
	inside_count = positions.size()
	if positions.size() < count:
		_add_layers(_yard_columns(size, count - positions.size()), 0.0, count, rng)
	_assign_types(rng)
	_build_chunks()
	alive = positions.size()
	_top = alive - 1


## 창고 바닥의 칸들: Vector3i(x칸, z칸, 최대 겹 수)
func _inside_columns(size: Vector2) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var half_w := size.x / 2.0 - WALL_MARGIN
	var half_d := size.y / 2.0 - WALL_MARGIN
	var front_z := size.y / 2.0 - Warehouse.FRONT_ZONE
	var back_z := -size.y / 2.0 + Warehouse.BACK_ZONE
	var shelf_rects := _shelf_rects()
	var nx := int((half_w * 2.0) / SPACING) + 1
	var nz := int((half_d * 2.0) / SPACING) + 1
	for ix in nx:
		for iz in nz:
			var p := _cell_center(ix, iz)
			if absf(p.x) > half_w or absf(p.y) > half_d:
				continue
			# 경사로와 2층 구멍
			if p.y < -size.y / 2.0 + Warehouse.RAMP_DEPTH + 0.4 and absf(p.x) < Warehouse.RAMP_HALF_RUN + 0.4:
				continue
			var blocked := false
			for rect: Rect2 in shelf_rects:
				if rect.has_point(p):
					blocked = true
					break
			if blocked:
				continue
			var layers := CARPET_LAYERS
			if p.y > front_z + 0.3 or p.y < back_z - 0.3:
				# 입고장·안쪽 구역: 가운데로 갈수록 높아지는 더미. 문 앞 길은 낮게 둔다
				var in_front := p.y > front_z
				var zone_min := front_z + 0.3 if in_front else -half_d
				var zone_max := half_d if in_front else back_z - 0.3
				var edge := minf(
					minf(p.x + half_w, half_w - p.x),
					minf(p.y - zone_min, zone_max - p.y)
				)
				if in_front:
					edge = minf(edge, absf(p.x) - LANE_HALF_WIDTH)
				if edge <= 0.0:
					layers = 1
				else:
					layers = clampi(CARPET_LAYERS + int(edge * ZONE_SLOPE), 1, ZONE_MAX_LAYERS)
			result.append(Vector3i(ix, iz, layers))
	return result


## 선반 자리 + 앞쪽 여유 (창고 로컬 x/z 평면). 배치는 Warehouse._build_shelves와 같다.
func _shelf_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var size := Warehouse.size_of(warehouse_id)
	var per_aisle: int = GameState.SHELVES_PER_AISLE[warehouse_id]
	var bays := Warehouse.bays_of(warehouse_id)
	var cross := Warehouse.cross_aisle_of(warehouse_id)
	var front_z := size.y / 2.0 - Warehouse.FRONT_ZONE
	for shelf_index in GameState.shelves_per_floor(warehouse_id):
		@warning_ignore("integer_division")
		var aisle := shelf_index / per_aisle
		var within := shelf_index % per_aisle
		var side := -1.0 if within < bays else 1.0
		var bay := within % bays
		var z := front_z - Warehouse.SHELF_PITCH * (bay + 0.5)
		@warning_ignore("integer_division")
		if bay >= bays / 2:
			z -= cross
		var x := Warehouse.aisle_x(warehouse_id, aisle) + side * Warehouse.row_offset(warehouse_id)
		var half := Vector2(Shelf.DEPTH / 2.0 + SHELF_CLEARANCE, Shelf.WIDTH / 2.0 + 0.1)
		rects.append(Rect2(Vector2(x, z) - half, half * 2.0))
	return rects


## 문 앞 마당의 타원 산: needed개가 들어가도록 크기를 정한다.
func _yard_columns(size: Vector2, needed: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var rz := 2.0
	while rz < 20.0:
		# 원뿔 부피 ≈ π·rx·rz·높이 / 3, 겹마다 칸 하나에 한 개
		var capacity := PI * rz * YARD_ASPECT * rz * YARD_MAX_LAYERS / 3.0 / (SPACING * SPACING)
		if capacity >= needed * 1.1:
			break
		rz += 0.25
	var rx := rz * YARD_ASPECT
	var center_z := size.y / 2.0 + YARD_GAP + rz
	var start := Vector2i(
		int(roundf((-rx - _grid_origin.x) / SPACING)),
		int(roundf((center_z - rz - _grid_origin.y) / SPACING))
	)
	for dx in int(rx * 2.0 / SPACING) + 2:
		for dz in int(rz * 2.0 / SPACING) + 2:
			var ix := start.x + dx
			var iz := start.y + dz
			var p := _cell_center(ix, iz)
			var d := Vector2(p.x / rx, (p.y - center_z) / rz).length()
			if d >= 1.0:
				continue
			result.append(Vector3i(ix, iz, maxi(1, int(YARD_MAX_LAYERS * (1.0 - d)))))
	return result


func _cell_center(ix: int, iz: int) -> Vector2:
	return _grid_origin + Vector2(ix, iz) * SPACING


## 칸들을 아래 겹부터 채운다. 전체가 count개가 되면 멈춘다.
func _add_layers(columns: Array[Vector3i], base_y: float, count: int, rng: RandomNumberGenerator) -> void:
	var top := 0
	for column in columns:
		top = maxi(top, column.z)
	for layer in top:
		for column in columns:
			if positions.size() >= count:
				return
			if column.z <= layer:
				continue
			var p := _cell_center(column.x, column.y)
			var at := Vector3(
				p.x + rng.randf_range(-JITTER, JITTER),
				base_y + layer * LAYER_HEIGHT,
				p.y + rng.randf_range(-JITTER, JITTER)
			)
			var slot := positions.size()
			positions.append(at)
			yaws.append(rng.randf() * TAU)
			var cell := Vector2i(column.x, column.y)
			var list: PackedInt32Array = _columns.get(cell, PackedInt32Array())
			list.append(slot)
			_columns[cell] = list
			_bounds = AABB(at, Vector3.ZERO) if slot == 0 else _bounds.expand(at)


## 형태는 박스 단위(4개씩)로 정해 섞는다. 형태마다 4의 배수가 되어 마지막 박스까지 맞는다.
func _assign_types(rng: RandomNumberGenerator) -> void:
	var count := positions.size()
	types.resize(count)
	golden.resize(count)
	state.resize(count)
	for i in count:
		if i % Toys.BOX_SIZE == 0:
			types[i] = rng.randi() % Toys.count()
		else:
			types[i] = types[i - 1]
	for i in range(count - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap := types[i]
		types[i] = types[j]
		types[j] = swap
	for i in count:
		golden[i] = 1 if rng.randf() < Warehouse.golden_chance else 0
		state[i] = ON_FLOOR
	_bounds = _bounds.grow(SPACING)
	_bounds.size.y += TOY_HEIGHT


## 4m 칸마다 MultiMesh 묶음: 형태별 모양(가까이) 6개 + 색 육면체(멀리) 1개 + 황금 1개
func _build_chunks() -> void:
	var count := positions.size()
	var kinds := Toys.count()
	_chunk_of.resize(count)
	_mesh_index.resize(count)
	_far_index.resize(count)
	var chunk_ids := {}
	var counts: Array[PackedInt32Array] = []  # [형태 6개, 육면체, 황금]
	var centers: Array[Vector3] = []
	for i in count:
		var at := positions[i]
		var id_key := Vector3i(floori(at.x / CHUNK), floori(at.z / CHUNK), 1 if i >= inside_count else 0)
		if not chunk_ids.has(id_key):
			chunk_ids[id_key] = counts.size()
			var zeros := PackedInt32Array()
			zeros.resize(kinds + 2)
			counts.append(zeros)
			centers.append(Vector3((id_key.x + 0.5) * CHUNK, at.y, (id_key.y + 0.5) * CHUNK))
		var chunk: int = chunk_ids[id_key]
		_chunk_of[i] = chunk
		var tally := counts[chunk]
		if golden[i] == 1:
			_mesh_index[i] = -1
			_far_index[i] = tally[kinds + 1]
			tally[kinds + 1] += 1
		else:
			_mesh_index[i] = tally[types[i]]
			tally[types[i]] += 1
			_far_index[i] = tally[kinds]
			tally[kinds] += 1
		counts[chunk] = tally

	for chunk in counts.size():
		var center := centers[chunk]
		var meshes: Array = []
		for type in kinds:
			meshes.append(_make_multimesh(Toys.field_mesh(type), counts[chunk][type], center, 0.0, NEAR_RANGE, false))
		_chunks.append({
			"center": center,
			"meshes": meshes,
			"far": _make_multimesh(Toys.far_mesh(), counts[chunk][kinds], center, NEAR_RANGE, 0.0, true),
			"gold": _make_multimesh(Toys.gold_mesh(), counts[chunk][kinds + 1], center, 0.0, 0.0, false),
		})
	for i in count:
		_show(i, true)


func _make_multimesh(mesh: Mesh, count: int, center: Vector3, begin: float, end: float, colors: bool) -> MultiMesh:
	if count <= 0:
		return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = colors
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.position = center
	node.visibility_range_begin = begin
	node.visibility_range_end = end
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return multimesh


func _show(slot: int, visible_now: bool) -> void:
	var entry: Dictionary = _chunks[_chunk_of[slot]]
	var local := positions[slot] - (entry["center"] as Vector3)
	var basis := Basis(Vector3.UP, yaws[slot])
	if not visible_now:
		basis = basis.scaled(Vector3.ZERO)
	if golden[slot] == 1:
		(entry["gold"] as MultiMesh).set_instance_transform(
			_far_index[slot], Transform3D(basis, local + Vector3.UP * 0.12))
		return
	var near := (entry["meshes"] as Array)[types[slot]] as MultiMesh
	near.set_instance_transform(_mesh_index[slot], Transform3D(basis, local))
	var far := entry["far"] as MultiMesh
	far.set_instance_transform(_far_index[slot], Transform3D(basis, local + Vector3.UP * 0.11))
	far.set_instance_color(_far_index[slot], Toys.COLORS[types[slot]])


## 바닥 재고(target)에 맞춘다: 집혀 나간 자리를 비우고, 남는 만큼 꼭대기부터 치우고, 모자라면 되살린다.
func sync(target: int) -> void:
	for i in range(_proxies.size() - 1, -1, -1):
		var toy := _proxies[i]
		if is_instance_valid(toy) and toy.is_in_group("toy") and not toy.is_queued_for_deletion():
			continue
		var slot := _proxy_slots[i]
		if state[slot] == AS_NODE:
			state[slot] = EMPTY
			alive -= 1
		_proxies.remove_at(i)
		_proxy_slots.remove_at(i)
	while alive > target and _top >= 0:
		var slot := _top
		_top -= 1
		if state[slot] == EMPTY:
			continue
		if state[slot] == AS_NODE:
			_free_proxy(slot)
		else:
			_show(slot, false)
		state[slot] = EMPTY
		alive -= 1
	if alive < target:
		for slot in state.size():
			if alive >= target:
				break
			if state[slot] != EMPTY:
				continue
			state[slot] = ON_FLOOR
			_show(slot, true)
			alive += 1
			_top = maxi(_top, slot)


func _free_proxy(slot: int) -> void:
	var index := _proxy_slots.find(slot)
	if index < 0:
		return
	var toy := _proxies[index]
	if is_instance_valid(toy):
		toy.remove_from_group("toy")
		toy.queue_free()
	_proxies.remove_at(index)
	_proxy_slots.remove_at(index)


## 자리를 진짜 장난감 노드로 바꾼다 (조준·줍기·자석용). 너무 많아지면 오래된 것을 다시 바닥 그림으로 돌린다.
func materialize(slot: int) -> Node3D:
	if state[slot] == AS_NODE:
		return _proxies[_proxy_slots.find(slot)]
	var toy := Warehouse.make_toy(false, types[slot], false) as Node3D
	if golden[slot] == 1:
		Warehouse.gild_toy(toy)
	toy.set_meta("floor_key", key)
	toy.set_meta("field_slot", slot)
	toy.position = positions[slot]
	toy.rotation.y = yaws[slot]
	add_child(toy)
	state[slot] = AS_NODE
	_show(slot, false)
	_proxies.append(toy)
	_proxy_slots.append(slot)
	while _proxies.size() > MAX_PROXIES:
		var oldest := _proxies[0]
		var oldest_slot := _proxy_slots[0]
		_proxies.remove_at(0)
		_proxy_slots.remove_at(0)
		if is_instance_valid(oldest) and oldest.is_in_group("toy"):
			oldest.remove_from_group("toy")
			oldest.queue_free()
			state[oldest_slot] = ON_FLOOR
			_show(oldest_slot, true)
		elif state[oldest_slot] == AS_NODE:
			state[oldest_slot] = EMPTY
			alive -= 1
	return toy


## 월드 좌표 광선이 처음 닿는 바닥 장난감 자리. 없으면 -1. hit_distance[0]에 거리를 넣는다.
func raycast(from: Vector3, direction: Vector3, max_distance: float, hit_distance: Array) -> int:
	var local_from := to_local(from)
	var local_dir := (to_local(from + direction) - local_from).normalized()
	var span := _ray_span(local_from, local_dir, max_distance)
	if span.x > span.y:
		return -1
	var t := span.x
	while t <= span.y:
		var p := local_from + local_dir * t
		var cell := Vector2i(
			int(roundf((p.x - _grid_origin.x) / SPACING)),
			int(roundf((p.z - _grid_origin.y) / SPACING))
		)
		if _columns.has(cell):
			for slot: int in _columns[cell]:
				if state[slot] != ON_FLOOR:
					continue
				var at := positions[slot]
				if p.y >= at.y and p.y <= at.y + TOY_HEIGHT:
					hit_distance.clear()
					hit_distance.append(t)
					return slot
		t += RAY_STEP
	return -1


## 광선이 자리 전체 범위(AABB) 안을 지나는 구간 (x: 들어감, y: 나감)
func _ray_span(origin: Vector3, direction: Vector3, max_distance: float) -> Vector2:
	var t_min := 0.0
	var t_max := max_distance
	for axis in 3:
		var o := origin[axis]
		var d := direction[axis]
		var lo := _bounds.position[axis]
		var hi := lo + _bounds.size[axis]
		if absf(d) < 0.00001:
			if o < lo or o > hi:
				return Vector2(1.0, 0.0)
			continue
		var t1 := (lo - o) / d
		var t2 := (hi - o) / d
		t_min = maxf(t_min, minf(t1, t2))
		t_max = minf(t_max, maxf(t1, t2))
	return Vector2(t_min, t_max)


## 자석: center 반경 안에서 type(-1이면 아무거나) 장난감을 limit개까지 노드로 바꿔 돌려준다.
func take_near(center: Vector3, radius: float, type: int, limit: int) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var local := to_local(center)
	var reach := Vector3(radius, 2.0, radius)
	if limit <= 0 or not _bounds.intersects(AABB(local - reach, reach * 2.0)):
		return found
	var steps := int(radius / SPACING) + 1
	var middle := Vector2i(
		int(roundf((local.x - _grid_origin.x) / SPACING)),
		int(roundf((local.z - _grid_origin.y) / SPACING))
	)
	for dx in range(-steps, steps + 1):
		for dz in range(-steps, steps + 1):
			var cell := middle + Vector2i(dx, dz)
			if not _columns.has(cell):
				continue
			for slot: int in _columns[cell]:
				if found.size() >= limit:
					return found
				if state[slot] != ON_FLOOR or (type >= 0 and types[slot] != type):
					continue
				var offset := positions[slot] - local
				if absf(offset.y) > 2.0 or Vector2(offset.x, offset.z).length() > radius:
					continue
				found.append(materialize(slot))
	return found


## 바닥 그림으로 남아 있는 장난감 수 (테스트용)
func floor_count() -> int:
	return state.count(ON_FLOOR)
