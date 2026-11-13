extends Node
## 밸런스 시뮬레이션: 계속 플레이하는 가상의 플레이어가 각 목표에 도달하는 시간을 추정한다.
## 실제 조작 대신 Skills의 공식과 단순한 이동·클릭 시간 모델을 쓴다.
## 실행: <godot> --headless --path . res://tests/balance.tscn

const MAX_SECONDS := 60 * 3600
const WALK_SECONDS := 2.5
const CLICK_SECONDS := 0.5
## 같은 형태의 다음 장난감까지 걸어가는 시간
const SEARCH_SECONDS := 0.6
const POSTURE_SECONDS := 0.6
const MILESTONES: Array[int] = [100, 1000, 5000, 10000, 100000, 1000000, 5000000, 10000000]
## 액션 스킬을 배우는 순서, 한계 돌파 우선순위
const LEARN_ORDER: Array[String] = ["magnet", "auto_sort", "jackpot", "long_arm"]
const BREAK_ORDER: Array[String] = ["auto_sort", "jackpot", "magnet", "long_arm"]
## 자석이 켜져 있을 때 줍는 시간이 줄어드는 비율
const MAGNET_SAVING := 0.8

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
		# 액션 스킬은 쿨타임이 끝날 때마다 바로 쓴다고 보고 가동률을 곱한다
		var auto := (
			Skills.auto_rate(_level("auto_sort"), _level("bundle"))
			* Skills.uptime("auto_sort", _level("auto_sort"))
		)
		carry_over += manual + auto
		var amount := int(carry_over)
		carry_over -= amount
		var stored := _store(amount)
		_coins += stored * _coin_mult()
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
	# 박스 하나에 같은 형태 장난감 BOX_SIZE개를 집어야 한다.
	# 자석이 켜져 있는 동안에는 찾아다니고 클릭하는 시간이 크게 준다.
	var picks := float(carry * Toys.BOX_SIZE)
	var speed := Skills.speed_mult(_level("sprint"))
	var pick_time := picks * (SEARCH_SECONDS / speed + click)
	pick_time *= 1.0 - MAGNET_SAVING * Skills.uptime("magnet", _level("magnet"))
	var cycle := WALK_SECONDS / speed + pick_time + click
	cycle += POSTURE_SECONDS * (1.0 - Skills.uptime("long_arm", _level("long_arm")))
	return carry * Toys.BOX_SIZE * Skills.bundle(_level("bundle")) / cycle


## 대박 타임 가동률을 반영한 평균 코인 배수
func _coin_mult() -> float:
	var level := _level("jackpot")
	return 1.0 + (Skills.jackpot_mult(level) - 1.0) * Skills.uptime("jackpot", level)


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
		for id: String in Skills.DEFS:
			var level := _level(id)
			# 액션 스킬은 배운 뒤 한계 레벨까지만, 업그레이드는 제한 없이
			if Skills.is_action(id) and (level <= 0 or level >= int(_caps[id])):
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
