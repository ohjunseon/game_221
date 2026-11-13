extends CharacterBody3D
## 1인칭 플레이어. WASD 이동, Space 점프, Shift 웅크리기, 마우스 시점.
## 좌클릭으로 장난감을 줍고, 선반에 넣고, 문을 여닫는다.

const WALK_SPEED := 5.0
const CROUCH_SPEED := 2.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const STAND_HEAD_Y := 0.7
const CROUCH_HEAD_Y := 0.1
const CROUCH_LERP_SPEED := 10.0
## 1: 바닥·선반·문, 2: 장난감
const RAY_MASK := 3
const ARM_REST := Vector3(0.32, -0.42, -0.55)

const ACTIONS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"crouch": KEY_SHIFT,
}

var is_crouching := false
## 지금 모으는 장난감 형태 (-1이면 없음)와 모은 개수 (0~3)
var held_type: int = -1
var loose: int = 0
## 완성해서 들고 있는 박스들의 장난감 형태
var boxes: Array[int] = []

var _aim_text := ""
var _repeat_timer := 0.0
var _shake := 0.0
var _held_toy: Node3D
var _held_toy_type: int = -1
var _held_box: MeshInstance3D
var _left_arm: MeshInstance3D
var _right_arm: MeshInstance3D
var _arm_tween: Tween

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera


func _ready() -> void:
	_ensure_actions()
	_build_arms()
	floor_snap_length = 0.3
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.shake_requested.connect(func(strength: float) -> void: _shake = maxf(_shake, strength))


func _unhandled_input(event: InputEvent) -> void:
	if GameState.menu_open:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if captured:
			_interact(false)
			_repeat_timer = Skills.repeat_interval(GameState.level("quick_hands"))
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif (
		event is InputEventKey and event.pressed and not event.echo
		and event.physical_keycode >= KEY_1
		and event.physical_keycode < KEY_1 + Skills.ACTION_ORDER.size()
	):
		use_skill(event.physical_keycode - KEY_1)
	elif event.is_action_pressed("ui_cancel"):
		# Esc: 마우스 잠금 해제
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Vector2.ZERO
	if GameState.menu_open:
		is_crouching = false
	else:
		is_crouching = Input.is_action_pressed("crouch") and is_on_floor()
		if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
			velocity.y = JUMP_VELOCITY
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		_update_repeat(delta)
	_update_magnet()

	var target_head_y := CROUCH_HEAD_Y if is_crouching else STAND_HEAD_Y
	head.position.y = lerpf(head.position.y, target_head_y, CROUCH_LERP_SPEED * delta)

	var speed := CROUCH_SPEED if is_crouching else WALK_SPEED
	speed *= Skills.speed_mult(GameState.level("sprint"))
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	move_and_slide()
	_update_shake(delta)
	_update_aim_text()


func get_posture() -> Shelf.Posture:
	if not is_on_floor():
		return Shelf.Posture.JUMP
	if is_crouching:
		return Shelf.Posture.CROUCH
	return Shelf.Posture.STAND


func carry_capacity() -> int:
	return Skills.carry(GameState.level("big_hands"))


## 장난감을 집는다. 한 번에 한 형태만 모을 수 있고, 같은 형태 4개가 모이면 박스가 된다.
func try_pick(toy: Node3D, quiet: bool = false) -> bool:
	var capacity := carry_capacity()
	if boxes.size() >= capacity:
		if not quiet:
			EventBus.message_shown.emit("박스를 더 들 수 없습니다. 선반에 넣으세요")
		return false
	var type: int = toy.get_meta("toy_type", 0)
	if loose > 0 and type != held_type:
		if not quiet:
			EventBus.message_shown.emit("지금은 %s만 모을 수 있습니다 (%d/%d)" % [
				Toys.NAMES[held_type], loose, Toys.BOX_SIZE
			])
			Sfx.play("error")
		return false
	_take(toy)
	Sfx.play("pick", 1.0 + 0.08 * loose)
	_punch_arm()
	_refresh_hands()
	return true


## 액션 스킬 발동 (slot 0~3 = 숫자키 1~4)
func use_skill(slot: int) -> bool:
	var id := Skills.ACTION_ORDER[slot]
	var skill_name: String = Skills.DEFS[id]["name"]
	if GameState.level(id) <= 0:
		EventBus.message_shown.emit("%s: 아직 배우지 않았습니다 (Tab)" % skill_name)
		Sfx.play("error")
		return false
	if not GameState.activate(id):
		EventBus.message_shown.emit(
			"%s: 쿨타임 %d초" % [skill_name, ceili(GameState.cooldown_left(id))]
		)
		Sfx.play("error")
		return false
	EventBus.message_shown.emit("%s 발동!" % skill_name)
	Sfx.play("unlock", 1.6)
	return true


## 자석이 켜져 있는 동안 주변 장난감이 손으로 날아온다. 모으는 형태가 있으면 그 형태만.
func _update_magnet() -> void:
	if not GameState.is_active("magnet"):
		return
	var capacity := carry_capacity()
	var radius := Skills.magnet_radius(GameState.level("magnet"))
	var took := false
	for toy: Node3D in get_tree().get_nodes_in_group("toy"):
		if boxes.size() >= capacity:
			break
		if toy.is_queued_for_deletion():
			continue
		if loose > 0 and int(toy.get_meta("toy_type", -1)) != held_type:
			continue
		var offset := toy.global_position - global_position
		if absf(offset.y) > 2.0 or Vector2(offset.x, offset.z).length() > radius:
			continue
		_take(toy, true)
		took = true
	if took:
		Sfx.play("pick", 1.0 + 0.08 * loose)
		_refresh_hands()


## 들고 있는 박스를 선반의 현재 단에 넣는다. 긴 팔이 켜져 있지 않으면 자세가 맞아야 한다.
func try_place(shelf: Shelf, posture: Shelf.Posture, quiet: bool = false) -> bool:
	if boxes.is_empty():
		if not quiet:
			EventBus.message_shown.emit(
				"먼저 박스를 만드세요 (같은 장난감 %d개)" % Toys.BOX_SIZE
			)
		return false
	if shelf.is_full():
		if not quiet:
			EventBus.message_shown.emit("가득 찬 선반입니다")
		return false
	var required := Shelf.required_posture(shelf.current_tier())
	if not GameState.is_active("long_arm") and posture != required:
		if not quiet:
			EventBus.message_shown.emit(
				"%d단: %s" % [shelf.current_tier(), Shelf.posture_text(required)]
			)
			Sfx.play("error")
		return false

	var per_box := Toys.BOX_SIZE * Skills.bundle(GameState.level("bundle"))
	var accepted := shelf.add(boxes.size() * per_box, 1.0, boxes[-1])
	for i in mini(ceili(float(accepted) / per_box), boxes.size()):
		boxes.pop_back()
	_refresh_hands()

	var popup := "+%s" % Skills.fmt(accepted)
	if GameState.is_active("jackpot"):
		popup += "  코인 ×%.1f" % GameState.coin_multiplier()
	EventBus.popup_requested.emit(popup)
	Sfx.play("place")
	_punch_arm()
	return true


func _interact(quiet: bool) -> void:
	var target := _raycast()
	if target is Shelf:
		try_place(target as Shelf, get_posture(), quiet)
	elif target is Node3D and (target as Node3D).is_in_group("toy"):
		try_pick(target as Node3D, quiet)
	elif target is Node3D and (target as Node3D).is_in_group("door") and not quiet:
		((target as Node3D).get_meta("warehouse") as Warehouse).toggle_door()


## 빠른 손: 마우스를 누르고 있으면 일정 간격으로 반복한다.
func _update_repeat(delta: float) -> void:
	var interval := Skills.repeat_interval(GameState.level("quick_hands"))
	if interval <= 0.0 or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_repeat_timer -= delta
	if _repeat_timer <= 0.0:
		_repeat_timer = interval
		_interact(true)


func _raycast() -> Object:
	var from := camera.global_position
	var reach := Skills.BASE_REACH
	if GameState.is_active("long_arm"):
		reach = Skills.reach(GameState.level("long_arm"))
	var to := from - camera.global_basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider")


func _update_aim_text() -> void:
	var text := ""
	var target := _raycast()
	if target is Shelf:
		var shelf := target as Shelf
		if shelf.is_full():
			text = "완성된 선반"
		elif GameState.is_active("long_arm"):
			text = "%d단: 좌클릭으로 넣기" % shelf.current_tier()
		else:
			var tier := shelf.current_tier()
			text = "%d단: %s" % [tier, Shelf.posture_text(Shelf.required_posture(tier))]
	elif target is Node3D and (target as Node3D).is_in_group("toy"):
		text = "좌클릭: 줍기"
	elif target is Node3D and (target as Node3D).is_in_group("door"):
		text = "좌클릭: 문 열기/닫기"
	if text != _aim_text:
		_aim_text = text
		EventBus.aim_text_changed.emit(text)


## HUD에 보여 줄 손 상태
func carry_text() -> String:
	var text := "박스 %d / %d" % [boxes.size(), carry_capacity()]
	if loose > 0:
		text += "   모으는 중: %s %d / %d" % [Toys.NAMES[held_type], loose, Toys.BOX_SIZE]
	else:
		text += "   같은 장난감 %d개 = 박스 1개" % Toys.BOX_SIZE
	return text


## fly가 참이면 장난감이 손으로 날아온 뒤 사라진다(자석).
func _take(toy: Node3D, fly: bool = false) -> void:
	held_type = toy.get_meta("toy_type", 0)
	toy.remove_from_group("toy")
	if fly:
		(toy as CollisionObject3D).collision_layer = 0
		if toy is RigidBody3D:
			(toy as RigidBody3D).freeze = true
		var tween := toy.create_tween()
		tween.tween_property(toy, "global_position", head.global_position + Vector3.DOWN * 0.4, 0.2)
		tween.tween_callback(toy.queue_free)
	else:
		toy.queue_free()
	loose += 1
	if loose >= Toys.BOX_SIZE:
		boxes.append(held_type)
		loose = 0
		held_type = -1
		EventBus.popup_requested.emit("박스 완성!")
		Sfx.play("buy")


## 오른손에는 모으는 장난감, 왼손에는 완성한 박스를 보여 준다.
func _refresh_hands() -> void:
	if _held_toy_type != held_type:
		if _held_toy != null:
			_held_toy.queue_free()
			_held_toy = null
		_held_toy_type = held_type
		if held_type >= 0:
			_held_toy = Toys.make_visual(held_type)
			_held_toy.scale = Vector3.ONE * 0.6
			_held_toy.position = Vector3(0.0, 0.05, -0.28)
			_right_arm.add_child(_held_toy)
	_held_box.visible = not boxes.is_empty()
	if not boxes.is_empty():
		Toys.set_box_type(_held_box, boxes[-1])
	EventBus.carried_changed.emit(boxes.size(), carry_capacity())


func _update_shake(delta: float) -> void:
	if _shake <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		return
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.06
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.06
	_shake = move_toward(_shake, 0.0, delta * 2.0)


func _punch_arm() -> void:
	if _arm_tween != null:
		_arm_tween.kill()
	_arm_tween = create_tween()
	_arm_tween.tween_property(_right_arm, "position", ARM_REST + Vector3(-0.1, 0.08, -0.25), 0.06)
	_arm_tween.tween_property(_right_arm, "position", ARM_REST, 0.12)


## 화면에 보이는 두 팔(로우폴리 상자)과 손에 든 장난감
func _build_arms() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.95, 0.78, 0.62)
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.09, 0.09, 0.45)
	for side: float in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.mesh = arm_mesh
		arm.material_override = skin
		arm.position = Vector3(ARM_REST.x * side, ARM_REST.y, ARM_REST.z)
		arm.rotation = Vector3(deg_to_rad(12.0), deg_to_rad(8.0) * side, 0.0)
		camera.add_child(arm)
		if side > 0.0:
			_right_arm = arm
		else:
			_left_arm = arm

	_held_box = Toys.make_box(0, 0.2)
	_held_box.position = Vector3(0.0, 0.14, -0.2)
	_held_box.visible = false
	_left_arm.add_child(_held_box)


func _ensure_actions() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key_event := InputEventKey.new()
		key_event.physical_keycode = ACTIONS[action]
		InputMap.action_add_event(action, key_event)
