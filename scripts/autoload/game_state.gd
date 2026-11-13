extends Node
## 게임 전역 수치. 장난감은 오브젝트가 아니라 선반별 숫자로 관리한다.

const TOTAL_TOYS := 10_000_000
const WAREHOUSE_COUNT := 4
const FLOORS_PER_WAREHOUSE := 2
const SHELVES_PER_FLOOR := 10
const SHELF_TIERS := 10
## 층 하나의 선반 10개 용량. 합계 1,250,000 (8개 층 = 1,000만)
const SHELF_CAPACITIES: Array[int] = [
	100, 400, 1500, 5000, 15000, 40000, 90000, 180000, 330000, 588000,
]
## 누적 정리 수 -> 개방되는 창고 번호
const UNLOCK_THRESHOLDS := {
	1000: 2,
	5000: 3,
	10000: 4,
}
const OFFLINE_MAX_SECONDS := 8 * 3600
const OFFLINE_EFFICIENCY := 0.5

var total_sorted: int = 0
var coins: int = 0
var unlocked_warehouses: Array[int] = [1]
var skill_points: int = 0
var skill_levels: Dictionary = {}
var skill_caps: Dictionary = {}
var shelf_stored: Dictionary = {}
var quest_index: int = 0
var doors_opened: Array[int] = []
var wareureu_done: bool = false
var saved_at: int = 0

## 저장하지 않는 실행 중 상태
var menu_open: bool = false
var offline_report: Dictionary = {}

var _auto_accum: float = 0.0
var _completed_emitted: bool = false


func _process(delta: float) -> void:
	var rate := auto_rate()
	if rate <= 0.0 or total_sorted >= TOTAL_TOYS:
		return
	_auto_accum += rate * delta
	if _auto_accum >= 1.0:
		var amount := int(_auto_accum)
		_auto_accum -= amount
		auto_store(amount)


static func shelf_key(warehouse_id: int, floor_index: int, shelf_index: int) -> String:
	return "%d_%d_%d" % [warehouse_id, floor_index, shelf_index]


func get_shelf_stored(key: String) -> int:
	return int(shelf_stored.get(key, 0))


## 선반에 넣고 실제로 들어간 개수를 돌려준다.
func store_in_shelf(
	warehouse_id: int, floor_index: int, shelf_index: int, amount: int, coin_mult: float = 1.0
) -> int:
	var key := shelf_key(warehouse_id, floor_index, shelf_index)
	var capacity := SHELF_CAPACITIES[shelf_index]
	var before := get_shelf_stored(key)
	var accepted := mini(amount, capacity - before)
	if accepted <= 0:
		return 0
	shelf_stored[key] = before + accepted
	total_sorted += accepted
	coins += int(ceil(accepted * coin_mult))
	EventBus.shelf_changed.emit(key)
	if before + accepted >= capacity:
		skill_points += 1
		EventBus.shelf_completed.emit(warehouse_id, floor_index, shelf_index)
		EventBus.skills_changed.emit()
	_check_unlocks()
	EventBus.coins_changed.emit(coins)
	EventBus.toy_sorted.emit(total_sorted)
	if total_sorted >= TOTAL_TOYS and not _completed_emitted:
		_completed_emitted = true
		EventBus.game_completed.emit()
	return accepted


## 자동 정리·오프라인 보상: 열린 층의 선반을 순서대로 채운다.
func auto_store(amount: int) -> int:
	var remaining := amount
	for warehouse_id in range(1, WAREHOUSE_COUNT + 1):
		if not is_warehouse_unlocked(warehouse_id):
			continue
		for floor_index in FLOORS_PER_WAREHOUSE:
			if not is_floor_active(warehouse_id, floor_index):
				continue
			for shelf_index in SHELVES_PER_FLOOR:
				if remaining <= 0:
					return amount
				remaining -= store_in_shelf(warehouse_id, floor_index, shelf_index, remaining)
	return amount - remaining


func add_coins(amount: int) -> void:
	coins += amount
	EventBus.coins_changed.emit(coins)


func is_warehouse_unlocked(warehouse_id: int) -> bool:
	return warehouse_id in unlocked_warehouses


func unlock_threshold(warehouse_id: int) -> int:
	for threshold: int in UNLOCK_THRESHOLDS:
		if UNLOCK_THRESHOLDS[threshold] == warehouse_id:
			return threshold
	return 0


func is_shelf_full(warehouse_id: int, floor_index: int, shelf_index: int) -> bool:
	var key := shelf_key(warehouse_id, floor_index, shelf_index)
	return get_shelf_stored(key) >= SHELF_CAPACITIES[shelf_index]


func is_floor_complete(warehouse_id: int, floor_index: int) -> bool:
	for shelf_index in SHELVES_PER_FLOOR:
		if not is_shelf_full(warehouse_id, floor_index, shelf_index):
			return false
	return true


## 1층은 창고가 열리면, 2층은 1층을 다 정리하면 작업할 수 있다.
func is_floor_active(warehouse_id: int, floor_index: int) -> bool:
	if not is_warehouse_unlocked(warehouse_id):
		return false
	return floor_index == 0 or is_floor_complete(warehouse_id, floor_index - 1)


func shelves_completed() -> int:
	var count := 0
	for key: String in shelf_stored:
		var shelf_index := int(key.get_slice("_", 2))
		if int(shelf_stored[key]) >= SHELF_CAPACITIES[shelf_index]:
			count += 1
	return count


func floors_completed() -> int:
	var count := 0
	for warehouse_id in range(1, WAREHOUSE_COUNT + 1):
		for floor_index in FLOORS_PER_WAREHOUSE:
			if is_floor_complete(warehouse_id, floor_index):
				count += 1
	return count


func level(id: String) -> int:
	return int(skill_levels.get(id, 0))


func cap(id: String) -> int:
	return int(skill_caps.get(id, 0))


func learned_count() -> int:
	var count := 0
	for id: String in skill_levels:
		if int(skill_levels[id]) > 0:
			count += 1
	return count


func auto_rate() -> float:
	return Skills.auto_rate(level("auto_sort"), level("bundle"))


## 스킬 포인트 1개로 새 스킬을 배운다.
func learn(id: String) -> bool:
	if level(id) > 0 or skill_points <= 0:
		return false
	skill_points -= 1
	skill_levels[id] = 1
	skill_caps[id] = Skills.CAP_PER_POINT
	EventBus.skills_changed.emit()
	return true


## 코인으로 레벨을 올린다.
func upgrade(id: String) -> bool:
	var current := level(id)
	if current <= 0 or current >= cap(id):
		return false
	var price := Skills.cost(id, current)
	if coins < price:
		return false
	coins -= price
	skill_levels[id] = current + 1
	EventBus.coins_changed.emit(coins)
	EventBus.skills_changed.emit()
	return true


## 스킬 포인트 1개로 최대 레벨을 늘린다.
func breakthrough(id: String) -> bool:
	if level(id) <= 0 or skill_points <= 0:
		return false
	skill_points -= 1
	skill_caps[id] = cap(id) + Skills.CAP_PER_POINT
	EventBus.skills_changed.emit()
	return true


func mark_door_opened(warehouse_id: int) -> void:
	if warehouse_id not in doors_opened:
		doors_opened.append(warehouse_id)


func to_dict() -> Dictionary:
	return {
		"total_sorted": total_sorted,
		"coins": coins,
		"unlocked_warehouses": unlocked_warehouses,
		"skill_points": skill_points,
		"skill_levels": skill_levels,
		"skill_caps": skill_caps,
		"shelf_stored": shelf_stored,
		"quest_index": quest_index,
		"doors_opened": doors_opened,
		"wareureu_done": wareureu_done,
	}


func from_dict(data: Dictionary) -> void:
	total_sorted = int(data.get("total_sorted", 0))
	coins = int(data.get("coins", 0))
	skill_points = int(data.get("skill_points", 0))
	quest_index = int(data.get("quest_index", 0))
	wareureu_done = bool(data.get("wareureu_done", false))
	saved_at = int(data.get("saved_at", 0))
	unlocked_warehouses.clear()
	for id: Variant in data.get("unlocked_warehouses", [1]):
		unlocked_warehouses.append(int(id))
	if unlocked_warehouses.is_empty():
		unlocked_warehouses.append(1)
	doors_opened.clear()
	for id: Variant in data.get("doors_opened", []):
		doors_opened.append(int(id))
	skill_levels = _int_dict(data.get("skill_levels", {}))
	skill_caps = _int_dict(data.get("skill_caps", {}))
	shelf_stored = _int_dict(data.get("shelf_stored", {}))
	_auto_accum = 0.0
	_completed_emitted = total_sorted >= TOTAL_TOYS
	offline_report = {}


func reset() -> void:
	from_dict({})


func _int_dict(source: Variant) -> Dictionary:
	var result := {}
	if source is Dictionary:
		for key: Variant in source:
			result[str(key)] = int(source[key])
	return result


func _check_unlocks() -> void:
	for threshold: int in UNLOCK_THRESHOLDS:
		var warehouse_id: int = UNLOCK_THRESHOLDS[threshold]
		if total_sorted >= threshold and not is_warehouse_unlocked(warehouse_id):
			unlocked_warehouses.append(warehouse_id)
			EventBus.warehouse_unlocked.emit(warehouse_id)
