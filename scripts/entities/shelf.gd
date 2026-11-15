class_name Shelf
extends StaticBody3D
## 10단 정리 선반. 저장량은 GameState가 갖고, 이 노드는 그것을 보여 준다.
## 아래 단부터 채워지고, 단 높이에 따라 필요한 자세가 다르다.

enum Posture { CROUCH, STAND, JUMP }

const TIER_COUNT := 10
const TIER_HEIGHT := 0.28
const WIDTH := 2.0
const DEPTH := 0.5
const BOARD_THICKNESS := 0.03
const SLOTS_PER_TIER := 10
const TOY_VISUAL_SIZE := 0.16
const PALETTE: Array[Color] = [
	Color(0.95, 0.3, 0.3),
	Color(0.3, 0.6, 0.95),
	Color(0.35, 0.8, 0.4),
	Color(0.98, 0.8, 0.25),
	Color(0.75, 0.45, 0.9),
	Color(0.98, 0.55, 0.2),
]

static var _materials: Dictionary = {}

var warehouse_id: int = 1
var floor_index: int = 0
var shelf_index: int = 0

var _key: String = ""
var _highlight: MeshInstance3D
var _label: Label3D
var _toy_mesh: BoxMesh
var _visuals: Array[MeshInstance3D] = []
var _pending_type: int = -1
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
	_build()
	_celebrated = is_full()
	_sync()
	if _celebrated:
		_add_crown(false)
	_live = true
	EventBus.shelf_changed.connect(_on_shelf_changed)


func capacity() -> int:
	return GameState.SHELF_CAPACITIES[shelf_index]


func stored() -> int:
	return GameState.get_shelf_stored(_key)


func is_full() -> bool:
	return stored() >= capacity()


## 지금 채워야 하는 단 (1~10)
func current_tier() -> int:
	@warning_ignore("integer_division")
	return mini(stored() * TIER_COUNT / capacity() + 1, TIER_COUNT)


## 해당 단(1~10) 가운데의 월드 좌표. 박스가 날아갈 목표다.
func tier_position(tier: int) -> Vector3:
	return global_transform * Vector3(0.0, (tier - 0.5) * TIER_HEIGHT, 0.0)


## 장난감을 넣고 실제로 들어간 개수를 돌려준다.
## toy_type: 선반에 보일 박스의 장난감 형태 (-1이면 무작위)
func add(amount: int, coin_mult: float = 1.0, toy_type: int = -1) -> int:
	_pending_type = toy_type
	var accepted := GameState.store_in_shelf(
		warehouse_id, floor_index, shelf_index, amount, coin_mult
	)
	_pending_type = -1
	return accepted


func _on_shelf_changed(key: String) -> void:
	if key != _key:
		return
	_sync()
	if is_full() and not _celebrated:
		_celebrated = true
		_celebrate()


func _sync() -> void:
	@warning_ignore("integer_division")
	var target := mini(stored() * TIER_COUNT * SLOTS_PER_TIER / capacity(), TIER_COUNT * SLOTS_PER_TIER)
	while _visuals.size() > target:
		_visuals.pop_back().queue_free()
	while _visuals.size() < target:
		_add_toy_visual(_visuals.size())
	if is_full():
		_label.text = "완성!"
		_label.modulate = Color(0.5, 1.0, 0.5)
	else:
		_label.text = "%s / %s" % [Skills.fmt(stored()), Skills.fmt(capacity())]
		_label.modulate = Color.WHITE
	_highlight.visible = not is_full()
	_highlight.position.y = (current_tier() - 0.5) * TIER_HEIGHT


func _add_toy_visual(index: int) -> void:
	@warning_ignore("integer_division")
	var tier := index / SLOTS_PER_TIER
	var slot := index % SLOTS_PER_TIER
	var type := _pending_type if _pending_type >= 0 else Toys.random_type()
	var toy := Toys.make_box(type, TOY_VISUAL_SIZE)
	var slot_width := (WIDTH - 0.1) / SLOTS_PER_TIER
	toy.position = Vector3(
		-WIDTH / 2.0 + 0.05 + slot_width * (slot + 0.5),
		tier * TIER_HEIGHT + BOARD_THICKNESS / 2.0 + TOY_VISUAL_SIZE / 2.0,
		0.0
	)
	add_child(toy)
	_visuals.append(toy)
	if _live:
		# 날아오는 박스가 닿을 즈음 "쏙" 하고 튀어나온다
		var full_scale := toy.scale
		toy.scale = full_scale * 0.1
		var tween := toy.create_tween()
		tween.tween_interval(0.12)
		tween.tween_property(toy, "scale", full_scale, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	EventBus.popup_requested.emit("선반 완성! 스킬 포인트 +1")
	EventBus.shake_requested.emit(0.5)


## 완성한 선반의 금색 테두리와 꼭대기에서 도는 별
func _add_crown(animated: bool) -> void:
	var gold := Look.glow(Toys.GOLD, 0.45)
	var height := TIER_HEIGHT * TIER_COUNT
	var bars: Array = [
		[Vector3(WIDTH + 0.16, 0.08, DEPTH + 0.08), Vector3(0.0, height + 0.04, 0.0)],
		[Vector3(0.1, height + 0.08, DEPTH + 0.08), Vector3(-WIDTH / 2.0, height / 2.0, 0.0)],
		[Vector3(0.1, height + 0.08, DEPTH + 0.08), Vector3(WIDTH / 2.0, height / 2.0, 0.0)],
	]
	for bar: Array in bars:
		var mesh := BoxMesh.new()
		mesh.size = bar[0]
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = gold
		node.position = bar[1]
		add_child(node)

	var star := Node3D.new()
	star.position.y = height + 0.62
	var point_mesh := BoxMesh.new()
	point_mesh.size = Vector3(0.24, 0.24, 0.06)
	for angle: float in [0.0, PI / 4.0]:
		var point := MeshInstance3D.new()
		point.mesh = point_mesh
		point.material_override = gold
		point.rotation.z = angle
		star.add_child(point)
	add_child(star)
	var spin := star.create_tween().set_loops()
	spin.tween_property(star, "rotation:y", TAU, 3.0).from(0.0)
	if animated:
		star.scale = Vector3.ONE * 0.1
		star.create_tween().tween_property(star, "scale", Vector3.ONE, 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build() -> void:
	var total_height := TIER_HEIGHT * TIER_COUNT

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, total_height, DEPTH)
	shape.shape = box
	shape.position.y = total_height / 2.0
	add_child(shape)

	# 물류 랙: 파란 기둥에 밝은 선반 판
	var frame_material := _material_for(Color(0.96, 0.92, 0.84))
	var post_material := _material_for(Color(0.3, 0.5, 0.92))

	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(WIDTH, BOARD_THICKNESS, DEPTH)
	for i in TIER_COUNT + 1:
		var board := MeshInstance3D.new()
		board.mesh = board_mesh
		board.material_override = frame_material
		board.position.y = i * TIER_HEIGHT
		add_child(board)

	var side_mesh := BoxMesh.new()
	side_mesh.size = Vector3(0.07, total_height + 0.06, DEPTH + 0.04)
	for x: float in [-WIDTH / 2.0, WIDTH / 2.0]:
		var side := MeshInstance3D.new()
		side.mesh = side_mesh
		side.material_override = post_material
		side.position = Vector3(x, total_height / 2.0, 0.0)
		add_child(side)

	var highlight_material := StandardMaterial3D.new()
	highlight_material.albedo_color = Color(1.0, 0.9, 0.2, 0.35)
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var highlight_mesh := BoxMesh.new()
	highlight_mesh.size = Vector3(WIDTH - 0.06, TIER_HEIGHT - BOARD_THICKNESS, DEPTH + 0.02)
	_highlight = MeshInstance3D.new()
	_highlight.mesh = highlight_mesh
	_highlight.material_override = highlight_material
	add_child(_highlight)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 56
	_label.outline_size = 14
	_label.outline_modulate = Color(0.1, 0.12, 0.22)
	_label.pixel_size = 0.004
	_label.position.y = total_height + 0.25
	add_child(_label)

	_toy_mesh = BoxMesh.new()
	_toy_mesh.size = Vector3.ONE * TOY_VISUAL_SIZE


static func _material_for(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		_materials[color] = material
	return _materials[color]
