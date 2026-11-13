extends Node
## user://save.json 저장·불러오기. 30초마다, 그리고 종료 시 자동 저장한다.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_INTERVAL := 30.0


func _ready() -> void:
	load_game()
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_INTERVAL
	timer.autostart = true
	timer.timeout.connect(save_game)
	add_child(timer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func save_game() -> void:
	var data := GameState.to_dict()
	data["version"] = SAVE_VERSION
	data["saved_at"] = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("저장 실패: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("불러오기 실패: %s" % error_string(FileAccess.get_open_error()))
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		GameState.from_dict(parsed)
	else:
		push_error("저장 파일이 손상되었습니다: %s" % SAVE_PATH)
