extends CharacterBody3D
## 1인칭 플레이어. WASD 이동, Space 점프, Shift 웅크리기, 마우스 시점.

const WALK_SPEED := 5.0
const CROUCH_SPEED := 2.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const STAND_HEAD_Y := 0.7
const CROUCH_HEAD_Y := 0.1
const CROUCH_LERP_SPEED := 10.0

const ACTIONS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"crouch": KEY_SHIFT,
}

const REACH := 3.0
## 1: 바닥·선반, 2: 장난감
const RAY_MASK := 3

var is_crouching := false
var holding := false
var held_color := Color.WHITE

var _aim_text := ""
var _held_visual: MeshInstance3D
var _held_material: StandardMaterial3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera


func _ready() -> void:
	_ensure_actions()
	_build_held_visual()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		_interact()
	elif event.is_action_pressed("ui_cancel"):
		# Esc: 마우스 잠금 해제/재잠금
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	is_crouching = Input.is_action_pressed("crouch") and is_on_floor()
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY

	var target_head_y := CROUCH_HEAD_Y if is_crouching else STAND_HEAD_Y
	head.position.y = lerpf(head.position.y, target_head_y, CROUCH_LERP_SPEED * delta)

	var speed := CROUCH_SPEED if is_crouching else WALK_SPEED
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	move_and_slide()
	_update_aim_text()


func get_posture() -> Shelf.Posture:
	if not is_on_floor():
		return Shelf.Posture.JUMP
	if is_crouching:
		return Shelf.Posture.CROUCH
	return Shelf.Posture.STAND


## 장난감 하나를 집는다. 이미 들고 있으면 실패.
func try_pick(toy: Node3D) -> bool:
	if holding:
		EventBus.message_shown.emit("이미 들고 있습니다. 선반에 넣으세요")
		return false
	held_color = toy.get_meta("color", Color.WHITE)
	toy.queue_free()
	_set_holding(true)
	return true


## 들고 있는 장난감을 선반의 현재 단에 넣는다. 자세가 맞아야 한다.
func try_place(shelf: Shelf, posture: Shelf.Posture) -> bool:
	if not holding:
		EventBus.message_shown.emit("먼저 장난감을 주우세요")
		return false
	if shelf.is_full():
		EventBus.message_shown.emit("가득 찬 선반입니다")
		return false
	var required := Shelf.required_posture(shelf.current_tier())
	if posture != required:
		EventBus.message_shown.emit(
			"%d단: %s" % [shelf.current_tier(), Shelf.posture_text(required)]
		)
		return false
	shelf.add_toy(held_color)
	_set_holding(false)
	GameState.add_sorted(1)
	GameState.add_coins(1)
	return true


func _interact() -> void:
	var target := _raycast()
	if target is Shelf:
		try_place(target as Shelf, get_posture())
	elif target is Node3D and (target as Node3D).is_in_group("toy"):
		try_pick(target as Node3D)


func _raycast() -> Object:
	var from := camera.global_position
	var to := from - camera.global_basis.z * REACH
	var query := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider")


func _update_aim_text() -> void:
	var text := ""
	var target := _raycast()
	if target is Shelf:
		var shelf := target as Shelf
		if shelf.is_full():
			text = "가득 찬 선반"
		else:
			var tier := shelf.current_tier()
			text = "%d단: %s" % [tier, Shelf.posture_text(Shelf.required_posture(tier))]
	elif target is Node3D and (target as Node3D).is_in_group("toy") and not holding:
		text = "좌클릭: 줍기"
	if text != _aim_text:
		_aim_text = text
		EventBus.aim_text_changed.emit(text)


func _set_holding(value: bool) -> void:
	holding = value
	_held_visual.visible = value
	_held_material.albedo_color = held_color


func _build_held_visual() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.2
	_held_material = StandardMaterial3D.new()
	_held_visual = MeshInstance3D.new()
	_held_visual.mesh = mesh
	_held_visual.material_override = _held_material
	_held_visual.position = Vector3(0.3, -0.25, -0.6)
	_held_visual.visible = false
	camera.add_child(_held_visual)


func _ensure_actions() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key_event := InputEventKey.new()
		key_event.physical_keycode = ACTIONS[action]
		InputMap.action_add_event(action, key_event)
