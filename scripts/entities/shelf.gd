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


func _celebrate() -> void:
	var particles := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.08
	particles.mesh = mesh
	var spark := StandardMaterial3D.new()
	spark.albedo_color = Color(1.0, 0.85, 0.2)
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particles.material_override = spark
	particles.one_shot = true
	particles.amount = 48
	particles.lifetime = 1.2
	particles.explosiveness = 0.95
	particles.direction = Vector3.UP
	particles.spread = 50.0
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 7.0
	particles.color = Color(1.0, 0.85, 0.2)
	particles.position.y = TIER_HEIGHT * TIER_COUNT
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(2.5).timeout.connect(particles.queue_free)
	Sfx.play("complete")


func _build() -> void:
	var total_height := TIER_HEIGHT * TIER_COUNT

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, total_height, DEPTH)
	shape.shape = box
	shape.position.y = total_height / 2.0
	add_child(shape)

	var frame_material := _material_for(Color(0.35, 0.42, 0.55))

	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(WIDTH, BOARD_THICKNESS, DEPTH)
	for i in TIER_COUNT + 1:
		var board := MeshInstance3D.new()
		board.mesh = board_mesh
		board.material_override = frame_material
		board.position.y = i * TIER_HEIGHT
		add_child(board)

	var side_mesh := BoxMesh.new()
	side_mesh.size = Vector3(0.04, total_height, DEPTH)
	for x: float in [-WIDTH / 2.0, WIDTH / 2.0]:
		var side := MeshInstance3D.new()
		side.mesh = side_mesh
		side.material_override = frame_material
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
