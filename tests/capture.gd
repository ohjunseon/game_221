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
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_player = _main.get_node("Player")
	await _wait(20)
	await _shot("1_start")

	# 창고 1 안, 선반 앞
	for i in 3:
		GameState.store_in_shelf(1, 0, i, 10_000)
	GameState.store_in_shelf(1, 0, 3, 700)
	_look_from(Vector3(-7.0, 0.9, -46.0), 0.35, -0.05)
	await _wait(20)
	await _shot("2_shelves")

	# 스킬 메뉴
	GameState.learn("bundle")
	GameState.learn("long_arm")
	GameState.add_coins(500)
	_main.get_node("HUD")._set_menu_open(true)
	await _wait(10)
	await _shot("3_menu")
	_main.get_node("HUD")._set_menu_open(false)

	# 2층으로 가는 경사로와 문 쪽
	_look_from(Vector3(6.0, 0.9, -34.0), -1.0, 0.1)
	await _wait(10)
	await _shot("4_ramp")

	# 와르르
	GameState.auto_store(10_000)
	_look_from(Vector3(-8.0, 0.9, 6.0), PI / 2.0 + 0.5, 0.0)
	await _wait(90)
	await _shot("5_wareureu")

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
