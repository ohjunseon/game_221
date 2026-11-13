extends Node
## 헤드리스 스모크 테스트: 줍기, 자세 규칙, 선반 채우기, 창고 해금.
## 실행: <godot> --headless --path . res://tests/smoke.tscn

var _failures: int = 0


func _ready() -> void:
	GameState.from_dict({})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: Node = main.get_node("Player")
	var shelves: Array[Shelf] = main.get_node("WarehouseFloor").shelves
	var toys := get_tree().get_nodes_in_group("toy")

	_check(shelves.size() == 10, "선반 10개 생성")
	_check(toys.size() == 150, "장난감 150개 생성 (실제 %d)" % toys.size())

	_check(Shelf.required_posture(1) == Shelf.Posture.CROUCH, "1단 웅크리기")
	_check(Shelf.required_posture(3) == Shelf.Posture.CROUCH, "3단 웅크리기")
	_check(Shelf.required_posture(4) == Shelf.Posture.STAND, "4단 서서")
	_check(Shelf.required_posture(8) == Shelf.Posture.STAND, "8단 서서")
	_check(Shelf.required_posture(9) == Shelf.Posture.JUMP, "9단 점프")
	_check(Shelf.required_posture(10) == Shelf.Posture.JUMP, "10단 점프")

	var shelf := shelves[0]
	_check(not player.try_place(shelf, Shelf.Posture.CROUCH), "빈손으로는 넣기 불가")
	_check(player.try_pick(toys[0]), "줍기")
	_check(not player.try_pick(toys[1]), "들고 있으면 또 줍기 불가")
	_check(not player.try_place(shelf, Shelf.Posture.STAND), "1단은 서서 넣기 불가")
	_check(not player.try_place(shelf, Shelf.Posture.JUMP), "1단은 점프로 넣기 불가")
	_check(player.try_place(shelf, Shelf.Posture.CROUCH), "1단 웅크리고 넣기")
	_check(GameState.total_sorted == 1 and GameState.coins == 1, "정리 1, 코인 1")
	_check(not player.holding, "넣은 뒤 빈손")

	var postures_used := {}
	for i in 999:
		var target: Shelf = null
		for candidate in shelves:
			if not candidate.is_full():
				target = candidate
				break
		if target == null:
			break
		var posture := Shelf.required_posture(target.current_tier())
		postures_used[posture] = true
		player.holding = true
		player.try_place(target, posture)

	_check(GameState.total_sorted == 1000, "1,000개 정리 (실제 %d)" % GameState.total_sorted)
	_check(postures_used.size() == 3, "세 자세 모두 사용")
	_check(shelves[0].is_full() and shelves[9].is_full(), "선반 10개 모두 가득")
	_check(GameState.is_warehouse_unlocked(2), "1,000개에 창고 2 개방")
	_check(not GameState.is_warehouse_unlocked(3), "창고 3은 아직 잠김")
	player.holding = true
	_check(not player.try_place(shelf, Shelf.Posture.JUMP), "가득 찬 선반에는 넣기 불가")

	GameState.add_sorted(4000)
	_check(GameState.is_warehouse_unlocked(3), "5,000개에 창고 3 개방")
	GameState.add_sorted(5000)
	_check(GameState.is_warehouse_unlocked(4), "10,000개에 창고 4 개방")

	await get_tree().physics_frame
	print("SMOKE %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failures += 1
	print("FAIL: %s" % description)
