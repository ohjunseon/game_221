class_name Story
extends CanvasLayer
## 오프닝·엔딩 그림 카드. 카드마다 그림(StoryArt)과 대사가 나오고,
## 클릭·스페이스·엔터로 넘기며 ESC로 건너뛴다. 다 보면 `finished`를 보낸다.

signal finished

const CHARS_PER_SECOND := 28.0
const FADE_SECONDS := 0.35
const KID := "민준"
const DAD := "아빠"
const BEAR := "곰 반장"

## 오프닝: 아빠에게 혼나고 잠든 민준이가 꿈속 장난감 물류창고로 간다.
const OPENING: Array[Dictionary] = [
	{"art": "room_night", "speaker": "", "text": "어느 날 밤, 민준이의 방.\n바닥에는 장난감이 발 디딜 틈도 없이 널려 있었어요."},
	{"art": "dad", "speaker": DAD, "text": "민준아! 장난감 정리 안 하면 내일 몽땅 갖다 버린다!"},
	{"art": "room_night", "speaker": KID, "text": "치… 이 많은 걸 언제 다 정리해. 내일 할래…"},
	{"art": "sleep", "speaker": "", "text": "민준이는 그대로 침대에 쓰러져 잠이 들었어요. 쿨쿨…"},
	{"art": "dream", "speaker": "", "text": "그런데 꿈속에서… 어디선가 확성기 소리가 들려왔어요."},
	{"art": "bear", "speaker": BEAR, "text": "삐익! 신입 정리 요원 민준! 장난감 물류창고에 온 걸 환영한다!"},
	{"art": "bear", "speaker": BEAR, "text": "여기 있는 장난감 1,000만 개를 박스에 담아 선반에 전부 정리해라.\n그래야 꿈에서 깰 수 있다!"},
	{"art": "bear", "speaker": KID, "text": "1,000만 개요?! 우리 방 장난감보다 훨씬 많잖아요!"},
	{"art": "bear", "speaker": BEAR, "text": "걱정 마라. 하다 보면 손도 빨라지고 멋진 기술도 배우게 된다.\n자, 정리 시작!"},
]

## 엔딩 앞부분: 정리를 마치고 곰 반장이 칭찬한다. 이어서 3D 장면에서 거대 상자가 떨어진다.
const ENDING_BEFORE_BOX: Array[Dictionary] = [
	{"art": "cheer", "speaker": BEAR, "text": "해냈구나, 민준! 장난감 1,000만 개 정리 완료!\n넌 최고의 정리 요원이다!"},
	{"art": "cheer", "speaker": BEAR, "text": "자, 이건 내가 주는 마지막 선물… 어? 어어?\n위, 위를 봐라!"},
]

## 엔딩 뒷부분: 상자에 깔려 잠에서 깬다.
const ENDING_AFTER_BOX: Array[Dictionary] = [
	{"art": "flash", "speaker": "", "text": "쿠우웅—!!", "shake": true},
	{"art": "room_morning", "speaker": KID, "text": "헉…! 꿈이었구나. 침대에서 굴러떨어졌네…"},
	{"art": "dad_morning", "speaker": DAD, "text": "일어났니? 어젯밤 약속 기억하지? 방이 아직 그대로구나."},
	{"art": "room_morning", "speaker": KID, "text": "걱정 마세요, 아빠.\n꿈에서 1,000만 개도 정리했는데, 이 정도쯤이야!"},
	{"art": "clean_room", "speaker": "", "text": "민준이는 눈 깜짝할 사이에 방을 반짝반짝 정리했어요."},
	{"art": "end", "speaker": "", "text": "끝 — 플레이해 줘서 고마워요!"},
]

var cards: Array[Dictionary] = []
var index: int = -1
var _art: StoryArt
var _speaker: Label
var _text: Label
var _fade: ColorRect
var _typing: float = 0.0
var _busy: bool = false
var _done: bool = false


## 카드 묶음을 보여 줄 Story 노드를 만든다. `parent`에 붙이면 바로 시작한다.
static func play(parent: Node, list: Array[Dictionary]) -> Story:
	var story := Story.new()
	story.cards = list
	parent.add_child(story)
	return story


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_art = StoryArt.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_art)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 60.0
	panel.offset_right = -60.0
	panel.offset_top = -200.0
	panel.offset_bottom = -30.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.1, 0.2, 0.9)
	box.set_corner_radius_all(22)
	box.set_border_width_all(4)
	box.border_color = Color(1.0, 0.84, 0.32)
	box.content_margin_left = 30.0
	box.content_margin_right = 30.0
	box.content_margin_top = 18.0
	box.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 26)
	_speaker.add_theme_color_override("font_color", Color(1.0, 0.84, 0.32))
	column.add_child(_speaker)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 30)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_text)
	var hint := Label.new()
	hint.text = "클릭 · 스페이스: 다음      ESC: 건너뛰기"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.64, 0.68, 0.78))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(hint)

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)

	GameState.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	next()


func _process(delta: float) -> void:
	if index < 0 or index >= cards.size():
		return
	var full: String = cards[index]["text"]
	if _typing < full.length():
		_typing += delta * CHARS_PER_SECOND
		_text.visible_characters = int(_typing)


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		finish()
	elif (
		event.is_action_pressed("ui_accept")
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	):
		get_viewport().set_input_as_handled()
		advance()


## 글자가 다 안 나왔으면 다 보여 주고, 다 나왔으면 다음 카드로 간다.
func advance() -> void:
	if _busy or index < 0:
		return
	var full: String = cards[index]["text"]
	if _typing < full.length():
		_typing = full.length()
		_text.visible_characters = -1
	else:
		next()


func next() -> void:
	index += 1
	if index >= cards.size():
		finish()
		return
	var card: Dictionary = cards[index]
	var art_changed: bool = index == 0 or cards[index - 1]["art"] != card["art"]
	if art_changed:
		_busy = true
		var tween := create_tween()
		if index > 0:
			tween.tween_property(_fade, "color:a", 1.0, FADE_SECONDS * 0.6)
		tween.tween_callback(_show_card.bind(card))
		tween.tween_property(_fade, "color:a", 0.0, FADE_SECONDS)
		tween.tween_callback(func() -> void: _busy = false)
	else:
		_show_card(card)


func _show_card(card: Dictionary) -> void:
	_art.scene = card["art"]
	_art.queue_redraw()
	_speaker.text = card["speaker"]
	_speaker.visible = card["speaker"] != ""
	_text.text = card["text"]
	_text.visible_characters = 0
	_typing = 0.0
	Sfx.play("pick", 1.2)
	if card.get("shake", false):
		Sfx.play("rumble", 0.8)
		var tween := create_tween()
		for i in 8:
			tween.tween_property(_art, "position", Vector2(randf_range(-18, 18), randf_range(-18, 18)), 0.04)
		tween.tween_property(_art, "position", Vector2.ZERO, 0.05)


func finish() -> void:
	if _done:
		return
	_done = true
	GameState.menu_open = false
	finished.emit()
	queue_free()
