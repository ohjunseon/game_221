extends Node
## 화면 확인용: 실제 창으로 실행해 주요 장면을 build/shots/ 에 PNG로 저장한다.
## 실행: <godot> --path . res://tests/capture.tscn

const OUT_DIR := "res://build/shots"

var _main: Node
var _player: CharacterBody3D


func _ready() -> void:
	SaveManager.enabled = false
	GameState.reset()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# 시작 화면과 새 게임 확인 팝업
	var title: Control = load("res://scenes/title.tscn").instantiate()
	add_child(title)
	await _wait(10)
	await _shot("0_title")
	title.confirm.visible = true
	await _wait(5)
	await _shot("0_title_confirm")
	title.queue_free()

	# 오프닝·엔딩 카드
	var shots := [
		[Story.OPENING, 1, "0_story_dad"], [Story.OPENING, 5, "0_story_bear"],
		[Story.ENDING_BEFORE_BOX, 0, "0_story_cheer"], [Story.ENDING_AFTER_BOX, 0, "0_story_boom"],
		[Story.ENDING_AFTER_BOX, 1, "0_story_wake"], [Story.ENDING_AFTER_BOX, 4, "0_story_clean"],
	]
	for spec: Array in shots:
		var story := Story.play(self, spec[0])
		story.index = int(spec[1]) - 1
		story.next()
		await _wait(120)  # 페이드와 글자 찍기가 끝날 때까지
		await _shot(spec[2])
		story.finish()
		await _wait(2)
	GameState.menu_open = false

	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_player = _main.get_node("Player")
	await _wait(20)
	await _shot("1_start")

	# 창고 1 안, 선반 앞
	for i in 3:
		GameState.store_in_shelf(1, 0, i, GameState.BOXES_PER_SHELF)
	GameState.store_in_shelf(1, 0, 3, 37)
	GameState.store_in_shelf(1, 0, 6, 12)
	_look_from(Vector3(0.0, 0.9, -26.0), 0.0, 0.05)
	await _wait(20)
	await _shot("2_shelves")

	# 바닥의 장난감 형태와 손에 든 장난감·박스
	# 큰 손을 배워 박스 2개까지: 한 형태 4개로 박스를 만들고, 다른 형태 2개를 모으는 중
	GameState.add_coins(100)
	GameState.upgrade("big_hands")
	var by_type := {}
	var field: ToyField = _main.warehouses[0].fields[0]
	for slot in 60:
		var toy := field.materialize(slot)
		var type: int = toy.get_meta("toy_type")
		if not by_type.has(type):
			by_type[type] = []
		by_type[type].append(toy)
	var types := by_type.keys()
	types.sort_custom(func(a: int, b: int) -> bool: return by_type[a].size() > by_type[b].size())
	for i in Toys.BOX_SIZE:
		_player.try_pick(by_type[types[0]][i])
	for i in 2:
		_player.try_pick(by_type[types[1]][i])
	for i in 3:
		Warehouse.gild_toy(by_type[types[2 + i]][0])
	_look_from(Vector3(0.0, 0.9, -21.0), 0.0, -0.55)
	await _wait(10)
	await _shot("2b_toys")

	# 창고 1 문 안쪽에서: 바닥 전체에 깔린 장난감 4,000개
	_look_from(Vector3(0.0, 1.6, -21.5), 0.0, -0.35)
	await _wait(30)
	await _shot("2c_field")
	print("FPS 창고 1 바닥: %d" % Engine.get_frames_per_second())

	# 스킬 메뉴
	GameState.learn("magnet")
	GameState.learn("auto_sort")
	GameState.learn("jackpot")
	GameState.add_coins(500)
	_main.get_node("HUD")._set_menu_open(true)
	await _wait(10)
	await _shot("3_menu")
	_main.get_node("HUD")._set_menu_open(false)

	# 2층으로 가는 경사로와 문 쪽
	# 스킬 슬롯: 자동 정리와 대박 타임을 켠 상태
	_player.use_skill(1)
	_player.use_skill(2)
	_look_from(Vector3(5.6, 0.9, -34.0), 0.3, 0.1)
	await _wait(10)
	await _shot("4_ramp")

	# 와르르
	GameState.auto_store(10_000)
	_look_from(Vector3(-4.0, 0.9, 5.0), PI / 2.0 + 0.3, 0.0)
	await _wait(90)
	await _shot("5_wareureu")

	# 가장 큰 창고 4: 문 안쪽에서 선반 줄을 바라본다 (선반 100개씩 2층)
	GameState.unlocked_warehouses = [1, 2, 3, 4]
	for i in 60:
		GameState.store_in_shelf(4, 0, i, GameState.BOXES_PER_SHELF if i % 3 else 40)
	_look_from(Vector3(-23.0, 0.9, 0.0), PI / 2.0, 0.08)
	await _wait(60)
	await _shot("6_big_warehouse")
	print("FPS 창고 4 안: %d" % Engine.get_frames_per_second())

	# 창고 4 문 앞 마당의 장난감 산 (창고 안에 다 못 들어간 만큼)
	_look_from(Vector3(6.0, 1.6, 0.0), PI / 2.0, 0.05)
	await _wait(60)
	await _shot("6b_yard_mountain")
	print("FPS 마당 산: %d" % Engine.get_frames_per_second())

	# 엔딩: 마당에서 하늘을 올려다보면 거대 상자가 떨어진다
	_look_from(Vector3(0.0, 0.9, -12.0), 0.0, 0.0)
	_main.drop_ending_box()
	await get_tree().create_timer(_main.ENDING_FALL_SECONDS * 0.75).timeout
	await _shot("7_ending_box")

	print("CAPTURE DONE")
	get_tree().quit(0)


func _look_from(at: Vector3, yaw: float, pitch: float) -> void:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.rotation.y = yaw
	_player.head.rotation.x = pitch


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot_name]))
