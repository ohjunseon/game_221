extends Node
## user://save.json 한 칸 저장·불러오기.
## 게임을 켜면 시작 화면이 뜨고, "이어하기"를 누를 때만 불러온다.
## 게임 화면(`in_game`)에서는 30초마다, 그리고 종료 시 자동 저장한다.
## 불러올 때 자동 정리 스킬이 있으면 오프라인 보상을 계산한다.

const SAVE_PATH := "user://save.json"
## 테스트는 다른 파일로 바꿔 쓴다.
var save_path: String = SAVE_PATH
## 3: 선반 저장량이 장난감 수에서 박스 수로 바뀜 (이전 저장은 호환되지 않아 .old로 보관하고 새로 시작)
const SAVE_VERSION := 3
const AUTOSAVE_INTERVAL := 30.0
const OFFLINE_MIN_SECONDS := 60

## 테스트에서 실제 저장 파일을 건드리지 않도록 끌 수 있다.
var enabled: bool = true
## 게임 화면에 있을 때만 자동 저장한다. 시작 화면·오프닝에서는 false.
var in_game: bool = false


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_autosave)
	add_child(timer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()


func _autosave() -> void:
	if in_game:
		save_game()


## 불러올 수 있는 저장 파일이 있는지 (이전 버전 파일은 없는 것으로 본다).
func has_save() -> bool:
	var data := _read()
	return not data.is_empty() and int(data.get("version", 0)) >= SAVE_VERSION


func save_game() -> bool:
	if not enabled:
		return false
	var data := GameState.to_dict()
	data["version"] = SAVE_VERSION
	data["saved_at"] = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("저장 실패: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data))
	return true


## 이어하기: 저장을 불러온다. 성공하면 true.
func load_game() -> bool:
	var data := _read()
	if data.is_empty():
		return false
	if int(data.get("version", 0)) < SAVE_VERSION:
		DirAccess.rename_absolute(save_path, save_path + ".old")
		push_warning("이전 버전 저장 파일을 %s.old 로 보관하고 새로 시작합니다" % save_path)
		return false
	GameState.from_dict(data)
	apply_offline_reward(int(Time.get_unix_time_from_system()))
	return true


## 새 게임: 저장 파일을 지우고 상태를 처음으로 되돌린다.
func new_game() -> void:
	if enabled and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	GameState.reset()


func _read() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("불러오기 실패: %s" % error_string(FileAccess.get_open_error()))
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("저장 파일이 손상되었습니다: %s" % save_path)
	return {}


## 꺼져 있던 시간만큼 자동 정리 수입의 일부를 지급한다.
func apply_offline_reward(now: int) -> int:
	var rate := GameState.auto_average_rate()
	if GameState.saved_at <= 0 or rate <= 0.0:
		return 0
	var elapsed := mini(now - GameState.saved_at, GameState.OFFLINE_MAX_SECONDS)
	if elapsed < OFFLINE_MIN_SECONDS:
		return 0
	var boxes := int(rate * elapsed * GameState.OFFLINE_EFFICIENCY)
	var per_box := GameState.toys_per_box()
	var stored := GameState.auto_store(boxes) * per_box
	GameState.offline_report = {"seconds": elapsed, "stored": stored}
	return stored
