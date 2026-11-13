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
const COMBO_WINDOW := 3.0
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
## 들고 있는 장난감 수
var carried: int = 0
var held_color := Color.WHITE

var _aim_text := ""
var _repeat_timer := 0.0
var _combo: int = 0
var _last_place_time := -100.0
var _shake := 0.0
var _held_visual: MeshInstance3D
var _held_material: StandardMaterial3D
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


## 장난감을 집는다. 자석 스킬이 있으면 주변 것도 함께 집는다.
func try_pick(toy: Node3D, quiet: bool = false) -> bool:
	var capacity := carry_capacity()
	if carried >= capacity:
		if not quiet:
			EventBus.message_shown.emit("손이 가득 찼습니다. 선반에 넣으세요")
		return false
	var center := toy.global_position
	_take(toy)
	var radius := Skills.magnet_radius(GameState.level("magnet"))
	if radius > 0.0:
		for other: Node3D in get_tree().get_nodes_in_group("toy"):
			if carried >= capacity:
				break
			if other.is_queued_for_deletion():
				continue
			if other.global_position.distance_to(center) <= radius:
				_take(other)
	Sfx.play("pick", 1.0 + 0.03 * carried)
	_punch_arm()
	_set_carried(carried)
	return true


## 들고 있는 장난감을 선반의 현재 단에 넣는다. 긴 팔 스킬이 없으면 자세가 맞아야 한다.
func try_place(shelf: Shelf, posture: Shelf.Posture, quiet: bool = false) -> bool:
	if carried <= 0:
		if not quiet:
			EventBus.message_shown.emit("먼저 장난감을 주우세요")
		return false
	if shelf.is_full():
		if not quiet:
			EventBus.message_shown.emit("가득 찬 선반입니다")
		return false
	var required := Shelf.required_posture(shelf.current_tier())
	if GameState.level("long_arm") <= 0 and posture != required:
		if not quiet:
			EventBus.message_shown.emit(
				"%d단: %s" % [shelf.current_tier(), Shelf.posture_text(required)]
			)
			Sfx.play("error")
		return false

	var now := Time.get_ticks_msec() / 1000.0
	_combo = mini(_combo + 1, Skills.MAX_COMBO) if now - _last_place_time <= COMBO_WINDOW else 0
	_last_place_time = now
	var coin_mult := 1.0 + _combo * Skills.combo_step(GameState.level("combo"))
	var is_crit := randf() < Skills.crit_chance(GameState.level("critical"))
	if is_crit:
		coin_mult *= Skills.CRIT_MULTIPLIER

	var bundle := Skills.bundle(GameState.level("bundle"))
	var accepted := shelf.add(carried * bundle, coin_mult, held_color)
	_set_carried(carried - ceili(float(accepted) / bundle))

	var popup := "+%s" % Skills.fmt(accepted)
	if is_crit:
		popup += " 크리티컬!"
	if _combo > 0 and GameState.level("combo") > 0:
		popup += " 콤보 %d" % _combo
	EventBus.popup_requested.emit(popup)
	Sfx.play("place", 1.0 + 0.04 * _combo)
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
	var reach := Skills.reach(GameState.level("long_arm"))
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
		elif GameState.level("long_arm") > 0:
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


func _take(toy: Node3D) -> void:
	held_color = toy.get_meta("color", Color.WHITE)
	toy.remove_from_group("toy")
	toy.queue_free()
	carried += 1


func _set_carried(value: int) -> void:
	carried = maxi(value, 0)
	_held_visual.visible = carried > 0
	_held_material.albedo_color = held_color
	EventBus.carried_changed.emit(carried, carry_capacity())


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

	var toy_mesh := BoxMesh.new()
	toy_mesh.size = Vector3.ONE * 0.16
	_held_material = StandardMaterial3D.new()
	_held_visual = MeshInstance3D.new()
	_held_visual.mesh = toy_mesh
	_held_visual.material_override = _held_material
	_held_visual.position = Vector3(0.0, 0.1, -0.3)
	_held_visual.visible = false
	_right_arm.add_child(_held_visual)


func _ensure_actions() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key_event := InputEventKey.new()
		key_event.physical_keycode = ACTIONS[action]
		InputMap.action_add_event(action, key_event)
