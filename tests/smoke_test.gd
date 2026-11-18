extends Node
## 헤드리스 스모크 테스트: 줍기, 자세 규칙, 선반·층·창고 해금, 스킬, 저장, 오프라인 보상.
## 실행: <godot> --headless --path . res://tests/smoke.tscn

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.enabled = false
	Warehouse.golden_chance = 0.0
	GameState.reset()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: Node = main.get_node("Player")
	var warehouses: Array[Warehouse] = main.warehouses
	_check(warehouses.size() == 4, "창고 4동 생성")
	_check(warehouses[0].shelves.size() == 20, "창고당 선반 20개 (2층 × 10)")
	_check(warehouses[0].is_open and not warehouses[1].is_open, "창고 1만 처음부터 열림")

	# 모든 선반은 박스 100개로 같고, 창고마다 선반 수와 크기가 다르다
	var expected_shelves: Array[int] = [20, 80, 100, 200]
	for i in 4:
		_check(
			warehouses[i].shelves.size() == expected_shelves[i],
			"창고 %d: 선반 %d개 (실제 %d)" % [i + 1, expected_shelves[i], warehouses[i].shelves.size()]
		)
	_check(GameState.total_shelves() == 400, "선반 총 400개")
	var all_same := true
	for warehouse in warehouses:
		for each_shelf in warehouse.shelves:
			all_same = all_same and each_shelf.capacity() == 100
	_check(all_same and GameState.BOXES_PER_SHELF == 100, "모든 선반 박스 100개")
	var sizes: Array[Vector2] = []
	for i in 4:
		sizes.append(Warehouse.size_of(i + 1))
	_check(
		sizes[0].x * sizes[0].y < sizes[1].x * sizes[1].y
		and sizes[1].x * sizes[1].y < sizes[2].x * sizes[2].y
		and sizes[2].x * sizes[2].y < sizes[3].x * sizes[3].y,
		"창고 넓이는 1 < 2 < 3 < 4"
	)
	_check(
		GameState.points_for_boxes(9) == 0 and GameState.points_for_boxes(10) == 1
		and GameState.points_for_boxes(30) == 2 and GameState.points_for_boxes(100) == 4
		and GameState.points_for_boxes(40000) == 88,
		"스킬 포인트: 박스 10·30·60·100개마다 (전체 88개)"
	)

	# 바닥 장난감: 창고 1의 1층 재고 4,000개가 전부 창고 안 바닥에 깔린다 (다른 층·잠긴 창고는 없음)
	var field: ToyField = warehouses[0].fields[0]
	_check(field != null and field.alive == 4000 and field.floor_count() == 4000,
		"창고 1 1층 장난감 4,000개가 전부 바닥에 (실제 %d)" % (field.alive if field else -1))
	_check(field != null and field.inside_count == 4000, "창고 1은 전부 창고 안에 들어감")
	_check(warehouses[0].fields[1] == null and warehouses[1].fields[0] == null, "2층·잠긴 창고에는 아직 없음")
	var per_type := {}
	for t: int in field.types:
		per_type[t] = int(per_type.get(t, 0)) + 1
	var multiples := true
	for t: int in per_type:
		multiples = multiples and per_type[t] % Toys.BOX_SIZE == 0
	_check(multiples, "형태별 개수가 4의 배수 (마지막 박스까지 맞음)")
	# 조준: 바닥 장난감을 내려다보면 진짜 장난감으로 바뀌어 잡힌다
	var probe: Vector3 = field.to_global(field.positions[0])
	player.global_position = probe + Vector3(0.0, 0.9, 1.2)
	player.rotation.y = 0.0
	player.head.rotation.x = -atan2(player.head.global_position.y - probe.y - 0.1, 1.2)
	await get_tree().physics_frame
	var aimed: Object = player._raycast()
	_check(aimed is Node3D and (aimed as Node3D).is_in_group("toy") and field.floor_count() == 3999,
		"조준하면 바닥 장난감이 주울 수 있는 장난감이 됨")
	var toys: Array[Node3D] = []
	for slot in 40:
		toys.append(field.materialize(slot))

	_check(Shelf.required_posture(1) == Shelf.Posture.CROUCH, "1단 웅크리기")
	_check(Shelf.required_posture(3) == Shelf.Posture.CROUCH, "3단 웅크리기")
	_check(Shelf.required_posture(4) == Shelf.Posture.STAND, "4단 서서")
	_check(Shelf.required_posture(8) == Shelf.Posture.STAND, "8단 서서")
	_check(Shelf.required_posture(9) == Shelf.Posture.JUMP, "9단 점프")

	# 박스 조합: 같은 형태 4개가 박스 1개
	var by_type := {}
	for toy in toys:
		var type: int = toy.get_meta("toy_type")
		if not by_type.has(type):
			by_type[type] = []
		by_type[type].append(toy)
	var type_a := -1
	var type_b := -1
	for type: int in by_type:
		if type_a < 0 and by_type[type].size() >= 5:
			type_a = type
		elif type_b < 0:
			type_b = type
	_check(type_a >= 0 and type_b >= 0, "장난감 형태가 2종 이상이고 한 종은 5개 이상")
	_check(Toys.count() == 6 and Toys.BOX_SIZE == 4, "장난감 6종, 박스당 4개")

	var shelf := warehouses[0].shelves[0]
	_check(not player.try_place(shelf, Shelf.Posture.CROUCH), "박스 없이는 넣기 불가")
	_check(player.try_pick(by_type[type_a][0]), "줍기")
	_check(player.loose == 1 and player.held_type == type_a, "모으는 중 1/4")
	_check(not player.try_place(shelf, Shelf.Posture.CROUCH), "장난감 1개로는 넣기 불가")
	_check(not player.try_pick(by_type[type_b][0]), "다른 형태는 집을 수 없음")
	for i in range(1, 4):
		player.try_pick(by_type[type_a][i])
	_check(player.boxes.size() == 1 and player.loose == 0, "같은 형태 4개 → 박스 1개")
	_check(not player.try_pick(by_type[type_a][4]), "큰 손 없이는 박스 1개만 들 수 있음")
	_check(not player.try_place(shelf, Shelf.Posture.STAND), "1단은 서서 넣기 불가")
	_check(player.try_place(shelf, Shelf.Posture.CROUCH), "1단 웅크리고 넣기")
	_check(GameState.total_sorted == 4 and GameState.coins >= 4, "박스 1개 = 4개 정리")
	_check(player.boxes.is_empty(), "넣은 뒤 빈손")

	# 바닥 재고는 한정: 창고 1의 1층 = 선반 10개 × 100박스 × 4개 - 이미 넣은 박스 1개
	var ground_before := GameState.ground_toys(1, 0)
	_check(ground_before == 10 * 100 * Toys.BOX_SIZE - Toys.BOX_SIZE, "1층 바닥 장난감 재고 (실제 %d)" % ground_before)
	# 우클릭: 장난감·박스를 내려놓고 다시 줍는다. 재고는 줍고 버린 만큼만 오르내린다
	var fresh: Array = []
	for candidate in get_tree().get_nodes_in_group("toy"):
		if int(candidate.get_meta("toy_type")) == type_a and not candidate.is_queued_for_deletion():
			fresh.append(candidate)
	player.try_pick(fresh[0])
	player.try_pick(fresh[1])
	_check(player.loose == 2 and GameState.ground_toys(1, 0) == ground_before - 2, "줍는 만큼 바닥 재고가 줄어듦")
	_check(player.drop_one() and player.loose == 1, "우클릭: 장난감 한 개 버림")
	_check(player.drop_one() and player.loose == 0 and player.held_type == -1, "다 버리면 빈손")
	_check(GameState.ground_toys(1, 0) == ground_before, "버린 장난감은 바닥 재고로 돌아감")
	var dropped_toy: Node = null
	for candidate in get_tree().get_nodes_in_group("toy"):
		if candidate.get_meta("dropped", false):
			dropped_toy = candidate
	_check(dropped_toy != null and player.try_pick(dropped_toy), "버린 장난감을 다시 주울 수 있음")
	player.drop_one()
	for candidate in get_tree().get_nodes_in_group("toy"):
		if candidate.get_meta("dropped", false):
			candidate.remove_from_group("toy")
			candidate.queue_free()
	GameState.dropped_toys.clear()
	player.boxes.append(type_a)
	_check(player.drop_one() and player.boxes.is_empty(), "우클릭: 박스 한 개 버림")
	var dropped_box: Node = get_tree().get_first_node_in_group("box_item")
	_check(dropped_box != null, "버린 박스가 바닥에 놓임")
	_check(player.try_pick_box(dropped_box) and player.boxes.size() == 1, "버린 박스를 다시 주울 수 있음")
	player.boxes.clear()
	GameState.carried_toys.clear()
	GameState.dropped_toys.clear()

	# 첫 선반을 자세에 맞게 채운다
	var postures_used := {}
	while not shelf.is_full():
		var posture := Shelf.required_posture(shelf.current_tier())
		postures_used[posture] = true
		player.boxes.append(type_a)
		if not player.try_place(shelf, posture):
			break
	_check(
		shelf.is_full() and GameState.total_sorted == shelf.capacity() * Toys.BOX_SIZE,
		"첫 선반 완성: 박스 %d개" % shelf.capacity()
	)
	_check(postures_used.size() == 3, "세 자세 모두 사용")
	_check(GameState.skill_points == 4, "박스 100개 → 스킬 포인트 4 (실제 %d)" % GameState.skill_points)
	GameState.skill_points = 1
	player.boxes.append(type_a)
	_check(not player.try_place(shelf, Shelf.Posture.JUMP), "완성된 선반에는 넣기 불가")
	player.boxes.clear()

	# 액션 스킬: 배우기, 발동, 지속 시간, 쿨타임
	_check(Skills.ACTION_ORDER == ["magnet", "auto_sort", "jackpot"] and Skills.UPGRADE_ORDER.size() == 4,
		"액션 3종(긴 팔 없음), 업그레이드 4종")
	_check(not Skills.DEFS.has("long_arm"), "긴 팔 삭제")
	_check(not GameState.learn("bundle"), "업그레이드는 포인트로 배우지 않음")
	_check(not player.use_skill(2), "배우지 않은 스킬은 발동 불가")
	_check(GameState.learn("jackpot"), "대박 타임 배우기")
	_check(not GameState.learn("magnet"), "포인트 없이는 못 배움")
	var second := warehouses[0].shelves[1]
	player.boxes.append(type_a)
	_check(not player.try_place(second, Shelf.Posture.STAND), "자세가 맞지 않으면 넣기 불가")
	player.boxes.clear()
	_check(player.use_skill(2) and GameState.is_active("jackpot"), "3번 키로 대박 타임 발동")
	_check(not player.use_skill(2), "쿨타임 중에는 다시 발동 불가")
	GameState.now += Skills.duration("jackpot", 1) + 0.1
	_check(
		not GameState.is_active("jackpot") and GameState.cooldown_left("jackpot") > 0.0,
		"지속 시간이 끝나도 쿨타임은 남음"
	)
	GameState.now += Skills.cooldown("jackpot", 1)
	_check(GameState.cooldown_left("jackpot") == 0.0, "쿨타임 끝")

	# 대박 타임: 코인 배수
	GameState.skill_points = 1
	_check(GameState.learn("magnet"), "자석 배우기")
	_check(GameState.learned_count() == 2, "배운 액션 스킬 2개")
	_check(player.use_skill(2), "3번 키로 대박 타임 발동")
	var coins_before := GameState.coins
	player.boxes.append(type_a)
	player.try_place(second, Shelf.required_posture(second.current_tier()))
	var jackpot_coins := int(ceil(Toys.BOX_SIZE * Skills.jackpot_mult(1)))
	_check(GameState.coins - coins_before == jackpot_coins, "대박 타임: 박스 1개에 %d 코인" % jackpot_coins)
	GameState.now += 100.0

	# 자석: 누를 때 한 번, 들고 있는 장난감과 같은 형태를 손 가득 끌어온다
	# 무작위 배치에 기대지 않도록 빈 마당에 형태 0을 6개, 형태 1을 2개 직접 놓는다
	player.global_position = Vector3(30.0, 0.9, 30.0)
	var magnet_toys: Array[Node3D] = []
	for i in 8:
		var magnet_toy := Warehouse.make_toy(false, 0 if i < 6 else 1)
		add_child(magnet_toy)
		magnet_toy.global_position = Vector3(30.5 + 0.3 * i, 0.0, 30.5)
		magnet_toys.append(magnet_toy)
	await get_tree().physics_frame
	_check(player.loose == 0 and player.boxes.is_empty(), "자석을 누르기 전에는 저절로 줍지 않음")
	_check(not player.use_skill(0) and GameState.cooldown_left("magnet") == 0.0,
		"빈손이면 자석 발동 안 함 (쿨타임도 안 씀)")
	player.try_pick(magnet_toys[0], true)
	_check(player.use_skill(0), "1번 키로 자석 발동")
	await get_tree().physics_frame
	_check(player.boxes == [0] and player.loose == 0,
		"자석: 들고 있는 형태만 손 가득(박스 1개) (박스 %s, 낱개 %d)" % [player.boxes, player.loose])
	_check(GameState.cooldown_left("magnet") > 0.0 and not GameState.is_active("magnet"), "자석은 지속 없이 쿨타임만")
	player.boxes.clear()
	player.try_pick(magnet_toys[4], true)
	for i in 10:
		await get_tree().physics_frame
	_check(player.loose == 1, "한 번 발동 뒤에는 계속 끌어오지 않음 (낱개 %d)" % player.loose)
	_check(not player.use_skill(0), "자석 쿨타임 중에는 다시 발동 불가")
	_check(Skills.magnet_radius(10) > Skills.magnet_radius(1) and Skills.cooldown("magnet", 10) < Skills.cooldown("magnet", 1),
		"자석 레벨업: 범위 증가, 쿨타임 감소")
	for toy in magnet_toys:
		if is_instance_valid(toy):
			toy.queue_free()
	player.loose = 0
	player.held_type = -1
	GameState.carried_toys.clear()
	GameState.now += 100.0

	# 황금 장난감: 한 개라도 섞인 박스는 코인 10배
	for i in Toys.BOX_SIZE:
		var golden_toy := Warehouse.make_toy(false, type_a)
		add_child(golden_toy)
		if i == 2:
			Warehouse.gild_toy(golden_toy)
		player.try_pick(golden_toy, true)
	_check(player.boxes.size() == 1 and player.golden_boxes == 1, "황금 장난감이 섞이면 황금 박스")
	coins_before = GameState.coins
	player.try_place(second, Shelf.required_posture(second.current_tier()))
	_check(
		GameState.coins - coins_before == Toys.BOX_SIZE * player.GOLDEN_MULT,
		"황금 박스: 코인 %d배 (실제 +%d)" % [player.GOLDEN_MULT, GameState.coins - coins_before]
	)
	_check(player.golden_boxes == 0, "넣은 뒤 황금 박스 없음")

	# 업그레이드: 포인트 없이 코인으로
	GameState.coins = 0
	_check(not GameState.upgrade("bundle"), "코인 부족하면 강화 불가")
	GameState.coins = 1_000_000_000_000
	for i in 10:
		GameState.upgrade("bundle")
	_check(GameState.level("bundle") == 10, "묶음 정리 Lv10 (실제 %d)" % GameState.level("bundle"))
	_check(GameState.upgrade("big_hands") and player.carry_capacity() == 2, "큰 손 Lv1: 박스 2개 들기")
	_check(not GameState.breakthrough("bundle"), "업그레이드에는 한계 돌파가 없음")

	# 액션 스킬 레벨 한계와 한계 돌파
	for i in 20:
		GameState.upgrade("magnet")
	_check(GameState.level("magnet") == 10, "액션 스킬 레벨 한계 10 (실제 %d)" % GameState.level("magnet"))
	GameState.skill_points = 1
	_check(GameState.breakthrough("magnet") and GameState.cap("magnet") == 20, "한계 돌파로 20")

	# 선반은 한 종류만: 처음 넣은 종류로 정해지고 다른 종류는 거절한다
	var third := warehouses[0].shelves[2]
	_check(third.shelf_type() == -1, "새 선반은 종류가 정해지지 않음")
	player.boxes.append(type_a)
	player.boxes.append(type_b)
	var before := GameState.total_sorted
	player.try_place(third, Shelf.required_posture(third.current_tier()))
	var expected := Toys.BOX_SIZE * Skills.bundle(10)
	_check(third.shelf_type() == type_b, "마지막 박스의 종류가 선반 종류가 됨")
	_check(GameState.total_sorted - before == expected, "묶음 Lv10: 같은 종류 박스 1개만 %d개로 계산" % expected)
	_check(player.boxes.size() == 1 and player.boxes[0] == type_a, "다른 종류 박스는 손에 남음")
	_check(not player.try_place(third, Shelf.required_posture(third.current_tier())), "다른 종류 선반에는 넣기 불가")
	_check(
		GameState.store_in_shelf(1, 0, 2, 100, 1.0, type_a) == 0, "다른 종류는 저장소에서도 거절"
	)
	player.boxes.clear()
	_check(third.stored() == 1 and third.current_tier() == 1, "선반에 박스 1개: 1단")

	# 창고 해금, 문, 와르르
	_check(not GameState.is_warehouse_unlocked(2), "1,000개 전에는 창고 2 잠김")
	warehouses[1].toggle_door()
	_check(not warehouses[1].is_open, "잠긴 창고 문은 안 열림")
	_sort_until(1000)
	_check(GameState.is_warehouse_unlocked(2), "1,000개에 창고 2 개방")
	warehouses[1].toggle_door()
	_check(warehouses[1].is_open, "개방 후 문 열림")
	warehouses[1].toggle_door()
	_check(not warehouses[1].is_open, "문 닫힘")
	_sort_until(5000)
	_check(GameState.is_warehouse_unlocked(3), "5,000개에 창고 3 개방")
	_check(not GameState.wareureu_done, "1만 개 전에는 와르르 없음")
	_sort_until(10000)
	_check(GameState.is_warehouse_unlocked(4), "10,000개에 창고 4 개방")
	_check(GameState.wareureu_done and warehouses[3].is_open, "와르르: 창고 4 문이 열림")
	for i in 100:
		await get_tree().physics_frame
	var rigid_count := 0
	for toy in get_tree().get_nodes_in_group("toy"):
		if toy is RigidBody3D:
			rigid_count += 1
	_check(rigid_count == 240, "와르르 장난감 240개 (실제 %d)" % rigid_count)

	# 열린 창고마다 1층 재고 전부가 깔리고, 창고 안에 다 안 들어가면 문 밖 마당 산으로 넘친다
	await get_tree().create_timer(1.2).timeout
	for i in 4:
		var each: ToyField = warehouses[i].fields[0]
		var expected_toys := maxi(0, GameState.ground_toys(i + 1, 0) - int(GameState.dropped_toys.get(GameState.floor_key(i + 1, 0), 0)))
		_check(each != null and each.alive == expected_toys,
			"창고 %d 1층 바닥 장난감 = 재고 %d (실제 %d)" % [i + 1, expected_toys, each.alive if each else -1])
	var big: ToyField = warehouses[3].fields[0]
	_check(big.inside_count < big.alive and big.inside_count > 15000,
		"창고 4: 안에 %d개, 넘친 %d개는 마당 산" % [big.inside_count, big.alive - big.inside_count])
	# 자석: 바닥 장난감을 같은 형태로 박스 분량씩 끌어온다
	var magnet_field: ToyField = warehouses[0].fields[0]
	player.global_position = magnet_field.to_global(magnet_field.positions[int(magnet_field.inside_count * 0.5)]) + Vector3.UP * 0.9
	player.boxes.clear()
	player.loose = 0
	player.held_type = -1
	GameState.now += 1000.0
	var before_magnet := magnet_field.floor_count()
	player.try_pick(magnet_field.materialize(int(magnet_field.inside_count * 0.5)), true)
	var magnet_type: int = player.held_type
	_check(player.use_skill(0), "자석 발동")
	await get_tree().physics_frame
	_check(player.boxes.size() == player.carry_capacity() and player.boxes.count(magnet_type) == player.boxes.size()
		and before_magnet - magnet_field.floor_count() >= player.boxes.size() * Toys.BOX_SIZE,
		"자석: 바닥에서 같은 형태로 손 가득 (박스 %d/%d, 줄어든 수 %d)" % [
			player.boxes.size(), player.carry_capacity(), before_magnet - magnet_field.floor_count()])
	GameState.now += 1000.0
	player.boxes.clear()
	GameState.carried_toys.clear()
	await get_tree().create_timer(1.1).timeout
	# 자동으로 박스가 정리되면 바닥 장난감도 그만큼 줄어든다
	var before_auto := magnet_field.alive
	GameState.auto_store(50)
	await get_tree().create_timer(1.1).timeout
	_check(magnet_field.alive == GameState.ground_toys(1, 0), "자동 정리만큼 바닥 장난감이 줄어듦 (%d → %d)" % [before_auto, magnet_field.alive])

	# 층 진행: 1층을 다 채워야 2층이 열린다
	_check(not GameState.is_floor_active(1, 1), "1층 완료 전 2층 비활성")
	for shelf_index in GameState.shelves_per_floor(1):
		GameState.store_in_shelf(1, 0, shelf_index, GameState.BOXES_PER_SHELF)
	_check(GameState.is_floor_complete(1, 0) and GameState.is_floor_active(1, 1), "1층 완료 → 2층 활성")
	_check(GameState.floors_completed() == 1, "완료한 층 1개")

	# 저장 왕복
	var saved := JSON.parse_string(JSON.stringify(GameState.to_dict())) as Dictionary
	var total_before := GameState.total_sorted
	var shelves_before := GameState.shelves_completed()
	GameState.reset()
	_check(GameState.total_sorted == 0 and GameState.level("bundle") == 0, "초기화")
	var points_before := int(saved["skill_points"])
	saved["skill_levels"]["long_arm"] = 15
	saved["skill_caps"]["long_arm"] = 20
	GameState.from_dict(saved)
	_check(GameState.skill_points == points_before + 2 and not GameState.skill_caps.has("long_arm"),
		"옛 저장의 긴 팔 포인트 2개 환급")
	GameState.skill_points = points_before
	_check(GameState.total_sorted == total_before, "저장 왕복: 정리 수 유지")
	_check(GameState.shelves_completed() == shelves_before, "저장 왕복: 선반 상태 유지")
	_check(GameState.level("bundle") == 10 and GameState.cap("magnet") == 20, "저장 왕복: 스킬 유지")
	_check(not GameState.is_active("jackpot"), "발동 상태는 저장되지 않음")

	# 자동 정리: 켜져 있는 동안만 선반이 채워진다
	GameState.skill_points = 1
	GameState.learn("auto_sort")
	total_before = GameState.total_sorted
	for i in 20:
		await get_tree().process_frame
	_check(GameState.total_sorted == total_before, "자동 정리를 켜기 전에는 그대로")
	_check(player.use_skill(1), "2번 키로 자동 정리 발동")
	GameState._auto_accum = 1.0
	for i in 60:
		await get_tree().process_frame
	_check(GameState.total_sorted > total_before, "자동 정리 사용 중 선반이 채워짐")
	GameState.now += 100.0

	# 오프라인 보상
	var rate := GameState.auto_average_rate()
	_check(rate > 0.0 and rate < GameState.auto_rate(), "평균 자동 정리 속도는 쿨타임만큼 낮음")
	GameState.saved_at = 1_000_000
	total_before = GameState.total_sorted
	var gained := SaveManager.apply_offline_reward(1_000_000 + 600)
	var offline_boxes := int(rate * 600 * GameState.OFFLINE_EFFICIENCY)
	_check(
		gained == offline_boxes * GameState.toys_per_box(),
		"오프라인 10분 보상: 박스 %d개 (실제 %d개 정리)" % [offline_boxes, gained]
	)
	_check(GameState.total_sorted == total_before + gained, "오프라인 보상이 정리 수에 반영")
	_check(SaveManager.apply_offline_reward(1_000_000 + 30) == 0, "1분 미만은 보상 없음")

	# 끝까지: 1,000만 개
	var completed := [false]
	EventBus.game_completed.connect(func() -> void: completed[0] = true)
	GameState.unlocked_warehouses = [1, 2, 3, 4]
	# 박스 1개에 장난감이 충분히 담기도록 묶음 정리를 높여 둔다
	GameState.skill_levels["bundle"] = 20
	GameState.auto_store(GameState.total_shelves() * GameState.BOXES_PER_SHELF)
	_check(GameState.total_sorted >= GameState.TOTAL_TOYS, "1,000만 개 정리 (실제 %d)" % GameState.total_sorted)
	_check(
		GameState.shelves_completed() == 400 and GameState.floors_completed() == 8,
		"선반 400개·8개 층 완료 (실제 선반 %d, 층 %d)" % [
			GameState.shelves_completed(), GameState.floors_completed()
		]
	)
	_check(completed[0], "완료 시그널 발생")
	_check(QuestManager.current().is_empty(), "모든 퀘스트 완료")

	# 엔딩: 곰 반장 카드 → 거대 상자 낙하 → 잠에서 깨는 카드 → 완료 패널
	var hud: Node = main.get_node("HUD")
	await get_tree().create_timer(hud.ENDING_DELAY + 0.2).timeout
	var story := _find_story(hud)
	_check(story != null and story.cards == Story.ENDING_BEFORE_BOX, "엔딩 앞부분 카드가 뜸")
	_check(GameState.menu_open, "엔딩 카드 동안 조작 멈춤")
	var landed := [false]
	EventBus.ending_box_landed.connect(func() -> void: landed[0] = true)
	if story != null:
		story.finish()
	await get_tree().create_timer(main.ENDING_FALL_SECONDS + 0.3).timeout
	_check(landed[0], "거대 상자가 떨어져 땅에 닿음")
	story = _find_story(hud)
	_check(story != null and story.cards == Story.ENDING_AFTER_BOX, "잠에서 깨는 카드가 뜸")
	if story != null:
		story.finish()
	_check(hud._ending_panel.visible, "엔딩 뒤 완료 패널 (계속 플레이 / 시작 화면)")
	hud._close_ending_panel()
	_check(not GameState.menu_open, "계속 플레이로 다시 조작 가능")

	# ESC 메뉴
	hud._set_pause_open(true)
	_check(hud._pause.visible and GameState.menu_open, "ESC 메뉴가 열리고 조작 멈춤")
	hud._set_pause_open(false)

	# 저장 한 칸: 저장 → 불러오기 → 새 게임은 저장을 지운다 (테스트 전용 파일)
	SaveManager.save_path = "user://smoke_save.json"
	SaveManager.enabled = true
	var sorted_saved := GameState.total_sorted
	_check(SaveManager.save_game() and SaveManager.has_save(), "저장하면 이어하기 가능")
	GameState.total_sorted = 0
	_check(SaveManager.load_game() and GameState.total_sorted == sorted_saved, "불러오면 정리 수 복원")
	var title: Control = load("res://scenes/title.tscn").instantiate()
	add_child(title)
	_check(not title.continue_button.disabled, "시작 화면: 저장이 있으면 이어하기 켜짐")
	title._on_new_game()
	_check(title.confirm.visible, "저장이 있으면 새 게임 확인 팝업")
	title.start_new_game()
	_check(not SaveManager.has_save() and GameState.total_sorted == 0, "새 게임은 저장을 지우고 처음부터")
	var opening := _find_story(title)
	_check(opening != null and opening.cards == Story.OPENING, "새 게임은 오프닝 카드부터")
	if opening != null:
		opening.finished.disconnect(title._enter_game)
		opening.finish()
	title.queue_free()
	SaveManager.enabled = false
	SaveManager.in_game = false
	SaveManager.save_path = SaveManager.SAVE_PATH

	await get_tree().physics_frame
	print("SMOKE %s (%d checks, %d failures)" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _failures
	])
	get_tree().quit(0 if _failures == 0 else 1)


## 정리한 장난감 수가 target에 닿을 때까지 자동 정리로 박스를 채운다.
func _sort_until(target: int) -> void:
	var per_box := GameState.toys_per_box()
	GameState.auto_store(maxi(0, ceili(float(target - GameState.total_sorted) / per_box)))


func _find_story(parent: Node) -> Story:
	for child in parent.get_children():
		if child is Story and not child.is_queued_for_deletion():
			return child
	return null


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("FAIL: %s" % description)
