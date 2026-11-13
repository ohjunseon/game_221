extends CanvasLayer
## 정리 수·코인·다음 목표, 조준점, 조준 안내, 알림 메시지.

const MESSAGE_SECONDS := 1.5

var _sorted_label: Label
var _coin_label: Label
var _goal_label: Label
var _aim_label: Label
var _message_label: Label
var _message_timer: Timer


func _ready() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(20, 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_sorted_label = _make_label(28)
	_coin_label = _make_label(22)
	_goal_label = _make_label(18)
	for label: Label in [_sorted_label, _coin_label, _goal_label]:
		box.add_child(label)

	var crosshair := _make_centered_label(26, 0.0)
	crosshair.text = "+"
	_aim_label = _make_centered_label(20, 40.0)
	_message_label = _make_centered_label(24, 80.0)
	_message_label.modulate = Color(1.0, 0.9, 0.3)

	_message_timer = Timer.new()
	_message_timer.one_shot = true
	_message_timer.timeout.connect(func() -> void: _message_label.text = "")
	add_child(_message_timer)

	EventBus.toy_sorted.connect(func(_total: int) -> void: _refresh())
	EventBus.coins_changed.connect(func(_coins: int) -> void: _refresh())
	EventBus.aim_text_changed.connect(func(text: String) -> void: _aim_label.text = text)
	EventBus.message_shown.connect(_show_message)
	EventBus.warehouse_unlocked.connect(
		func(id: int) -> void: _show_message("창고 %d 개방!" % id)
	)
	EventBus.shelf_completed.connect(
		func(_w: int, _f: int, _s: int) -> void: _show_message("선반 완성!")
	)
	_refresh()


func _refresh() -> void:
	_sorted_label.text = "정리 %s / %s" % [
		_comma(GameState.total_sorted), _comma(GameState.TOTAL_TOYS)
	]
	_coin_label.text = "코인 %s" % _comma(GameState.coins)
	_goal_label.text = _next_goal_text()


func _next_goal_text() -> String:
	var next_threshold := -1
	for threshold: int in GameState.UNLOCK_THRESHOLDS:
		if threshold > GameState.total_sorted and (next_threshold < 0 or threshold < next_threshold):
			next_threshold = threshold
	if next_threshold < 0:
		return "모든 창고 개방"
	return "다음 목표: %s개 → 창고 %d 개방" % [
		_comma(next_threshold), GameState.UNLOCK_THRESHOLDS[next_threshold]
	]


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_timer.start(MESSAGE_SECONDS)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label


func _make_centered_label(font_size: int, offset_y: float) -> Label:
	var label := _make_label(font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.offset_top = offset_y
	label.offset_bottom = offset_y
	add_child(label)
	return label


func _comma(value: int) -> String:
	var digits := str(value)
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return digits + out
