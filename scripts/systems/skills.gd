class_name Skills
extends RefCounted
## 스킬 정의와 수치 공식. 상태(레벨)는 GameState가 가진다.

## 스킬 포인트 1개당 올릴 수 있는 레벨 수
const CAP_PER_POINT := 10
const BASE_REACH := 3.0
const MAX_COMBO := 10
const CRIT_MULTIPLIER := 5.0

const ORDER: Array[String] = [
	"bundle", "big_hands", "long_arm", "auto_sort", "quick_hands",
	"magnet", "sprint", "critical", "combo",
]

const DEFS := {
	"bundle": {"name": "묶음 정리", "desc": "박스에 장난감이 더 많이 담긴 것으로 계산된다", "base": 40, "growth": 2.3},
	"big_hands": {"name": "큰 손", "desc": "박스를 한 번에 더 많이 든다", "base": 20, "growth": 1.8},
	"long_arm": {"name": "긴 팔", "desc": "웅크리기·점프 없이 모든 단에 넣는다", "base": 150, "growth": 1.8},
	"auto_sort": {"name": "자동 정리", "desc": "가만히 있어도 선반이 채워진다", "base": 200, "growth": 2.0},
	"quick_hands": {"name": "빠른 손", "desc": "마우스를 누르고 있으면 연속으로 줍고 넣는다", "base": 80, "growth": 1.5},
	"magnet": {"name": "자석", "desc": "클릭한 장난감 주변의 같은 형태도 함께 줍는다", "base": 100, "growth": 1.7},
	"sprint": {"name": "달리기", "desc": "이동 속도가 빨라진다", "base": 50, "growth": 1.7},
	"critical": {"name": "크리티컬 정리", "desc": "확률로 코인 5배", "base": 120, "growth": 1.6},
	"combo": {"name": "콤보", "desc": "연속으로 정리하면 코인 보너스", "base": 120, "growth": 1.6},
}


## level -> level+1 강화 비용 (level >= 1)
static func cost(id: String, level: int) -> int:
	return int(DEFS[id]["base"] * pow(DEFS[id]["growth"], level - 1))


## 초반에는 레벨당 +1, 이후에는 1.25배씩
static func bundle(level: int) -> int:
	return maxi(level + 1, int(round(pow(1.25, level))))


static func carry(level: int) -> int:
	return 1 + level


## 초당 자동 정리 개수
static func auto_rate(auto_level: int, bundle_level: int) -> float:
	return auto_base(auto_level) * bundle(bundle_level)


## 묶음을 곱하기 전의 초당 자동 정리 개수
static func auto_base(auto_level: int) -> float:
	if auto_level <= 0:
		return 0.0
	return 0.5 * pow(1.25, auto_level - 1)


## 누르고 있을 때 반복 간격(초). 0이면 반복 없음
static func repeat_interval(level: int) -> float:
	if level <= 0:
		return 0.0
	return maxf(0.06, 0.45 - 0.04 * level)


static func reach(level: int) -> float:
	return BASE_REACH + 0.4 * level


static func speed_mult(level: int) -> float:
	return 1.0 + 0.08 * level


static func magnet_radius(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.6 + 0.35 * level


static func crit_chance(level: int) -> float:
	return minf(0.6, 0.05 * level)


## 콤보 1회당 코인 보너스 비율
static func combo_step(level: int) -> float:
	return 0.02 * level


## 1234567 -> "1,234,567"
static func fmt(value: int) -> String:
	var digits := str(value)
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return digits + out


static func effect_text(id: String, level: int) -> String:
	match id:
		"bundle":
			return "박스 1개 = %d개" % (Toys.BOX_SIZE * bundle(level))
		"big_hands":
			return "박스 최대 %d개 들기" % carry(level)
		"long_arm":
			return "자세 무관, 팔 길이 %.1fm" % reach(level) if level > 0 else "자세 필요"
		"auto_sort":
			return "기본 초당 %.1f개 × 묶음" % auto_base(level) if level > 0 else "없음"
		"quick_hands":
			return "%.2f초마다 반복" % repeat_interval(level) if level > 0 else "클릭만"
		"magnet":
			return "반경 %.1fm" % magnet_radius(level) if level > 0 else "없음"
		"sprint":
			return "속도 ×%.2f" % speed_mult(level)
		"critical":
			return "확률 %d%%" % int(crit_chance(level) * 100.0)
		"combo":
			return "콤보당 +%d%% (최대 %d회)" % [int(combo_step(level) * 100.0), MAX_COMBO]
	return ""
