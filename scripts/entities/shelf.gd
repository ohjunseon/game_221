class_name Shelf
extends StaticBody3D
## 10단 정리 선반. 아래 단부터 채워지고, 단 높이에 따라 필요한 자세가 다르다.

enum Posture { CROUCH, STAND, JUMP }

const TIER_COUNT := 10
const TIER_HEIGHT := 0.28
const WIDTH := 2.0
const DEPTH := 0.5
const BOARD_THICKNESS := 0.03
const SLOTS_PER_TIER := 10
const TOY_VISUAL_SIZE := 0.16

static var _materials: Dictionary = {}

@export var tier_capacity: int = 10
@export var warehouse_id: int = 1
@export var floor_index: int = 0
@export var shelf_index: int = 0

var stored: int = 0

var _highlight: MeshInstance3D
var _label: Label3D
var _toy_mesh: BoxMesh


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
	_build()
	_refresh()


func capacity() -> int:
	return tier_capacity * TIER_COUNT


func is_full() -> bool:
	return stored >= capacity()


## 지금 채워야 하는 단 (1~10)
func current_tier() -> int:
	@warning_ignore("integer_division")
	return mini(stored / tier_capacity + 1, TIER_COUNT)


func add_toy(color: Color) -> bool:
	if is_full():
		return false
	var tier := current_tier()
	var in_tier := stored - (tier - 1) * tier_capacity
	@warning_ignore("integer_division")
	var step := maxi(1, tier_capacity / SLOTS_PER_TIER)
	if in_tier % step == 0:
		@warning_ignore("integer_division")
		_add_toy_visual(tier, in_tier / step, color)
	stored += 1
	_refresh()
	if is_full():
		EventBus.shelf_completed.emit(warehouse_id, floor_index, shelf_index)
	return true


func _build() -> void:
	var total_height := TIER_HEIGHT * TIER_COUNT

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, total_height, DEPTH)
	shape.shape = box
	shape.position.y = total_height / 2.0
	add_child(shape)

	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.35, 0.42, 0.55)

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
	_label.font_size = 64
	_label.pixel_size = 0.004
	_label.position.y = total_height + 0.25
	add_child(_label)

	_toy_mesh = BoxMesh.new()
	_toy_mesh.size = Vector3.ONE * TOY_VISUAL_SIZE


func _refresh() -> void:
	_label.text = "%d / %d" % [stored, capacity()]
	_highlight.visible = not is_full()
	_highlight.position.y = (current_tier() - 0.5) * TIER_HEIGHT


func _add_toy_visual(tier: int, slot: int, color: Color) -> void:
	var toy := MeshInstance3D.new()
	toy.mesh = _toy_mesh
	toy.material_override = _material_for(color)
	var slot_width := (WIDTH - 0.1) / SLOTS_PER_TIER
	toy.position = Vector3(
		-WIDTH / 2.0 + 0.05 + slot_width * (slot + 0.5),
		(tier - 1) * TIER_HEIGHT + BOARD_THICKNESS / 2.0 + TOY_VISUAL_SIZE / 2.0,
		0.0
	)
	add_child(toy)


static func _material_for(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		_materials[color] = material
	return _materials[color]
