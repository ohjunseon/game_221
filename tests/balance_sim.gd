extends Node
## 밸런스 시뮬레이션: 계속 플레이하는 가상의 플레이어가 각 목표에 도달하는 시간을 추정한다.
## 실제 조작 대신 Skills의 공식과 단순한 이동·클릭 시간 모델을 쓴다.
## 실행: <godot> --headless --path . res://tests/balance.tscn

const MAX_SECONDS := 60 * 3600
const WALK_SECONDS := 3.5
const CLICK_SECONDS := 0.5
const POSTURE_SECONDS := 0.6
const MILESTONES: Array[int] = [100, 1000, 5000, 10000, 100000, 1000000, 5000000, 10000000]
const LEARN_ORDER: Array[String] = [
	"bundle", "big_hands", "auto_sort", "long_arm", "magnet",
	"quick_hands", "sprint", "critical", "combo",
]
## 한계 돌파에 포인트를 쓸 가치가 있는 스킬
const BREAK_ORDER: Array[String] = ["bundle", "auto_sort", "big_hands", "magnet"]

var _levels: Dictionary = {}
var _caps: Dictionary = {}
var _points: int = 0
var _coins: float = 0.0
var _total: int = 0
var _stored: Dictionary = {}
var _unlocked: Array[int] = [1]


func _ready() -> void:
	SaveManager.enabled = false
	var next_milestone := 0
	var carry_over := 0.0
	var second := 0
	while second < MAX_SECONDS and _total < GameState.TOTAL_TOYS:
		second += 1
		var manual := _manual_rate()
		var auto := Skills.auto_rate(_level("auto_sort"), _level("bundle"))
		carry_over += manual + auto
		var amount := int(carry_over)
		carry_over -= amount
		var stored := _store(amount)
		var manual_share := manual / maxf(manual + auto, 0.0001)
		_coins += stored * (manual_share * _manual_coin_mult() + (1.0 - manual_share))
		_spend()
		while next_milestone < MILESTONES.size() and _total >= MILESTONES[next_milestone]:
			print("%10s개: %s  (수동 %.1f/s, 자동 %.1f/s, 묶음 Lv%d, 자동 Lv%d)" % [
				Skills.fmt(MILESTONES[next_milestone]), _clock(second), manual, auto,
				_level("bundle"), _level("auto_sort"),
			])
			next_milestone += 1
	if _total < GameState.TOTAL_TOYS:
		print("미완료: %s 시점에 %s개" % [_clock(second), Skills.fmt(_total)])
	print("BALANCE DONE")
	get_tree().quit(0)


func _level(id: String) -> int:
	return int(_levels.get(id, 0))


## 한 번 왕복(줍기 → 걷기 → 넣기)으로 정리하는 초당 개수
func _manual_rate() -> float:
	var carry := Skills.carry(_level("big_hands"))
	var click := CLICK_SECONDS
	var interval := Skills.repeat_interval(_level("quick_hands"))
	if interval > 0.0:
		click = interval
	var picks := ceilf(float(carry) / (1.0 + _level("magnet")))
	var cycle := WALK_SECONDS / Skills.speed_mult(_level("sprint")) + picks * click + click
	if _level("long_arm") <= 0:
		cycle += POSTURE_SECONDS
	return carry * Skills.bundle(_level("bundle")) / cycle


func _manual_coin_mult() -> float:
	var crit := Skills.crit_chance(_level("critical")) * (Skills.CRIT_MULTIPLIER - 1.0)
	var combo := Skills.MAX_COMBO * 0.5 * Skills.combo_step(_level("combo"))
	return (1.0 + crit) * (1.0 + combo)


## 열려 있는 층의 선반 중 가장 작은 것부터 채운다.
func _store(amount: int) -> int:
	var remaining := amount
	while remaining > 0:
		var best_key := ""
		var best_space := 0
		var best_capacity := 0
		for warehouse_id in _unlocked:
			for floor_index in GameState.FLOORS_PER_WAREHOUSE:
				if floor_index == 1 and not _floor_done(warehouse_id, 0):
					continue
				for shelf_index in GameState.SHELVES_PER_FLOOR:
					var key := GameState.shelf_key(warehouse_id, floor_index, shelf_index)
					var capacity := GameState.SHELF_CAPACITIES[shelf_index]
					var space := capacity - int(_stored.get(key, 0))
					if space > 0 and (best_key == "" or capacity < best_capacity):
						best_key = key
						best_space = space
						best_capacity = capacity
		if best_key == "":
			break
		var put := mini(remaining, best_space)
		_stored[best_key] = int(_stored.get(best_key, 0)) + put
		remaining -= put
		_total += put
		if put == best_space:
			_points += 1
		for threshold: int in GameState.UNLOCK_THRESHOLDS:
			var warehouse_id: int = GameState.UNLOCK_THRESHOLDS[threshold]
			if _total >= threshold and warehouse_id not in _unlocked:
				_unlocked.append(warehouse_id)
	return amount - remaining


func _floor_done(warehouse_id: int, floor_index: int) -> bool:
	for shelf_index in GameState.SHELVES_PER_FLOOR:
		var key := GameState.shelf_key(warehouse_id, floor_index, shelf_index)
		if int(_stored.get(key, 0)) < GameState.SHELF_CAPACITIES[shelf_index]:
			return false
	return true


## 포인트는 새 스킬 → 한계 돌파 순으로, 코인은 가장 싼 강화부터 쓴다.
func _spend() -> void:
	while _points > 0:
		var spent := false
		for id in LEARN_ORDER:
			if _level(id) <= 0:
				_levels[id] = 1
				_caps[id] = Skills.CAP_PER_POINT
				_points -= 1
				spent = true
				break
		if spent:
			continue
		for id in BREAK_ORDER:
			if _level(id) >= int(_caps[id]):
				_caps[id] = int(_caps[id]) + Skills.CAP_PER_POINT
				_points -= 1
				spent = true
				break
		if not spent:
			break
	while true:
		var cheapest := ""
		var price := 0
		for id in LEARN_ORDER:
			var level := _level(id)
			if level <= 0 or level >= int(_caps[id]):
				continue
			var cost := Skills.cost(id, level)
			if cheapest == "" or cost < price:
				cheapest = id
				price = cost
		if cheapest == "" or _coins < price:
			break
		_coins -= price
		_levels[cheapest] = _level(cheapest) + 1


func _clock(seconds: int) -> String:
	@warning_ignore("integer_division")
	return "%d시간 %02d분 %02d초" % [seconds / 3600, seconds / 60 % 60, seconds % 60]
