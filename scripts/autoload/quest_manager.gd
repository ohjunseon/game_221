extends Node
## 순서대로 진행되는 퀘스트(업적 포함). 달성하면 코인 보상을 준다.

const QUESTS: Array[Dictionary] = [
	{"text": "장난감 10개 정리하기", "type": "sorted", "target": 10, "reward": 30},
	{"text": "첫 선반 완성하기", "type": "shelves", "target": 1, "reward": 100},
	{"text": "스킬 1개 배우기 (Tab)", "type": "skills", "target": 1, "reward": 100},
	{"text": "1,000개 정리해서 창고 2 열기", "type": "sorted", "target": 1000, "reward": 300},
	{"text": "창고 2의 문 열기", "type": "doors", "target": 2, "reward": 200},
	{"text": "스킬 3개 배우기", "type": "skills", "target": 3, "reward": 500},
	{"text": "5,000개 정리해서 창고 3 열기", "type": "sorted", "target": 5000, "reward": 1000},
	{"text": "10,000개 정리해서 창고 4 열기", "type": "sorted", "target": 10000, "reward": 2000},
	{"text": "선반 10개 완성하기", "type": "shelves", "target": 10, "reward": 5000},
	{"text": "100,000개 정리하기", "type": "sorted", "target": 100000, "reward": 20000},
	{"text": "선반 30개 완성하기", "type": "shelves", "target": 30, "reward": 50000},
	{"text": "한 층을 전부 정리하기", "type": "floors", "target": 1, "reward": 200000},
	{"text": "1,000,000개 정리하기", "type": "sorted", "target": 1000000, "reward": 300000},
	{"text": "네 개 층 정리하기", "type": "floors", "target": 4, "reward": 1000000},
	{"text": "5,000,000개 정리하기", "type": "sorted", "target": 5000000, "reward": 2000000},
	{"text": "10,000,000개 모두 정리하기", "type": "sorted", "target": 10000000, "reward": 0},
]


func _ready() -> void:
	EventBus.toy_sorted.connect(func(_total: int) -> void: check())
	EventBus.skills_changed.connect(check)
	EventBus.door_toggled.connect(func(_id: int, _open: bool) -> void: check())
	check.call_deferred()


func current() -> Dictionary:
	if GameState.quest_index >= QUESTS.size():
		return {}
	return QUESTS[GameState.quest_index]


func progress() -> int:
	var quest := current()
	if quest.is_empty():
		return 0
	match quest["type"]:
		"sorted":
			return GameState.total_sorted
		"shelves":
			return GameState.shelves_completed()
		"skills":
			return GameState.learned_count()
		"doors":
			return GameState.doors_opened.size()
		"floors":
			return GameState.floors_completed()
	return 0


func text() -> String:
	var quest := current()
	if quest.is_empty():
		return "모든 퀘스트 완료!"
	return "퀘스트: %s (%d/%d)" % [
		quest["text"], mini(progress(), quest["target"]), quest["target"]
	]


func check() -> void:
	var changed := false
	while not current().is_empty() and progress() >= int(current()["target"]):
		var quest := current()
		GameState.quest_index += 1
		if int(quest["reward"]) > 0:
			GameState.add_coins(int(quest["reward"]))
		EventBus.message_shown.emit("퀘스트 완료! +%d 코인" % int(quest["reward"]))
		Sfx.play("complete")
		changed = true
	if changed:
		EventBus.quest_changed.emit()
