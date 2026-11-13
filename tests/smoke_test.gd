extends Node
## 헤드리스 스모크 테스트: 줍기, 자세 규칙, 선반·층·창고 해금, 스킬, 저장, 오프라인 보상.
## 실행: <godot> --headless --path . res://tests/smoke.tscn

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	SaveManager.enabled = false
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

	var capacity_sum := 0
	for capacity in GameState.SHELF_CAPACITIES:
		capacity_sum += capacity
	_check(capacity_sum * 8 == GameState.TOTAL_TOYS, "선반 용량 합계 = 1,000만")

	var toys := get_tree().get_nodes_in_group("toy")
	_check(toys.size() == Warehouse.TOY_TARGET, "창고 1의 1층에만 장난감 (실제 %d)" % toys.size())

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

	# 첫 선반을 자세에 맞게 채운다
	var postures_used := {}
	while not shelf.is_full():
		var posture := Shelf.required_posture(shelf.current_tier())
		postures_used[posture] = true
		player.boxes.append(type_a)
		if not player.try_place(shelf, posture):
			break
	_check(shelf.is_full() and GameState.total_sorted == shelf.capacity(), "첫 선반 완성")
	_check(postures_used.size() == 3, "세 자세 모두 사용")
	_check(GameState.skill_points == 1, "선반 완성 시 스킬 포인트 1")
	player.boxes.append(type_a)
	_check(not player.try_place(shelf, Shelf.Posture.JUMP), "완성된 선반에는 넣기 불가")
	player.boxes.clear()

	# 액션 스킬: 배우기, 발동, 지속 시간, 쿨타임
	_check(Skills.ACTION_ORDER.size() == 4 and Skills.UPGRADE_ORDER.size() == 4, "액션 4종, 업그레이드 4종")
	_check(not GameState.learn("bundle"), "업그레이드는 포인트로 배우지 않음")
	_check(not player.use_skill(1), "배우지 않은 스킬은 발동 불가")
	_check(GameState.learn("long_arm"), "긴 팔 배우기")
	_check(not GameState.learn("magnet"), "포인트 없이는 못 배움")
	var second := warehouses[0].shelves[1]
	player.boxes.append(type_a)
	_check(not player.try_place(second, Shelf.Posture.STAND), "긴 팔을 켜지 않으면 자세 필요")
	_check(player.use_skill(1) and GameState.is_active("long_arm"), "2번 키로 긴 팔 발동")
	_check(player.try_place(second, Shelf.Posture.STAND), "긴 팔 사용 중: 1단도 서서 넣기")
	_check(not player.use_skill(1), "쿨타임 중에는 다시 발동 불가")
	GameState.now += Skills.duration("long_arm", 1) + 0.1
	_check(
		not GameState.is_active("long_arm") and GameState.cooldown_left("long_arm") > 0.0,
		"지속 시간이 끝나도 쿨타임은 남음"
	)
	GameState.now += Skills.cooldown("long_arm", 1)
	_check(GameState.cooldown_left("long_arm") == 0.0 and player.use_skill(1), "쿨타임 뒤 다시 발동")
	GameState.now += 100.0

	# 대박 타임: 코인 배수
	GameState.skill_points = 2
	_check(GameState.learn("jackpot") and GameState.learn("magnet"), "대박 타임·자석 배우기")
	_check(GameState.learned_count() == 3, "배운 액션 스킬 3개")
	_check(player.use_skill(3), "4번 키로 대박 타임 발동")
	var coins_before := GameState.coins
	player.boxes.append(type_a)
	player.try_place(second, Shelf.required_posture(second.current_tier()))
	var jackpot_coins := int(ceil(Toys.BOX_SIZE * Skills.jackpot_mult(1)))
	_check(GameState.coins - coins_before == jackpot_coins, "대박 타임: 박스 1개에 %d 코인" % jackpot_coins)
	GameState.now += 100.0

	# 자석: 켜 두면 주변 장난감이 손으로 들어온다
	player.global_position = Vector3(0.0, 0.9, -24.0)
	await get_tree().physics_frame
	_check(player.loose == 0 and player.boxes.is_empty(), "자석을 켜기 전에는 저절로 줍지 않음")
	_check(player.use_skill(0), "1번 키로 자석 발동")
	for i in 5:
		await get_tree().physics_frame
	_check(player.boxes.size() == 1, "자석: 같은 형태 4개가 모여 박스 1개 (실제 %d)" % player.boxes.size())
	_check(player.loose == 0, "박스를 더 못 들면 자석도 멈춤")
	player.boxes.clear()
	GameState.now += 100.0

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
		GameState.upgrade("long_arm")
	_check(GameState.level("long_arm") == 10, "액션 스킬 레벨 한계 10 (실제 %d)" % GameState.level("long_arm"))
	GameState.skill_points = 1
	_check(GameState.breakthrough("long_arm") and GameState.cap("long_arm") == 20, "한계 돌파로 20")

	player.boxes.append(type_a)
	player.boxes.append(type_b)
	var before := GameState.total_sorted
	var third := warehouses[0].shelves[2]
	player.try_place(third, Shelf.required_posture(third.current_tier()))
	var expected := 2 * Toys.BOX_SIZE * Skills.bundle(10)
	_check(GameState.total_sorted - before == expected, "묶음 Lv10: 박스 2개가 %d개로 계산" % expected)

	# 창고 해금, 문, 와르르
	_check(not GameState.is_warehouse_unlocked(2), "1,000개 전에는 창고 2 잠김")
	warehouses[1].toggle_door()
	_check(not warehouses[1].is_open, "잠긴 창고 문은 안 열림")
	GameState.auto_store(1000 - GameState.total_sorted)
	_check(GameState.is_warehouse_unlocked(2), "1,000개에 창고 2 개방")
	warehouses[1].toggle_door()
	_check(warehouses[1].is_open, "개방 후 문 열림")
	warehouses[1].toggle_door()
	_check(not warehouses[1].is_open, "문 닫힘")
	GameState.auto_store(4000)
	_check(GameState.is_warehouse_unlocked(3), "5,000개에 창고 3 개방")
	_check(not GameState.wareureu_done, "1만 개 전에는 와르르 없음")
	GameState.auto_store(5000)
	_check(GameState.is_warehouse_unlocked(4), "10,000개에 창고 4 개방")
	_check(GameState.wareureu_done and warehouses[3].is_open, "와르르: 창고 4 문이 열림")
	for i in 100:
		await get_tree().physics_frame
	var rigid_count := 0
	for toy in get_tree().get_nodes_in_group("toy"):
		if toy is RigidBody3D:
			rigid_count += 1
	_check(rigid_count == 240, "와르르 장난감 240개 (실제 %d)" % rigid_count)

	# 층 진행: 1층을 다 채워야 2층이 열린다
	_check(not GameState.is_floor_active(1, 1), "1층 완료 전 2층 비활성")
	for shelf_index in GameState.SHELVES_PER_FLOOR:
		GameState.store_in_shelf(1, 0, shelf_index, 10_000_000)
	_check(GameState.is_floor_complete(1, 0) and GameState.is_floor_active(1, 1), "1층 완료 → 2층 활성")
	_check(GameState.floors_completed() == 1, "완료한 층 1개")

	# 저장 왕복
	var saved := JSON.parse_string(JSON.stringify(GameState.to_dict())) as Dictionary
	var total_before := GameState.total_sorted
	var shelves_before := GameState.shelves_completed()
	GameState.reset()
	_check(GameState.total_sorted == 0 and GameState.level("bundle") == 0, "초기화")
	GameState.from_dict(saved)
	_check(GameState.total_sorted == total_before, "저장 왕복: 정리 수 유지")
	_check(GameState.shelves_completed() == shelves_before, "저장 왕복: 선반 상태 유지")
	_check(GameState.level("bundle") == 10 and GameState.cap("long_arm") == 20, "저장 왕복: 스킬 유지")
	_check(not GameState.is_active("long_arm"), "발동 상태는 저장되지 않음")

	# 자동 정리: 켜져 있는 동안만 선반이 채워진다
	GameState.skill_points = 1
	GameState.learn("auto_sort")
	total_before = GameState.total_sorted
	for i in 20:
		await get_tree().process_frame
	_check(GameState.total_sorted == total_before, "자동 정리를 켜기 전에는 그대로")
	_check(player.use_skill(2), "3번 키로 자동 정리 발동")
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
	_check(gained == int(rate * 600 * GameState.OFFLINE_EFFICIENCY), "오프라인 10분 보상 (실제 %d)" % gained)
	_check(GameState.total_sorted == total_before + gained, "오프라인 보상이 정리 수에 반영")
	_check(SaveManager.apply_offline_reward(1_000_000 + 30) == 0, "1분 미만은 보상 없음")

	# 끝까지: 1,000만 개
	var completed := [false]
	EventBus.game_completed.connect(func() -> void: completed[0] = true)
	GameState.unlocked_warehouses = [1, 2, 3, 4]
	GameState.auto_store(GameState.TOTAL_TOYS)
	_check(GameState.total_sorted == GameState.TOTAL_TOYS, "1,000만 개 정리 (실제 %d)" % GameState.total_sorted)
	_check(GameState.shelves_completed() == 80 and GameState.floors_completed() == 8, "선반 80개·8개 층 완료")
	_check(completed[0], "완료 시그널 발생")
	_check(QuestManager.current().is_empty(), "모든 퀘스트 완료")

	await get_tree().physics_frame
	print("SMOKE %s (%d checks, %d failures)" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _failures
	])
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	print("FAIL: %s" % description)
