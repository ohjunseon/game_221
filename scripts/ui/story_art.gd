class_name StoryArt
extends Control
## 오프닝·엔딩 카드의 그림. 그림 파일 없이 도형으로 그린다.
## 1280×720 기준 좌표로 그리고 화면 크기에 맞춰 늘린다.

const BASE := Vector2(1280, 720)
const TOY_COLORS: Array[Color] = [
	Color(1.0, 0.45, 0.45), Color(1.0, 0.8, 0.3), Color(0.45, 0.8, 1.0),
	Color(0.5, 0.9, 0.55), Color(0.8, 0.55, 1.0), Color(1.0, 0.6, 0.85),
]
const SKIN := Color(1.0, 0.84, 0.7)
const BEAR_BROWN := Color(0.72, 0.5, 0.3)

var scene: String = "room_night"
var _font: Font


func _ready() -> void:
	_font = get_theme_default_font()
	resized.connect(queue_redraw)


func _draw() -> void:
	var fit := size / BASE
	draw_set_transform(Vector2.ZERO, 0.0, fit)
	match scene:
		"room_night":
			_room(false, true)
			_kid(Vector2(560, 470), 1.0, false)
		"dad":
			_room(false, true)
			_door(true, false)
			_dad(Vector2(180, 500), true)
			_kid(Vector2(640, 470), 1.0, false)
			_text_at("!", Vector2(250, 190), 90, Color(1.0, 0.84, 0.32))
		"sleep":
			_room(false, true)
			_sleeper(Vector2(960, 330))
			_text_at("Z", Vector2(1040, 230), 52, Color.WHITE)
			_text_at("z", Vector2(1090, 180), 40, Color(1, 1, 1, 0.8))
			_text_at("z", Vector2(1125, 140), 30, Color(1, 1, 1, 0.6))
		"dream":
			_dream(true)
		"title":
			_dream(false)
		"bear":
			_warehouse()
			_bear(Vector2(760, 420), false)
			_kid(Vector2(330, 500), 1.0, false)
		"cheer":
			_warehouse()
			_confetti()
			_bear(Vector2(760, 420), true)
			_kid(Vector2(330, 500), 1.0, true)
		"flash":
			draw_rect(Rect2(Vector2.ZERO, BASE), Color(1.0, 0.98, 0.9))
			_giant_box(Vector2(640, 300), 1.6)
		"room_morning":
			_room(true, true)
			_kid(Vector2(820, 520), 1.0, false)
			_text_at("?", Vector2(860, 300), 60, Color(0.2, 0.25, 0.45))
		"dad_morning":
			_room(true, true)
			_door(true, true)
			_dad(Vector2(180, 500), false)
			_kid(Vector2(820, 520), 1.0, false)
		"clean_room":
			_room(true, false)
			_toy_chest(Vector2(560, 470))
			_kid(Vector2(820, 490), 1.0, true)
			_sparkles()
		"end":
			draw_rect(Rect2(Vector2.ZERO, BASE), Color(0.12, 0.15, 0.28))
			_confetti()
			_text_at("끝", Vector2(640, 300), 200, Color(1.0, 0.84, 0.32))
			_toy_chest(Vector2(640, 400))
	draw_set_transform(Vector2.ZERO)


## 민준이의 방: 벽, 창문, 침대, 바닥. messy면 바닥에 장난감이 널려 있다.
func _room(morning: bool, messy: bool) -> void:
	var wall := Color(0.98, 0.9, 0.75) if morning else Color(0.22, 0.25, 0.45)
	var floor_color := Color(0.85, 0.65, 0.45) if morning else Color(0.32, 0.27, 0.35)
	draw_rect(Rect2(0, 0, 1280, 470), wall)
	draw_rect(Rect2(0, 470, 1280, 250), floor_color)
	draw_rect(Rect2(0, 462, 1280, 14), wall.darkened(0.25))
	# 창문
	var sky := Color(0.6, 0.85, 1.0) if morning else Color(0.06, 0.08, 0.2)
	draw_rect(Rect2(560, 90, 260, 200), Color(0.95, 0.95, 1.0))
	draw_rect(Rect2(572, 102, 236, 176), sky)
	draw_rect(Rect2(686, 102, 8, 176), Color(0.95, 0.95, 1.0))
	if morning:
		draw_circle(Vector2(760, 160), 34, Color(1.0, 0.86, 0.35))
	else:
		draw_circle(Vector2(760, 160), 28, Color(1.0, 0.97, 0.8))
		draw_circle(Vector2(774, 150), 24, sky)
		for p: Vector2 in [Vector2(610, 140), Vector2(640, 230), Vector2(720, 250), Vector2(600, 200)]:
			draw_circle(p, 3, Color.WHITE)
	# 침대
	draw_rect(Rect2(860, 330, 380, 150), Color(0.45, 0.6, 0.95))
	draw_rect(Rect2(860, 300, 380, 50), Color(0.95, 0.95, 1.0))
	draw_rect(Rect2(1200, 230, 40, 260), Color(0.55, 0.38, 0.25))
	draw_rect(Rect2(860, 470, 380, 20), Color(0.55, 0.38, 0.25))
	draw_rect(Rect2(1100, 300, 90, 40), Color(1.0, 1.0, 1.0))
	if messy:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 34:
			var pos := Vector2(rng.randf_range(40, 1240), rng.randf_range(500, 700))
			var color := TOY_COLORS[i % TOY_COLORS.size()]
			if not morning:
				color = color.darkened(0.35)
			_toy(pos, rng.randf_range(16, 30), color, i % 3)


func _toy(pos: Vector2, r: float, color: Color, shape: int) -> void:
	match shape:
		0:
			draw_rect(Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), color)
			draw_rect(Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), color.darkened(0.3), false, 3.0)
		1:
			draw_circle(pos, r, color)
			draw_circle(pos + Vector2(-r * 0.3, -r * 0.3), r * 0.3, color.lightened(0.4))
		_:
			draw_colored_polygon(PackedVector2Array([
				pos + Vector2(0, -r), pos + Vector2(r, r), pos + Vector2(-r, r)
			]), color)


func _door(open: bool, morning: bool) -> void:
	draw_rect(Rect2(90, 150, 210, 320), Color(0.4, 0.28, 0.2))
	if open:
		var light := Color(1.0, 0.95, 0.75) if not morning else Color(1.0, 1.0, 0.95)
		draw_rect(Rect2(104, 164, 182, 306), light)
		draw_colored_polygon(PackedVector2Array([
			Vector2(104, 470), Vector2(286, 470), Vector2(420, 720), Vector2(0, 720)
		]), Color(light, 0.35))


## 사람 그림: 동그란 머리, 몸통, 팔다리. happy면 두 팔을 든다.
func _kid(pos: Vector2, s: float, happy: bool) -> void:
	## happy가 아니면 입이 삐죽하다
	_person(pos, s, Color(1.0, 0.55, 0.3), Color(0.25, 0.35, 0.7), Color(0.25, 0.18, 0.12), happy, happy)


func _dad(pos: Vector2, angry: bool) -> void:
	_person(pos, 1.45, Color(0.35, 0.6, 0.45), Color(0.3, 0.3, 0.38), Color(0.15, 0.12, 0.1), false, not angry)
	if angry:
		var head := pos + Vector2(0, -175 * 1.45)
		draw_line(head + Vector2(-26, -14), head + Vector2(-8, -6), Color.BLACK, 5.0)
		draw_line(head + Vector2(26, -14), head + Vector2(8, -6), Color.BLACK, 5.0)


func _person(pos: Vector2, s: float, shirt: Color, pants: Color, hair: Color, arms_up: bool, smile: bool = true) -> void:
	var head := pos + Vector2(0, -175) * s
	# 다리
	draw_line(pos + Vector2(-16, -60) * s, pos + Vector2(-20, 0) * s, pants, 18 * s)
	draw_line(pos + Vector2(16, -60) * s, pos + Vector2(20, 0) * s, pants, 18 * s)
	# 몸통
	draw_rect(Rect2(pos + Vector2(-36, -135) * s, Vector2(72, 80) * s), shirt)
	# 팔
	var arm_end := Vector2(64, -190) if arms_up else Vector2(56, -70)
	draw_line(pos + Vector2(-32, -125) * s, pos + Vector2(-arm_end.x, arm_end.y) * s, shirt, 14 * s)
	draw_line(pos + Vector2(32, -125) * s, pos + arm_end * s, shirt, 14 * s)
	# 머리
	draw_circle(head, 42 * s, SKIN)
	draw_circle(head + Vector2(0, -16) * s, 40 * s, hair, true)
	draw_circle(head + Vector2(0, 6) * s, 36 * s, SKIN)
	draw_circle(head + Vector2(-13, 4) * s, 4.5 * s, Color.BLACK)
	draw_circle(head + Vector2(13, 4) * s, 4.5 * s, Color.BLACK)
	if smile:
		draw_arc(head + Vector2(0, 16) * s, 10 * s, 0.3, PI - 0.3, 10, Color(0.6, 0.2, 0.2), 3.0 * s)
	else:
		draw_arc(head + Vector2(0, 30) * s, 10 * s, PI + 0.5, TAU - 0.5, 10, Color(0.6, 0.2, 0.2), 3.0 * s)


func _sleeper(pos: Vector2) -> void:
	draw_circle(pos + Vector2(170, -16), 36, SKIN)
	draw_circle(pos + Vector2(180, -30), 32, Color(0.25, 0.18, 0.12))
	draw_rect(Rect2(pos + Vector2(-90, -30), Vector2(230, 60)), Color(1.0, 0.75, 0.4))
	draw_line(pos + Vector2(160, -14), pos + Vector2(172, -14), Color.BLACK, 3.0)


func _dream(sleeper: bool) -> void:
	draw_rect(Rect2(Vector2.ZERO, BASE), Color(0.25, 0.15, 0.45))
	for i in 7:
		draw_circle(Vector2(640, 330), 520 - i * 70, Color(0.45 + i * 0.05, 0.3 + i * 0.04, 0.75, 0.25))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 60:
		draw_circle(Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720)), rng.randf_range(1.5, 4), Color.WHITE)
	for i in 10:
		var angle := TAU * i / 10.0
		var pos := Vector2(640, 330) + Vector2(cos(angle), sin(angle)) * 230
		_toy(pos, 24, TOY_COLORS[i % TOY_COLORS.size()], i % 3)
	if sleeper:
		_sleeper(Vector2(560, 340))


## 꿈속 창고: 회색 벽, 선반 줄, 박스.
func _warehouse() -> void:
	draw_rect(Rect2(0, 0, 1280, 500), Color(0.62, 0.68, 0.78))
	draw_rect(Rect2(0, 500, 1280, 220), Color(0.5, 0.52, 0.56))
	for x: int in [40, 1000]:
		for tier in 4:
			var y: float = 120 + tier * 95
			draw_rect(Rect2(x, y + 70, 240, 10), Color(0.95, 0.5, 0.2))
			for b in 4:
				draw_rect(Rect2(x + 10 + b * 58, y + 20, 50, 50), Color(0.82, 0.62, 0.4))
		draw_rect(Rect2(x, 120, 10, 390), Color(0.2, 0.35, 0.7))
		draw_rect(Rect2(x + 230, 120, 10, 390), Color(0.2, 0.35, 0.7))
	draw_rect(Rect2(0, 560, 1280, 12), Color(1.0, 0.84, 0.32))


## 곰 반장: 모자를 쓴 곰. 평소엔 확성기를 들고, 기쁠 땐 두 팔을 든다.
func _bear(pos: Vector2, cheering: bool) -> void:
	var dark := BEAR_BROWN.darkened(0.25)
	var belly := Color(0.92, 0.78, 0.6)
	# 몸
	draw_circle(pos + Vector2(0, -60), 110, BEAR_BROWN)
	draw_circle(pos + Vector2(0, -50), 70, belly)
	# 머리
	var head := pos + Vector2(0, -230)
	draw_circle(head + Vector2(-70, -60), 34, BEAR_BROWN)
	draw_circle(head + Vector2(70, -60), 34, BEAR_BROWN)
	draw_circle(head + Vector2(-70, -60), 18, dark)
	draw_circle(head + Vector2(70, -60), 18, dark)
	draw_circle(head, 92, BEAR_BROWN)
	draw_circle(head + Vector2(0, 28), 40, belly)
	draw_circle(head + Vector2(0, 14), 12, Color(0.15, 0.1, 0.08))
	draw_circle(head + Vector2(-32, -16), 9, Color.BLACK)
	draw_circle(head + Vector2(32, -16), 9, Color.BLACK)
	draw_arc(head + Vector2(0, 34), 16, 0.4, PI - 0.4, 10, Color(0.15, 0.1, 0.08), 4.0)
	# 반장 모자
	draw_rect(Rect2(head + Vector2(-70, -110), Vector2(140, 46)), Color(0.2, 0.3, 0.65))
	draw_rect(Rect2(head + Vector2(-86, -70), Vector2(172, 14)), Color(0.15, 0.22, 0.5))
	draw_circle(head + Vector2(0, -88), 12, Color(1.0, 0.84, 0.32))
	# 팔과 확성기
	if cheering:
		draw_line(pos + Vector2(-90, -110), pos + Vector2(-150, -250), BEAR_BROWN, 34)
		draw_line(pos + Vector2(90, -110), pos + Vector2(150, -250), BEAR_BROWN, 34)
	else:
		draw_line(pos + Vector2(-90, -100), pos + Vector2(-170, -150), BEAR_BROWN, 34)
		draw_colored_polygon(PackedVector2Array([
			pos + Vector2(-180, -165), pos + Vector2(-260, -215),
			pos + Vector2(-260, -95), pos + Vector2(-180, -140),
		]), Color(1.0, 0.84, 0.32))
		for i in 3:
			draw_arc(pos + Vector2(-270, -155), 30 + i * 22, PI * 0.75, PI * 1.25, 8, Color.WHITE, 4.0)


func _confetti() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 80:
		var pos := Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 520))
		draw_rect(Rect2(pos, Vector2(12, 7)), TOY_COLORS[i % TOY_COLORS.size()])


func _giant_box(center: Vector2, s: float) -> void:
	var half := Vector2(220, 160) * s
	draw_rect(Rect2(center - half, half * 2.0), Color(0.82, 0.6, 0.38))
	draw_rect(Rect2(center - half, half * 2.0), Color(0.55, 0.38, 0.22), false, 8.0)
	draw_rect(Rect2(center + Vector2(-30 * s, -half.y), Vector2(60 * s, half.y * 2.0)), Color(0.95, 0.85, 0.55))
	_text_at("장난감", center + Vector2(0, 70 * s), int(56 * s), Color(0.45, 0.28, 0.15))


func _toy_chest(pos: Vector2) -> void:
	for i in 6:
		_toy(pos + Vector2(-90 + i * 36, -70 - (i % 2) * 16), 22, TOY_COLORS[i], i % 3)
	draw_rect(Rect2(pos + Vector2(-140, -70), Vector2(280, 130)), Color(0.9, 0.45, 0.35))
	draw_rect(Rect2(pos + Vector2(-140, -70), Vector2(280, 22)), Color(0.75, 0.32, 0.25))
	draw_circle(pos, 18, Color(1.0, 0.84, 0.32))


func _sparkles() -> void:
	for p: Vector2 in [Vector2(300, 380), Vector2(480, 330), Vector2(700, 380), Vector2(1000, 260), Vector2(200, 560)]:
		draw_line(p + Vector2(-16, 0), p + Vector2(16, 0), Color(1.0, 0.95, 0.5), 4.0)
		draw_line(p + Vector2(0, -16), p + Vector2(0, 16), Color(1.0, 0.95, 0.5), 4.0)


func _text_at(text: String, center: Vector2, font_size: int, color: Color) -> void:
	if _font == null:
		return
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, center + Vector2(-width / 2.0, font_size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
