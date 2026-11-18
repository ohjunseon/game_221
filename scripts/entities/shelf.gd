class_name Shelf
extends StaticBody3D
## 10단 정리 선반. 모든 선반은 똑같이 박스 100개(한 단에 10칸)를 담는다.
## 저장량(박스 수)은 GameState가 갖고, 이 노드는 그것을 보여 준다.
## 선반마다 장난감 종류가 하나이고, 아래 단부터 채워지며, 단 높이에 따라 필요한 자세가 다르다.

enum Posture { CROUCH, STAND, JUMP }

const TIER_COUNT := 10
const TIER_HEIGHT := 0.28
const WIDTH := 2.0
const DEPTH := 0.5
const BOARD_THICKNESS := 0.03
const SLOTS_PER_TIER := 10
const TOY_VISUAL_SIZE := 0.16
## 이 거리보다 멀리 있는 선반의 모양은 그리지 않는다 (선반이 400개라서)
const DRAW_RANGE := 55.0
const LABEL_RANGE := 22.0
const POP_DELAY := 0.12
const POP_SECONDS := 0.25
const MAX_POPS := 6

static var _frame_mesh: ArrayMesh
static var _crown_mesh: ArrayMesh
static var _star_mesh: ArrayMesh
static var _highlight_mesh: BoxMesh
static var _highlight_material: StandardMaterial3D

var warehouse_id: int = 1
var floor_index: int = 0
var shelf_index: int = 0

var _key: String = ""
var _highlight: MeshInstance3D
var _label: Label3D
var _boxes: MultiMeshInstance3D
var _box_type: int = -1
## 선반 맨 위 앞면의 형태 색 간판과, 그 위에 올린 큰 장난감 모형
var _sign: MeshInstance3D
var _figure: MeshInstance3D
static var _sign_materials: Dictionary = {}
var _shown: int = 0
## 튀어나오는 중인 박스: 칸 번호 → 지난 시간
var _pops: Dictionary = {}
var _celebrated: bool = false
## _ready가 끝난 뒤에 들어오는 박스만 튀어나오는 연출을 한다
var _live: bool = false


## 1~3단 웅크리기, 4~8단 서서, 9~10단 점프
static func required_posture(tier: int) -> Posture:
	if tier <= 3:
		return Posture.CROUCH
	if tier <= 8:
		return Posture.STAND
	return Posture.JUMP


static func posture_text(posture: Posture) -> String:
	match posture:
		Posture.CROUCH:
			return "웅크리고 넣기 (Shift)"
		Posture.JUMP:
			return "점프해서 넣기 (Space)"
		_:
			return "서서 넣기"


func _ready() -> void:
	_key = GameState.shelf_key(warehouse_id, floor_index, shelf_index)
	add_to_group("shelf")
	_build()
	_celebrated = is_full()
	_sync()
	if _celebrated:
		_add_crown(false)
	_live = true
	set_process(false)
	EventBus.shelf_changed.connect(_on_shelf_changed)


## 담을 수 있는 박스 수 (모든 선반이 같다)
func capacity() -> int:
	return GameState.BOXES_PER_SHELF


## 지금 담긴 박스 수
func stored() -> int:
	return GameState.get_shelf_stored(_key)


func is_full() -> bool:
	return stored() >= capacity()


## 지금 채워야 하는 단 (1~10). 한 단에 박스 10칸
func current_tier() -> int:
	@warning_ignore("integer_division")
	return mini(stored() / SLOTS_PER_TIER + 1, TIER_COUNT)


## 이 선반의 장난감 종류 (아직 정해지지 않았으면 -1)
func shelf_type() -> int:
	return GameState.get_shelf_type(_key)


## 해당 단(1~10) 가운데의 월드 좌표. 박스가 날아갈 목표다.
func tier_position(tier: int) -> Vector3:
	return global_transform * Vector3(0.0, (tier - 0.5) * TIER_HEIGHT, 0.0)


## 박스를 넣고 실제로 들어간 박스 수를 돌려준다.
## toy_type: 박스의 장난감 종류 (-1이면 선반 종류를 따른다)
func add(boxes: int, coin_mult: float = 1.0, toy_type: int = -1) -> int:
	return GameState.store_in_shelf(
		warehouse_id, floor_index, shelf_index, boxes, coin_mult, toy_type
	)


func _process(delta: float) -> void:
	var multimesh := _boxes.multimesh
	for index: int in _pops.keys():
		var elapsed: float = _pops[index] + delta
		var progress := clampf((elapsed - POP_DELAY) / POP_SECONDS, 0.0, 1.0)
		# 살짝 넘쳤다가 돌아오는 "쏙" 효과
		var back := 1.0 + 2.70158 * pow(progress - 1.0, 3.0) + 1.70158 * pow(progress - 1.0, 2.0)
		multimesh.set_instance_transform(index, _slot_transform(index, lerpf(0.1, 1.0, back)))
		if progress >= 1.0:
			_pops.erase(index)
		else:
			_pops[index] = elapsed
	if _pops.is_empty():
		set_process(false)


func _on_shelf_changed(key: String) -> void:
	if key != _key:
		return
	_sync()
	if is_full() and not _celebrated:
		_celebrated = true
		_celebrate()


func _sync() -> void:
	var count := mini(stored(), capacity())
	var type := shelf_type()
	if type >= 0 and type != _box_type:
		_box_type = type
		_boxes.multimesh.mesh = Toys.box_mesh(type)
		if not _sign_materials.has(type):
			_sign_materials[type] = Look.matte(Toys.COLORS[type])
		_sign.material_override = _sign_materials[type]
		_figure.mesh = Toys.field_mesh(type)
	# 빈 선반은 흰 간판(아무 박스나 받음), 종류가 정해지면 그 색 간판과 모형
	if type < 0:
		if not _sign_materials.has(-1):
			_sign_materials[-1] = Look.matte(Color(0.95, 0.95, 0.95))
		_sign.material_override = _sign_materials[-1]
	_figure.visible = type >= 0
	if _live and count > _shown:
		for index in range(maxi(_shown, count - MAX_POPS), count):
			_pops[index] = 0.0
			_boxes.multimesh.set_instance_transform(index, _slot_transform(index, 0.1))
		set_process(true)
	_shown = count
	_boxes.multimesh.visible_instance_count = count

	var type_name := "빈 선반" if type < 0 else Toys.NAMES[type]
	if is_full():
		_label.text = "%s 완성!" % type_name
		_label.modulate = Color(0.5, 1.0, 0.5)
	else:
		_label.text = "%s\n박스 %d / %d" % [type_name, count, capacity()]
		_label.modulate = Color.WHITE if type < 0 else Toys.COLORS[type].lightened(0.35)
	_highlight.visible = not is_full()
	_highlight.position.y = (current_tier() - 0.5) * TIER_HEIGHT


## 박스 번호(0~99)가 놓이는 자리: 아래 단부터, 한 단에 왼쪽에서 오른쪽으로 10칸
func _slot_transform(index: int, box_scale: float) -> Transform3D:
	@warning_ignore("integer_division")
	var tier := index / SLOTS_PER_TIER
	var slot := index % SLOTS_PER_TIER
	var slot_width := (WIDTH - 0.1) / SLOTS_PER_TIER
	var at := Vector3(
		-WIDTH / 2.0 + 0.05 + slot_width * (slot + 0.5),
		tier * TIER_HEIGHT + BOARD_THICKNESS / 2.0 + TOY_VISUAL_SIZE / 2.0,
		0.0
	)
	return Transform3D(Basis.from_scale(Vector3.ONE * TOY_VISUAL_SIZE * box_scale), at)


## 선반 완성: 색종이 폭죽, 금색 테두리와 별, 팡파르
func _celebrate() -> void:
	var particles := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.02, 0.07)
	particles.mesh = mesh
	var paper := StandardMaterial3D.new()
	paper.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paper.vertex_color_use_as_albedo = true
	particles.material_override = paper
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
	colors.colors = PackedColorArray([
		Color(1.0, 0.85, 0.2), Color(1.0, 0.45, 0.6), Color(0.4, 0.75, 1.0),
		Color(0.45, 0.95, 0.65), Color(1.0, 1.0, 1.0),
	])
	particles.color_initial_ramp = colors
	particles.one_shot = true
	particles.amount = 110
	particles.lifetime = 1.8
	particles.explosiveness = 0.95
	particles.direction = Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 8.0
	particles.angular_velocity_min = -360.0
	particles.angular_velocity_max = 360.0
	particles.gravity = Vector3(0.0, -7.0, 0.0)
	particles.position.y = TIER_HEIGHT * TIER_COUNT
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(3.0).timeout.connect(particles.queue_free)
	_add_crown(true)
	Sfx.play("fanfare")
	EventBus.popup_requested.emit("선반 완성!")
	EventBus.shake_requested.emit(0.5)


## 완성한 선반의 금색 테두리와 꼭대기에서 도는 별 (메시는 모든 선반이 공유)
func _add_crown(animated: bool) -> void:
	if _crown_mesh == null:
		var height := TIER_HEIGHT * TIER_COUNT
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		Look.add_cuboid(
			st, Vector3(0.0, height + 0.04, 0.0), Vector3(WIDTH + 0.16, 0.08, DEPTH + 0.08), Color.WHITE
		)
		for x: float in [-WIDTH / 2.0, WIDTH / 2.0]:
			Look.add_cuboid(
				st, Vector3(x, height / 2.0, 0.0), Vector3(0.1, height + 0.08, DEPTH + 0.08), Color.WHITE
			)
		_crown_mesh = st.commit()
		_crown_mesh.surface_set_material(0, Look.glow(Toys.GOLD, 0.45))
		var star := SurfaceTool.new()
		star.begin(Mesh.PRIMITIVE_TRIANGLES)
		Look.add_cuboid(star, Vector3.ZERO, Vector3(0.24, 0.24, 0.06), Color.WHITE)
		_star_mesh = star.commit()
		_star_mesh.surface_set_material(0, Look.glow(Toys.GOLD, 0.45))

	var crown := MeshInstance3D.new()
	crown.mesh = _crown_mesh
	crown.visibility_range_end = DRAW_RANGE
	add_child(crown)

	# 정사각형 두 장을 45도 어긋나게 겹쳐 8각 별처럼 보이게 한다
	var star_node := Node3D.new()
	star_node.position.y = TIER_HEIGHT * TIER_COUNT + 0.62
	for angle: float in [0.0, PI / 4.0]:
		var point := MeshInstance3D.new()
		point.mesh = _star_mesh
		point.rotation.z = angle
		point.visibility_range_end = DRAW_RANGE
		star_node.add_child(point)
	add_child(star_node)
	var spin := star_node.create_tween().set_loops()
	spin.tween_property(star_node, "rotation:y", TAU, 3.0).from(0.0)
	if animated:
		star_node.scale = Vector3.ONE * 0.1
		star_node.create_tween().tween_property(star_node, "scale", Vector3.ONE, 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build() -> void:
	var total_height := TIER_HEIGHT * TIER_COUNT

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, total_height, DEPTH)
	shape.shape = box
	shape.position.y = total_height / 2.0
	add_child(shape)

	# 물류 랙: 파란 기둥에 밝은 선반 판. 모든 선반이 하나의 메시를 나눠 쓴다
	if _frame_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var board_color := Color(0.96, 0.92, 0.84)
		for i in TIER_COUNT + 1:
			Look.add_cuboid(
				st, Vector3(0.0, i * TIER_HEIGHT, 0.0),
				Vector3(WIDTH, BOARD_THICKNESS, DEPTH), board_color
			)
		for x: float in [-WIDTH / 2.0, WIDTH / 2.0]:
			Look.add_cuboid(
				st, Vector3(x, total_height / 2.0, 0.0),
				Vector3(0.07, total_height + 0.06, DEPTH + 0.04), Color(0.3, 0.5, 0.92)
			)
		_frame_mesh = st.commit()
		_frame_mesh.surface_set_material(0, Look.vertex_color(0.7))
	var frame := MeshInstance3D.new()
	frame.mesh = _frame_mesh
	frame.visibility_range_end = DRAW_RANGE
	add_child(frame)

	# 박스 100칸: 형태별 메시를 쓰는 MultiMesh 하나. 종류가 정해지면 메시를 바꾼다
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = capacity()
	for index in capacity():
		multimesh.set_instance_transform(index, _slot_transform(index, 1.0))
	multimesh.visible_instance_count = 0
	multimesh.mesh = Toys.box_mesh(0)
	_boxes = MultiMeshInstance3D.new()
	_boxes.multimesh = multimesh
	_boxes.visibility_range_end = DRAW_RANGE
	add_child(_boxes)

	if _highlight_mesh == null:
		_highlight_material = StandardMaterial3D.new()
		_highlight_material.albedo_color = Color(1.0, 0.9, 0.2, 0.35)
		_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight_mesh = BoxMesh.new()
		_highlight_mesh.size = Vector3(WIDTH - 0.06, TIER_HEIGHT - BOARD_THICKNESS, DEPTH + 0.02)
	_highlight = MeshInstance3D.new()
	_highlight.mesh = _highlight_mesh
	_highlight.material_override = _highlight_material
	_highlight.visibility_range_end = LABEL_RANGE
	add_child(_highlight)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.outline_size = 12
	_label.outline_modulate = Color(0.1, 0.12, 0.22)
	_label.pixel_size = 0.004
	_label.position = Vector3(0.0, total_height + 0.45, DEPTH / 2.0 + 0.15)
	_label.visibility_range_end = LABEL_RANGE
	add_child(_label)

	# 종류 간판: 맨 위 단 앞에 형태 색 판, 선반 지붕 위에 그 장난감 모형 (멀리서도 보인다)
	_sign = MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(WIDTH, 0.3, 0.04)
	_sign.mesh = sign_mesh
	_sign.position = Vector3(0.0, total_height + 0.15, DEPTH / 2.0 + 0.03)
	_sign.visibility_range_end = DRAW_RANGE
	add_child(_sign)
	_figure = MeshInstance3D.new()
	_figure.scale = Vector3.ONE * 2.2
	_figure.position = Vector3(0.0, total_height + 0.02, -0.05)
	_figure.visibility_range_end = DRAW_RANGE
	add_child(_figure)
