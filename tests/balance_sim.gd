extends Node
## 밸런스 시뮬레이션: 계속 플레이하는 가상의 플레이어가 각 목표에 도달하는 시간을 추정한다.
## 실제 조작 대신 Skills의 공식과 단순한 이동·클릭 시간 모델을 쓴다.
## 선반은 모두 박스 100개이고, 박스 1개에 담긴 장난감 수는 묶음 정리 레벨이 정한다.
## 실행: <godot> --headless --path . res://tests/balance.tscn

const MAX_SECONDS := 60 * 3600
const WALK_SECONDS := 2.5
const CLICK_SECONDS := 0.5
## 같은 형태의 다음 장난감까지 걸어가는 시간
const SEARCH_SECONDS := 0.6
const POSTURE_SECONDS := 0.6
const MILESTONES: Array[int] = [100, 1000, 5000, 10000, 100000, 1000000, 5000000, 10000000]
## 액션 스킬을 배우는 순서, 한계 돌파 우선순위
const LEARN_ORDER: Array[String] = ["magnet", "auto_sort", "jackpot"]
const BREAK_ORDER: Array[String] = ["auto_sort", "jackpot", "magnet"]
## 자석으로 손을 채운 왕복에서 줍는 시간이 줄어드는 비율
const MAGNET_SAVING := 0.8

var _levels: Dictionary = {}
var _caps: Dictionary = {}
var _points: int = 0
var _coins: float = 0.0
## 정리한 장난감 수, 정리한 박스 수
var _total: int = 0
var _boxes_total: int = 0
var _stored: Dictionary = {}
var _unlocked: Array[int] = [1]


func _ready() -> void:
	SaveManager.enabled = false
	var next_milestone := 0
	var carry_over := 0.0
	var second := 0
	var done := false
	while second < MAX_SECONDS and not done:
		second += 1
		var manual := _manual_boxes()
		# 액션 스킬은 쿨타임이 끝날 때마다 바로 쓴다고 보고 가동률을 곱한다
		var auto := (
			Skills.auto_boxes(_level("auto_sort")) * Skills.uptime("auto_sort", _level("auto_sort"))
		)
		carry_over += manual + auto
		var boxes := int(carry_over)
		carry_over -= boxes
		var per_box := Toys.BOX_SIZE * Skills.bundle(_level("bundle"))
		var stored := _store(boxes)
		_coins += stored * per_box * _coin_mult()
		_spend()
		while next_milestone < MILESTONES.size() and _total >= MILESTONES[next_milestone]:
			print("%10s개: %s  (박스 %s개, 수동 %.2f/s, 자동 %.2f/s, 묶음 Lv%d=%d개/박스, 자동 Lv%d)" % [
				Skills.fmt(MILESTONES[next_milestone]), _clock(second), Skills.fmt(_boxes_total),
				manual, auto, _level("bundle"), per_box, _level("auto_sort"),
			])
			next_milestone += 1
		done = _total >= GameState.TOTAL_TOYS or _all_full()
	if _total < GameState.TOTAL_TOYS:
		print("1,000만 개 미달: %s 시점에 %s개 (박스 %s개, 선반 모두 참=%s)" % [
			_clock(second), Skills.fmt(_total), Skills.fmt(_boxes_total), _all_full()
		])
	print("끝: %s, 박스 %s / %s" % [
		_clock(second), Skills.fmt(_boxes_total),
		Skills.fmt(GameState.total_shelves() * GameState.BOXES_PER_SHELF)
	])
	print("BALANCE DONE")
	get_tree().quit(0)


func _level(id: String) -> int:
	return int(_levels.get(id, 0))


## 한 번 왕복(줍기 → 걷기 → 넣기)으로 정리하는 초당 박스 수
func _manual_boxes() -> float:
	var carry := Skills.carry(_level("big_hands"))
	var click := CLICK_SECONDS
	var interval := Skills.repeat_interval(_level("quick_hands"))
	if interval > 0.0:
		click = interval
	# 박스 하나에 같은 형태 장난감 BOX_SIZE개를 집어야 한다.
	# 자석은 쿨타임마다 한 번 손을 채워 준다: 그 왕복에서는 찾아다니고 클릭하는 시간이 크게 준다.
	var picks := float(carry * Toys.BOX_SIZE)
	var speed := Skills.speed_mult(_level("sprint"))
	var pick_time := picks * (SEARCH_SECONDS / speed + click)
	var other := WALK_SECONDS / speed + click + POSTURE_SECONDS
	var magnet := _level("magnet")
	if magnet > 0:
		# 자석을 쓴 왕복의 비율 = 왕복 시간 / 쿨타임 (최대 1)
		var assisted := minf(1.0, (other + pick_time * (1.0 - MAGNET_SAVING)) / Skills.cooldown("magnet", magnet))
		pick_time *= 1.0 - MAGNET_SAVING * assisted
	return carry / (other + pick_time)


## 대박 타임 가동률을 반영한 평균 코인 배수
func _coin_mult() -> float:
	var level := _level("jackpot")
	return 1.0 + (Skills.jackpot_mult(level) - 1.0) * Skills.uptime("jackpot", level)


## 열려 있는 층의 선반을 순서대로 채운다. 넣은 박스 수를 돌려준다.
func _store(boxes: int) -> int:
	var remaining := boxes
	while remaining > 0:
		var best_key := ""
		for warehouse_id in _unlocked:
			for floor_index in GameState.FLOORS_PER_WAREHOUSE:
				if floor_index == 1 and not _floor_done(warehouse_id, 0):
					continue
				for shelf_index in GameState.shelves_per_floor(warehouse_id):
					var key := GameState.shelf_key(warehouse_id, floor_index, shelf_index)
					if int(_stored.get(key, 0)) < GameState.BOXES_PER_SHELF:
						best_key = key
						break
				if best_key != "":
					break
			if best_key != "":
				break
		if best_key == "":
			break
		var space := GameState.BOXES_PER_SHELF - int(_stored.get(best_key, 0))
		var put := mini(remaining, space)
		_stored[best_key] = int(_stored.get(best_key, 0)) + put
		remaining -= put
		var points_before := GameState.points_for_boxes(_boxes_total)
		_boxes_total += put
		_points += GameState.points_for_boxes(_boxes_total) - points_before
		_total += put * Toys.BOX_SIZE * Skills.bundle(_level("bundle"))
		for threshold: int in GameState.UNLOCK_THRESHOLDS:
			var warehouse_id: int = GameState.UNLOCK_THRESHOLDS[threshold]
			if _total >= threshold and warehouse_id not in _unlocked:
				_unlocked.append(warehouse_id)
	return boxes - remaining


func _floor_done(warehouse_id: int, floor_index: int) -> bool:
	for shelf_index in GameState.shelves_per_floor(warehouse_id):
		var key := GameState.shelf_key(warehouse_id, floor_index, shelf_index)
		if int(_stored.get(key, 0)) < GameState.BOXES_PER_SHELF:
			return false
	return true


func _all_full() -> bool:
	return _boxes_total >= GameState.total_shelves() * GameState.BOXES_PER_SHELF


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
