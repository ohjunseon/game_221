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
const HELD_BOX_SIZE := 0.2
const DROPPED_BOX_SIZE := 0.45
## 황금 박스의 코인 배수
const GOLDEN_MULT := 10

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
## 모으는 묶음에 황금 장난감이 섞였는지, 들고 있는 박스 중 황금 박스 수
var golden_loose := false
var golden_boxes: int = 0

## 모으는 장난감·박스가 어느 층 더미에서 왔는지 (key "창고_층"). 버리면 그 층 재고로 돌아간다
var _loose_keys: Array[String] = []
var box_keys: Array[String] = []

var _packed := false
var _box_tween: Tween
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
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if captured:
			drop_one()
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
	# Esc는 HUD가 받아 일시정지 메뉴를 연다


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


## 액션 스킬 발동 (slot 0~2 = 숫자키 1~3)
func use_skill(slot: int) -> bool:
	var id := Skills.ACTION_ORDER[slot]
	var skill_name: String = Skills.DEFS[id]["name"]
	if GameState.level(id) <= 0:
		EventBus.message_shown.emit("%s: 아직 배우지 않았습니다 (Tab)" % skill_name)
		Sfx.play("error")
		return false
	if GameState.cooldown_left(id) > 0.0:
		EventBus.message_shown.emit(
			"%s: 쿨타임 %d초" % [skill_name, ceili(GameState.cooldown_left(id))]
		)
		Sfx.play("error")
		return false
	if id == "magnet":
		return _use_magnet()
	GameState.activate(id)
	EventBus.message_shown.emit("%s 발동!" % skill_name)
	Sfx.play("unlock", 1.6)
	return true


## 자석: 누를 때 한 번, 들고 있는 장난감과 같은 형태를 반경 안에서 손 가득 끌어온다.
## 아무것도 안 들었거나 끌어올 게 없으면 쿨타임을 쓰지 않는다.
func _use_magnet() -> bool:
	var type: int = held_type if loose > 0 else (boxes[-1] if not boxes.is_empty() else -1)
	var capacity := carry_capacity()
	var want := (capacity - boxes.size()) * Toys.BOX_SIZE - loose
	if type < 0:
		EventBus.message_shown.emit("자석: 먼저 장난감을 하나 주우세요")
	elif want <= 0:
		EventBus.message_shown.emit("자석: 손이 가득 찼어요")
	else:
		var pulled := magnet_pull(type, want)
		if pulled > 0:
			GameState.activate("magnet")
			EventBus.message_shown.emit("자석! %s %d개" % [Toys.NAMES[type], pulled])
			Sfx.play("unlock", 1.6)
			return true
		EventBus.message_shown.emit("자석: 주변에 같은 장난감(%s)이 없어요" % Toys.NAMES[type])
	Sfx.play("error")
	return false


## 반경 안의 type 장난감을 최대 limit개 끌어온다. 버린 장난감은 줍지 않는다.
func magnet_pull(type: int, limit: int) -> int:
	var radius := Skills.magnet_radius(GameState.level("magnet"))
	var pulled := 0
	for toy: Node3D in get_tree().get_nodes_in_group("toy"):
		if pulled >= limit:
			break
		if toy.is_queued_for_deletion() or toy.get_meta("dropped", false):
			continue
		if int(toy.get_meta("toy_type", -1)) != type:
			continue
		var offset := toy.global_position - global_position
		if absf(offset.y) > 2.0 or Vector2(offset.x, offset.z).length() > radius:
			continue
		_take(toy, true)
		pulled += 1
	for field in ToyField.all:
		if pulled >= limit:
			break
		for toy in field.take_near(global_position, radius, type, limit - pulled):
			_take(toy, true)
			pulled += 1
	if pulled > 0:
		Sfx.play("pick", 1.0 + 0.08 * loose)
		_refresh_hands()
	return pulled


## 들고 있는 박스를 선반의 현재 단에 넣는다. 자세가 맞아야 한다.
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
	if posture != required:
		if not quiet:
			EventBus.message_shown.emit(
				"%d단: %s" % [shelf.current_tier(), Shelf.posture_text(required)]
			)
			Sfx.play("error")
		return false

	# 선반은 한 종류만 받는다: 정해진 종류가 없으면 마지막 박스의 종류로 정한다
	var box_type: int = boxes[-1] if shelf.shelf_type() < 0 else shelf.shelf_type()
	if not boxes.has(box_type):
		if not quiet:
			EventBus.message_shown.emit("이 선반은 %s 전용입니다" % Toys.NAMES[box_type])
			Sfx.play("error")
		return false
	var matching := boxes.count(box_type)
	var per_box := GameState.toys_per_box()
	var target := shelf.tier_position(shelf.current_tier())
	var used := shelf.add(matching, 1.0, box_type)
	var accepted := used * per_box
	_sync_keys()
	for i in used:
		var index := boxes.rfind(box_type)
		GameState.add_carried(box_keys[index], -Toys.BOX_SIZE)
		boxes.remove_at(index)
		box_keys.remove_at(index)
	# 황금 박스: 이미 받은 1배에 더해 나머지 9배를 준다
	var golden_used := mini(golden_boxes, used)
	golden_boxes -= golden_used
	if golden_used > 0:
		GameState.add_coins(int(ceil(
			golden_used * per_box * (GOLDEN_MULT - 1) * GameState.coin_multiplier()
		)))
	_throw_box(box_type, target, golden_used > 0)
	_refresh_hands()

	var popup := "+%s" % Skills.fmt(accepted)
	if GameState.is_active("jackpot"):
		popup += "  코인 ×%.1f" % GameState.coin_multiplier()
	if golden_used > 0:
		popup += "  황금 박스 ×%d" % GOLDEN_MULT
		Sfx.play("golden")
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
	elif target is Node3D and (target as Node3D).is_in_group("box_item"):
		try_pick_box(target as Node3D, quiet)
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
	var direction := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * reach, RAY_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Object = hit.get("collider")
	# 바닥에 깔린 장난감(그림)이 더 가까우면 그 자리를 진짜 장난감으로 바꿔 돌려준다
	var nearest := reach
	if collider != null:
		nearest = from.distance_to(hit["position"])
	var best_field: ToyField = null
	var best_slot := -1
	var distance := []
	for field in ToyField.all:
		var slot := field.raycast(from, direction, nearest, distance)
		if slot >= 0:
			nearest = distance[0]
			best_field = field
			best_slot = slot
	if best_field != null:
		return best_field.materialize(best_slot)
	return collider


func _update_aim_text() -> void:
	var text := ""
	var target := _raycast()
	if target is Shelf:
		var shelf := target as Shelf
		if shelf.is_full():
			text = "완성된 선반"
		else:
			var tier := shelf.current_tier()
			text = "%d단: %s" % [tier, Shelf.posture_text(Shelf.required_posture(tier))]
		if shelf.shelf_type() >= 0 and not shelf.is_full():
			text = "%s 선반 · %s" % [Toys.NAMES[shelf.shelf_type()], text]
	elif target is Node3D and (target as Node3D).is_in_group("toy"):
		text = "좌클릭: 줍기"
	elif target is Node3D and (target as Node3D).is_in_group("box_item"):
		text = "좌클릭: 박스 줍기"
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
	if loose > 0 or not boxes.is_empty():
		text += "   우클릭: 버리기"
	return text


## fly가 참이면 장난감이 손으로 날아온 뒤 사라진다(자석).
func _take(toy: Node3D, fly: bool = false) -> void:
	held_type = toy.get_meta("toy_type", 0)
	var origin: String = toy.get_meta("floor_key", "")
	GameState.add_carried(origin, 1)
	if toy.get_meta("dropped", false):
		GameState.add_dropped(origin, -1)
	_loose_keys.append(origin)
	if toy.get_meta("golden", false):
		golden_loose = true
		EventBus.popup_requested.emit("황금 장난감!")
		Sfx.play("golden")
	toy.remove_from_group("toy")
	if toy.is_inside_tree():
		# 손으로 빨려 들어온 뒤 사라진다
		(toy as CollisionObject3D).collision_layer = 0
		if toy is RigidBody3D:
			(toy as RigidBody3D).freeze = true
		var tween := toy.create_tween()
		tween.tween_property(
			toy, "global_position", head.global_position + Vector3.DOWN * 0.4, 0.2 if fly else 0.1
		)
		tween.tween_callback(toy.queue_free)
	else:
		toy.queue_free()
	loose += 1
	if loose >= Toys.BOX_SIZE:
		boxes.append(held_type)
		_sync_keys()
		var box_origin := _loose_keys[0]
		for key in _loose_keys:
			GameState.add_carried(key, -1)
		GameState.add_carried(box_origin, Toys.BOX_SIZE)
		box_keys[box_keys.size() - 1] = box_origin
		_loose_keys.clear()
		loose = 0
		held_type = -1
		_packed = true
		if golden_loose:
			golden_loose = false
			golden_boxes += 1
			EventBus.popup_requested.emit("황금 박스 완성!")
		else:
			EventBus.popup_requested.emit("박스 완성!")
		Sfx.play("pack")


## 우클릭: 모으는 장난감이 있으면 한 개, 없으면 박스 한 개를 앞 바닥에 내려놓는다.
## 내려놓은 것은 다시 주울 수 있고, 그 층 바닥 재고로 돌아간다.
func drop_one() -> bool:
	if loose > 0:
		return _drop_toy()
	if not boxes.is_empty():
		return _drop_box()
	return false


func _drop_point() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var from := global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * 1.2, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var distance := 1.0
	if not hit.is_empty():
		distance = maxf(0.3, from.distance_to(hit["position"]) - 0.3)
	return from + forward * distance


## 들고 있던 층 키가 맞지 않게 된 박스 키 배열을 박스 수에 맞춘다 (테스트가 boxes를 직접 바꿔도 안전하게)
func _sync_keys() -> void:
	while box_keys.size() > boxes.size():
		box_keys.pop_back()
	while box_keys.size() < boxes.size():
		box_keys.append("")
	while _loose_keys.size() > loose:
		_loose_keys.pop_back()
	while _loose_keys.size() < loose:
		_loose_keys.append("")


func _drop_toy() -> bool:
	_sync_keys()
	var origin: String = _loose_keys.pop_back()
	var toy := Warehouse.make_toy(true, held_type, false) as RigidBody3D
	toy.set_meta("floor_key", origin)
	toy.set_meta("dropped", true)
	if golden_loose:
		Warehouse.gild_toy(toy)
		golden_loose = false
	get_parent().add_child(toy)
	toy.global_position = _drop_point()
	toy.rotation.y = randf() * TAU
	GameState.add_carried(origin, -1)
	GameState.add_dropped(origin, 1)
	loose -= 1
	if loose == 0:
		held_type = -1
		golden_loose = false
	Sfx.play("pick", 0.7)
	_refresh_hands()
	return true


func _drop_box() -> bool:
	_sync_keys()
	var type: int = boxes.pop_back()
	var origin: String = box_keys.pop_back()
	var golden := golden_boxes > 0
	if golden:
		golden_boxes -= 1
	var item := RigidBody3D.new()
	item.collision_layer = Warehouse.TOY_LAYER
	item.collision_mask = 1
	item.add_to_group("box_item")
	item.set_meta("box_type", type)
	item.set_meta("golden", golden)
	item.set_meta("floor_key", origin)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3.ONE * DROPPED_BOX_SIZE
	shape.shape = box_shape
	shape.position.y = DROPPED_BOX_SIZE / 2.0
	item.add_child(shape)
	var visual := Toys.make_box(type, DROPPED_BOX_SIZE)
	Toys.set_box_golden(visual, golden)
	visual.position.y = DROPPED_BOX_SIZE / 2.0
	item.add_child(visual)
	get_parent().add_child(item)
	item.global_position = _drop_point()
	item.rotation.y = randf() * TAU
	GameState.add_carried(origin, -Toys.BOX_SIZE)
	GameState.add_dropped(origin, Toys.BOX_SIZE)
	Sfx.play("pick", 0.6)
	_refresh_hands()
	return true


## 내려놓은 박스를 다시 줍는다.
func try_pick_box(item: Node3D, quiet: bool = false) -> bool:
	if boxes.size() >= carry_capacity():
		if not quiet:
			EventBus.message_shown.emit("박스를 더 들 수 없습니다. 선반에 넣으세요")
		return false
	_sync_keys()
	var origin: String = item.get_meta("floor_key", "")
	boxes.append(int(item.get_meta("box_type", 0)))
	box_keys.append(origin)
	if item.get_meta("golden", false):
		golden_boxes += 1
	GameState.add_carried(origin, Toys.BOX_SIZE)
	GameState.add_dropped(origin, -Toys.BOX_SIZE)
	item.remove_from_group("box_item")
	item.queue_free()
	Sfx.play("pick")
	_packed = true
	_refresh_hands()
	return true


## 오른손에는 모으는 장난감, 왼손에는 완성한 박스를 보여 준다.
func _refresh_hands() -> void:
	if _held_toy_type != held_type:
		if _held_toy != null:
			if _packed:
				_pack_away(_held_toy)
			else:
				_held_toy.queue_free()
			_held_toy = null
		_held_toy_type = held_type
		if held_type >= 0:
			_held_toy = Toys.make_visual(held_type)
			_held_toy.scale = Vector3.ONE * 0.6
			_held_toy.position = Vector3(0.0, 0.05, -0.28)
			_right_arm.add_child(_held_toy)
	if _held_toy != null and golden_loose and not _held_toy.has_meta("golden"):
		_held_toy.set_meta("golden", true)
		Toys.gild(_held_toy)
	golden_boxes = mini(golden_boxes, boxes.size())
	_held_box.visible = not boxes.is_empty()
	if not boxes.is_empty():
		Toys.set_box_type(_held_box, boxes[-1])
		Toys.set_box_golden(_held_box, golden_boxes > 0)
	if _packed:
		_packed = false
		_pop_box()
	EventBus.carried_changed.emit(boxes.size(), carry_capacity())


## 박스 완성: 오른손의 장난감이 빙글 돌며 왼손 박스 쪽으로 빨려 들어간다.
func _pack_away(toy: Node3D) -> void:
	var tween := toy.create_tween().set_parallel(true)
	tween.tween_property(toy, "rotation:y", TAU * 2.0, 0.22)
	tween.tween_property(toy, "scale", Vector3.ONE * 0.05, 0.22).set_ease(Tween.EASE_IN)
	tween.tween_property(toy, "position", Vector3(-0.6, 0.14, -0.2), 0.22).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(toy.queue_free)


## 왼손 박스가 "뿅" 하고 튀어나온다.
func _pop_box() -> void:
	if _box_tween != null:
		_box_tween.kill()
	_held_box.scale = Vector3.ONE * HELD_BOX_SIZE * 0.2
	_box_tween = create_tween()
	_box_tween.tween_interval(0.12)
	_box_tween.tween_property(_held_box, "scale", Vector3.ONE * HELD_BOX_SIZE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 넣을 때 박스가 왼손에서 선반 칸으로 날아간다.
func _throw_box(type: int, target: Vector3, golden: bool) -> void:
	var box := Toys.make_box(type, HELD_BOX_SIZE)
	Toys.set_box_golden(box, golden)
	get_parent().add_child(box)
	box.global_position = _held_box.global_position
	var tween := box.create_tween().set_parallel(true)
	tween.tween_property(box, "global_position", target, 0.14).set_ease(Tween.EASE_IN)
	tween.tween_property(box, "scale", Vector3.ONE * Shelf.TOY_VISUAL_SIZE, 0.14)
	tween.chain().tween_callback(box.queue_free)


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
	# 파란 작업복 소매, 흰 소맷단, 노란 작업 장갑
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.09, 0.09, 0.45)
	var cuff_mesh := BoxMesh.new()
	cuff_mesh.size = Vector3(0.1, 0.1, 0.03)
	var glove_mesh := BoxMesh.new()
	glove_mesh.size = Vector3(0.105, 0.095, 0.12)
	for side: float in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.mesh = arm_mesh
		arm.material_override = Look.matte(Color(0.3, 0.55, 0.95))
		var cuff := MeshInstance3D.new()
		cuff.mesh = cuff_mesh
		cuff.material_override = Look.matte(Color(0.97, 0.96, 0.92))
		cuff.position.z = -0.12
		arm.add_child(cuff)
		var glove := MeshInstance3D.new()
		glove.mesh = glove_mesh
		glove.material_override = Look.matte(Color(1.0, 0.82, 0.28))
		glove.position.z = -0.19
		arm.add_child(glove)
		arm.position = Vector3(ARM_REST.x * side, ARM_REST.y, ARM_REST.z)
		arm.rotation = Vector3(deg_to_rad(12.0), deg_to_rad(8.0) * side, 0.0)
		camera.add_child(arm)
		if side > 0.0:
			_right_arm = arm
		else:
			_left_arm = arm

	_held_box = Toys.make_box(0, HELD_BOX_SIZE)
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
