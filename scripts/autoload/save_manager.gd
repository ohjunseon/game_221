extends Node
## user://save.json 저장·불러오기. 30초마다, 그리고 종료 시 자동 저장한다.
## 불러올 때 자동 정리 스킬이 있으면 오프라인 보상을 계산한다.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2
const AUTOSAVE_INTERVAL := 30.0
const OFFLINE_MIN_SECONDS := 60

## 테스트에서 실제 저장 파일을 건드리지 않도록 끌 수 있다.
var enabled: bool = true


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
	if not enabled:
		return
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
		apply_offline_reward(int(Time.get_unix_time_from_system()))
	else:
		push_error("저장 파일이 손상되었습니다: %s" % SAVE_PATH)


## 꺼져 있던 시간만큼 자동 정리 수입의 일부를 지급한다.
func apply_offline_reward(now: int) -> int:
	var rate := GameState.auto_rate()
	if GameState.saved_at <= 0 or rate <= 0.0:
		return 0
	var elapsed := mini(now - GameState.saved_at, GameState.OFFLINE_MAX_SECONDS)
	if elapsed < OFFLINE_MIN_SECONDS:
		return 0
	var amount := int(rate * elapsed * GameState.OFFLINE_EFFICIENCY)
	var stored := GameState.auto_store(amount)
	GameState.offline_report = {"seconds": elapsed, "stored": stored}
	return stored
