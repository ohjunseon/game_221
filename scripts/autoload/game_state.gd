extends Node
## 게임 전역 수치. 장난감 개수는 오브젝트가 아니라 숫자로 관리한다.

const TOTAL_TOYS := 10_000_000
const WAREHOUSE_COUNT := 4
const FLOORS_PER_WAREHOUSE := 2
const TOYS_PER_FLOOR := 1_250_000
const SHELF_TIERS := 10

## 누적 정리 수 -> 개방되는 창고 번호
const UNLOCK_THRESHOLDS := {
	1000: 2,
	5000: 3,
	10000: 4,
}

var total_sorted: int = 0
var coins: int = 0
var unlocked_warehouses: Array[int] = [1]


func add_sorted(amount: int = 1) -> void:
	total_sorted = mini(total_sorted + amount, TOTAL_TOYS)
	EventBus.toy_sorted.emit(total_sorted)
	_check_unlocks()


func add_coins(amount: int) -> void:
	coins += amount
	EventBus.coins_changed.emit(coins)


func is_warehouse_unlocked(warehouse_id: int) -> bool:
	return warehouse_id in unlocked_warehouses


func to_dict() -> Dictionary:
	return {
		"total_sorted": total_sorted,
		"coins": coins,
		"unlocked_warehouses": unlocked_warehouses,
	}


func from_dict(data: Dictionary) -> void:
	total_sorted = int(data.get("total_sorted", 0))
	coins = int(data.get("coins", 0))
	unlocked_warehouses.clear()
	for id in data.get("unlocked_warehouses", [1]):
		unlocked_warehouses.append(int(id))
	if unlocked_warehouses.is_empty():
		unlocked_warehouses.append(1)


func _check_unlocks() -> void:
	for threshold: int in UNLOCK_THRESHOLDS:
		var warehouse_id: int = UNLOCK_THRESHOLDS[threshold]
		if total_sorted >= threshold and not is_warehouse_unlocked(warehouse_id):
			unlocked_warehouses.append(warehouse_id)
			EventBus.warehouse_unlocked.emit(warehouse_id)
