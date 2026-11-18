extends Node
## 게임 전역 수치. 장난감은 오브젝트가 아니라 선반별 숫자로 관리한다.

const TOTAL_TOYS := 10_000_000
const WAREHOUSE_COUNT := 4
const FLOORS_PER_WAREHOUSE := 2
const SHELF_TIERS := 10
## 창고 번호 → 한 층의 선반 수. 창고가 클수록 선반이 많다 (2층이라 창고당 ×2)
const SHELVES_PER_FLOOR := {1: 10, 2: 40, 3: 50, 4: 100}
## 창고 번호 → 통로 하나의 선반 수 (통로 양쪽에 반씩). 통로 수 = 한 층 선반 수 / 이 값
const SHELVES_PER_AISLE := {1: 10, 2: 10, 3: 10, 4: 20}
## 모든 선반은 똑같이 박스 100개(10단 × 10칸). 박스 1개에 담긴 장난감 수는 묶음 정리로 커진다
const BOXES_PER_SHELF := 100
## 스킬 포인트: 정리한 박스 누적이 5·n·(n+1)개(10, 30, 60, 100, ...)에 닿을 때마다 1개
const POINT_STEP := 5
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
## 지금까지 선반에 넣은 박스 수 (스킬 포인트 지급 기준)
var boxes_total: int = 0
var skill_levels: Dictionary = {}
var skill_caps: Dictionary = {}
var shelf_stored: Dictionary = {}
## 선반별 장난감 종류 (key → 종류). 처음 넣은 종류로 정해지며 이후 바뀌지 않는다
var shelf_types: Dictionary = {}
var quest_index: int = 0
var doors_opened: Array[int] = []
var wareureu_done: bool = false
var saved_at: int = 0

## 저장하지 않는 실행 중 상태
var menu_open: bool = false
var offline_report: Dictionary = {}

## 게임 내 시계(초). 액션 스킬의 지속 시간과 쿨타임 기준
var now: float = 0.0

## 층(key "창고_층")별로 손에 든 장난감 수(박스 포함)와, 바닥에 버려진 장난감 수(박스 포함).
## 바닥 재고 = 빈 선반 칸 × 박스당 장난감 - 손에 든 수. 저장하지 않고 선반 저장량에서 매번 계산한다.
var carried_toys: Dictionary = {}
var dropped_toys: Dictionary = {}

var _auto_accum: float = 0.0
var _completed_emitted: bool = false
var _active_until: Dictionary = {}
var _ready_at: Dictionary = {}


func _process(delta: float) -> void:
	now += delta
	if not is_active("auto_sort") or total_sorted >= TOTAL_TOYS:
		return
	_auto_accum += auto_rate() * delta
	if _auto_accum >= 1.0:
		var boxes := int(_auto_accum)
		_auto_accum -= boxes
		auto_store(boxes)


static func shelf_key(warehouse_id: int, floor_index: int, shelf_index: int) -> String:
	return "%d_%d_%d" % [warehouse_id, floor_index, shelf_index]


func get_shelf_stored(key: String) -> int:
	return int(shelf_stored.get(key, 0))


## 선반의 종류 (아직 정해지지 않았으면 -1)
func get_shelf_type(key: String) -> int:
	return int(shelf_types.get(key, -1))


static func floor_key(warehouse_id: int, floor_index: int) -> String:
	return "%d_%d" % [warehouse_id, floor_index]


## 한 층에서 아직 선반에 들어가지 않은 박스 칸 수
func empty_boxes(warehouse_id: int, floor_index: int) -> int:
	var empty := 0
	for shelf_index in shelves_per_floor(warehouse_id):
		empty += BOXES_PER_SHELF - get_shelf_stored(shelf_key(warehouse_id, floor_index, shelf_index))
	return empty


## 한 층 바닥에 남은 장난감 수 (더미 + 버려진 것). 새로 생기는 장난감은 없다.
func ground_toys(warehouse_id: int, floor_index: int) -> int:
	var key := floor_key(warehouse_id, floor_index)
	return maxi(0, empty_boxes(warehouse_id, floor_index) * Toys.BOX_SIZE - int(carried_toys.get(key, 0)))


func add_carried(key: String, amount: int) -> void:
	if key.is_empty():
		return
	carried_toys[key] = int(carried_toys.get(key, 0)) + amount


func add_dropped(key: String, amount: int) -> void:
	if key.is_empty():
		return
	dropped_toys[key] = maxi(0, int(dropped_toys.get(key, 0)) + amount)


## 한 층의 선반 수
static func shelves_per_floor(warehouse_id: int) -> int:
	return int(SHELVES_PER_FLOOR[warehouse_id])


## 통로가 맡는 장난감 종류. 자동 정리가 빈 선반에 넣을 때 따르고, 통로 표지판에 적힌다.
## 창고와 층마다 시작 종류를 달리해 여섯 종류가 고루 나온다.
static func default_shelf_type(warehouse_id: int, floor_index: int, shelf_index: int) -> int:
	@warning_ignore("integer_division")
	var aisle := shelf_index / int(SHELVES_PER_AISLE[warehouse_id])
	return (aisle + floor_index * 3 + warehouse_id - 1) % Toys.count()


## 박스 1개에 담긴 장난감 수 (묶음 정리 레벨에 따라 커진다)
func toys_per_box() -> int:
	return Toys.BOX_SIZE * Skills.bundle(level("bundle"))


## 박스 누적 수에 해당하는 스킬 포인트 수 (5·n·(n+1) ≤ 박스 수를 만족하는 가장 큰 n)
static func points_for_boxes(boxes: int) -> int:
	return int((-1.0 + sqrt(1.0 + 4.0 * boxes / POINT_STEP)) / 2.0)


## 박스를 선반에 넣고 실제로 들어간 박스 수를 돌려준다. 박스 1개 = toys_per_box() 개.
## toy_type: 넣는 박스의 종류. 선반 종류가 정해져 있고 다르면 넣지 않는다.
## -1(자동 정리)이면 정해진 종류를 따르고, 없으면 선반 번호로 종류를 배정한다.
func store_in_shelf(
	warehouse_id: int, floor_index: int, shelf_index: int, boxes: int,
	coin_mult: float = 1.0, toy_type: int = -1
) -> int:
	var key := shelf_key(warehouse_id, floor_index, shelf_index)
	var shelf_type := get_shelf_type(key)
	if shelf_type >= 0 and toy_type >= 0 and toy_type != shelf_type:
		return 0
	var before := get_shelf_stored(key)
	var accepted := mini(boxes, BOXES_PER_SHELF - before)
	if accepted <= 0:
		return 0
	if shelf_type < 0:
		shelf_types[key] = (
			toy_type if toy_type >= 0
			else default_shelf_type(warehouse_id, floor_index, shelf_index)
		)
	shelf_stored[key] = before + accepted
	var toys := accepted * toys_per_box()
	total_sorted += toys
	coins += int(ceil(toys * coin_mult * coin_multiplier()))
	var points_before := points_for_boxes(boxes_total)
	boxes_total += accepted
	var new_points := points_for_boxes(boxes_total) - points_before
	skill_points += new_points
	EventBus.shelf_changed.emit(key)
	if before + accepted >= BOXES_PER_SHELF:
		EventBus.shelf_completed.emit(warehouse_id, floor_index, shelf_index)
	if new_points > 0:
		EventBus.skills_changed.emit()
		EventBus.popup_requested.emit("스킬 포인트 +%d" % new_points)
	_check_unlocks()
	EventBus.coins_changed.emit(coins)
	EventBus.toy_sorted.emit(total_sorted)
	if (total_sorted >= TOTAL_TOYS or all_shelves_full()) and not _completed_emitted:
		_completed_emitted = true
		EventBus.game_completed.emit()
	return accepted


## 자동 정리·오프라인 보상: 열린 층의 선반을 순서대로 박스로 채운다. 넣은 박스 수를 돌려준다.
func auto_store(boxes: int) -> int:
	var remaining := boxes
	for warehouse_id in range(1, WAREHOUSE_COUNT + 1):
		if not is_warehouse_unlocked(warehouse_id):
			continue
		for floor_index in FLOORS_PER_WAREHOUSE:
			if not is_floor_active(warehouse_id, floor_index):
				continue
			# 바닥에 남은 장난감만큼만 정리할 수 있다
			var allowed := mini(remaining, ground_toys(warehouse_id, floor_index) / Toys.BOX_SIZE)
			var left := allowed
			for shelf_index in shelves_per_floor(warehouse_id):
				if left <= 0:
					break
				left -= store_in_shelf(warehouse_id, floor_index, shelf_index, left)
			remaining -= allowed - left
			if remaining <= 0:
				return boxes
	return boxes - remaining


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
	return get_shelf_stored(key) >= BOXES_PER_SHELF


func is_floor_complete(warehouse_id: int, floor_index: int) -> bool:
	for shelf_index in shelves_per_floor(warehouse_id):
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
		if int(shelf_stored[key]) >= BOXES_PER_SHELF:
			count += 1
	return count


## 모든 층(창고 4동 × 2층)이 가득 찼는지
func all_shelves_full() -> bool:
	return floors_completed() == WAREHOUSE_COUNT * FLOORS_PER_WAREHOUSE


## 선반 총 개수 (창고 4동 × 2층)
static func total_shelves() -> int:
	var count := 0
	for warehouse_id in SHELVES_PER_FLOOR:
		count += shelves_per_floor(warehouse_id) * FLOORS_PER_WAREHOUSE
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


## 배운 액션 스킬 수
func learned_count() -> int:
	var count := 0
	for id in Skills.ACTION_ORDER:
		if level(id) > 0:
			count += 1
	return count


## 자동 정리가 켜져 있는 동안 초당 선반에 들어가는 박스 수
func auto_rate() -> float:
	return Skills.auto_boxes(level("auto_sort"))


## 쿨타임까지 감안한 평균 초당 박스 수 (오프라인 보상용)
func auto_average_rate() -> float:
	return auto_rate() * Skills.uptime("auto_sort", level("auto_sort"))


## 액션 스킬을 발동한다. 배우지 않았거나 쿨타임이면 실패.
func activate(id: String) -> bool:
	var current := level(id)
	if not Skills.is_action(id) or current <= 0 or cooldown_left(id) > 0.0:
		return false
	_active_until[id] = now + Skills.duration(id, current)
	_ready_at[id] = now + Skills.cooldown(id, current)
	EventBus.skill_activated.emit(id)
	return true


func is_active(id: String) -> bool:
	return active_left(id) > 0.0


func active_left(id: String) -> float:
	return maxf(0.0, float(_active_until.get(id, 0.0)) - now)


func cooldown_left(id: String) -> float:
	return maxf(0.0, float(_ready_at.get(id, 0.0)) - now)


## 대박 타임이 켜져 있으면 코인 배수
func coin_multiplier() -> float:
	if is_active("jackpot"):
		return Skills.jackpot_mult(level("jackpot"))
	return 1.0


## 스킬 포인트 1개로 액션 스킬을 배운다.
func learn(id: String) -> bool:
	if not Skills.is_action(id) or level(id) > 0 or skill_points <= 0:
		return false
	skill_points -= 1
	skill_levels[id] = 1
	skill_caps[id] = Skills.CAP_PER_POINT
	EventBus.skills_changed.emit()
	return true


## 코인으로 레벨을 올린다.
func upgrade(id: String) -> bool:
	var current := level(id)
	# 액션 스킬은 배운 뒤 한계 레벨까지만, 업그레이드는 처음부터 제한 없이 올린다
	if Skills.is_action(id) and (current <= 0 or current >= cap(id)):
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
	if not Skills.is_action(id) or level(id) <= 0 or skill_points <= 0:
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
		"shelf_types": shelf_types,
		"boxes_total": boxes_total,
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
	# 없어진 스킬(긴 팔)에 쓴 스킬 포인트는 돌려준다
	for removed: String in skill_caps.keys():
		if not Skills.DEFS.has(removed):
			skill_points += int(skill_caps[removed] / Skills.CAP_PER_POINT)
			skill_caps.erase(removed)
			skill_levels.erase(removed)
	shelf_stored = _int_dict(data.get("shelf_stored", {}))
	shelf_types = _int_dict(data.get("shelf_types", {}))
	boxes_total = int(data.get("boxes_total", 0))
	_auto_accum = 0.0
	carried_toys.clear()
	dropped_toys.clear()
	_active_until.clear()
	_ready_at.clear()
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
