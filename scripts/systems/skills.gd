class_name Skills
extends RefCounted
## 액션 스킬 4종(1~4 키로 발동)과 업그레이드 4종(항상 적용)의 정의와 수치 공식.
## 상태(레벨, 발동 시각)는 GameState가 가진다.

## 스킬 포인트 1개당 올릴 수 있는 액션 스킬 레벨 수
const CAP_PER_POINT := 10
const BASE_REACH := 3.0

## 슬롯 순서 = 숫자키 1~4
const ACTION_ORDER: Array[String] = ["magnet", "long_arm", "auto_sort", "jackpot"]
const UPGRADE_ORDER: Array[String] = ["bundle", "big_hands", "quick_hands", "sprint"]

const DEFS := {
	"magnet": {"name": "자석", "desc": "주변 장난감이 손으로 날아온다", "base": 100, "growth": 1.7},
	"long_arm": {"name": "긴 팔", "desc": "자세 상관없이 멀리서도 선반에 넣는다", "base": 150, "growth": 1.7},
	"auto_sort": {"name": "자동 정리", "desc": "선반이 알아서 채워진다", "base": 200, "growth": 2.0},
	"jackpot": {"name": "대박 타임", "desc": "받는 코인이 몇 배가 된다", "base": 150, "growth": 1.8},
	"bundle": {"name": "묶음 정리", "desc": "박스에 장난감이 더 많이 담긴 것으로 계산된다", "base": 40, "growth": 2.3},
	"big_hands": {"name": "큰 손", "desc": "박스를 한 번에 더 많이 든다", "base": 20, "growth": 1.8},
	"quick_hands": {"name": "빠른 손", "desc": "마우스를 누르고 있으면 연속으로 줍고 넣는다", "base": 80, "growth": 1.5},
	"sprint": {"name": "달리기", "desc": "이동 속도가 빨라진다", "base": 50, "growth": 1.7},
}


static func is_action(id: String) -> bool:
	return id in ACTION_ORDER


## level -> level+1 강화 비용. 액션 스킬은 Lv1부터, 업그레이드는 Lv0부터 시작한다.
static func cost(id: String, level: int) -> int:
	var steps := level - 1 if is_action(id) else level
	return int(DEFS[id]["base"] * pow(DEFS[id]["growth"], steps))


## 발동 후 효과가 유지되는 시간(초)
static func duration(id: String, level: int) -> float:
	match id:
		"magnet":
			return 4.0 + 0.6 * level
		"long_arm":
			return 6.0 + 1.0 * level
		"auto_sort":
			return 5.0 + 1.0 * level
		"jackpot":
			return 6.0 + 0.6 * level
	return 0.0


## 발동 시점부터 다시 쓸 수 있을 때까지의 시간(초). 레벨이 오르면 지속 시간보다 짧아져 계속 켤 수 있다.
static func cooldown(id: String, level: int) -> float:
	match id:
		"magnet":
			return maxf(8.0, 20.0 - 0.5 * level)
		"long_arm":
			return maxf(10.0, 25.0 - 0.5 * level)
		"auto_sort":
			return maxf(10.0, 30.0 - 0.6 * level)
		"jackpot":
			return maxf(15.0, 40.0 - 0.7 * level)
	return 0.0


## 켜져 있는 시간의 비율 (0~1)
static func uptime(id: String, level: int) -> float:
	if level <= 0:
		return 0.0
	return minf(1.0, duration(id, level) / cooldown(id, level))


static func magnet_radius(level: int) -> float:
	return 2.5 + 0.4 * level


## 긴 팔이 켜져 있을 때 닿는 거리
static func reach(level: int) -> float:
	return BASE_REACH + 3.0 + 0.5 * level


static func jackpot_mult(level: int) -> float:
	return 3.0 + 0.5 * level


## 자동 정리가 켜져 있을 때 초당 채워지는 박스 수
static func auto_boxes(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.5 * pow(1.25, level - 1)


## 자동 정리가 켜져 있을 때 초당 정리 개수
static func auto_rate(auto_level: int, bundle_level: int) -> float:
	return auto_boxes(auto_level) * Toys.BOX_SIZE * bundle(bundle_level)


## 초반에는 레벨당 +1, 이후에는 1.25배씩
static func bundle(level: int) -> int:
	return maxi(level + 1, int(round(pow(1.25, level))))


## 한 번에 들 수 있는 박스 수
static func carry(level: int) -> int:
	return 1 + level


## 누르고 있을 때 반복 간격(초). 0이면 반복 없음
static func repeat_interval(level: int) -> float:
	if level <= 0:
		return 0.0
	return maxf(0.06, 0.45 - 0.04 * level)


static func speed_mult(level: int) -> float:
	return 1.0 + 0.08 * level


## 1234567 -> "1,234,567"
static func fmt(value: int) -> String:
	var digits := str(value)
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return digits + out


static func effect_text(id: String, level: int) -> String:
	if is_action(id):
		var timing := "%.0f초 지속 / %.0f초마다" % [duration(id, level), cooldown(id, level)]
		match id:
			"magnet":
				return "반경 %.1fm, %s" % [magnet_radius(level), timing]
			"long_arm":
				return "팔 길이 %.1fm, %s" % [reach(level), timing]
			"auto_sort":
				return "초당 박스 %.1f개, %s" % [auto_boxes(level), timing]
			"jackpot":
				return "코인 ×%.1f, %s" % [jackpot_mult(level), timing]
	match id:
		"bundle":
			return "박스 1개 = %d개" % (Toys.BOX_SIZE * bundle(level))
		"big_hands":
			return "박스 최대 %d개 들기" % carry(level)
		"quick_hands":
			return "%.2f초마다 반복" % repeat_interval(level) if level > 0 else "클릭만"
		"sprint":
			return "속도 ×%.2f" % speed_mult(level)
	return ""
