extends CanvasLayer
## 정리 수·코인·퀘스트, 진행 바, 조준 안내, 알림, 떠오르는 숫자, 스킬 메뉴(Tab).

const MESSAGE_SECONDS := 2.2

var _sorted_label: Label
var _coin_label: Label
var _skill_label: Label
var _carry_label: Label
var _quest_label: Label
var _progress: ProgressBar
var _aim_label: Label
var _message_label: Label
var _message_timer: Timer
var _menu: PanelContainer
var _menu_title: Label
var _rows: Dictionary = {}


func _ready() -> void:
	if not InputMap.has_action("menu"):
		InputMap.add_action("menu")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_TAB
		InputMap.action_add_event("menu", key)

	var box := VBoxContainer.new()
	box.position = Vector2(20, 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_sorted_label = _make_label(28)
	_coin_label = _make_label(22)
	_skill_label = _make_label(18)
	_carry_label = _make_label(18)
	_quest_label = _make_label(18)
	_quest_label.modulate = Color(0.7, 1.0, 0.8)
	for label: Label in [_sorted_label, _coin_label, _skill_label, _carry_label, _quest_label]:
		box.add_child(label)

	_progress = ProgressBar.new()
	_progress.max_value = GameState.TOTAL_TOYS
	_progress.custom_minimum_size = Vector2(460, 22)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_progress.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_progress.offset_top = 14.0
	add_child(_progress)

	var crosshair := _make_centered_label(26, 0.0)
	crosshair.text = "+"
	_aim_label = _make_centered_label(20, 40.0)
	_message_label = _make_centered_label(26, 90.0)
	_message_label.modulate = Color(1.0, 0.9, 0.3)

	_message_timer = Timer.new()
	_message_timer.one_shot = true
	_message_timer.timeout.connect(func() -> void: _message_label.text = "")
	add_child(_message_timer)

	_build_menu()

	EventBus.toy_sorted.connect(func(_total: int) -> void: _refresh())
	EventBus.coins_changed.connect(func(_coins: int) -> void: _refresh())
	EventBus.skills_changed.connect(_refresh)
	EventBus.quest_changed.connect(_refresh)
	EventBus.carried_changed.connect(func(_carried: int, _capacity: int) -> void: _refresh())
	EventBus.aim_text_changed.connect(func(text: String) -> void: _aim_label.text = text)
	EventBus.message_shown.connect(_show_message)
	EventBus.popup_requested.connect(_show_popup)
	EventBus.game_completed.connect(_on_game_completed)
	_refresh()

	var report := GameState.offline_report
	if not report.is_empty() and int(report["stored"]) > 0:
		@warning_ignore("integer_division")
		_show_message("자리를 비운 %d분 동안 %s개가 정리되었습니다" % [
			int(report["seconds"]) / 60, Skills.fmt(int(report["stored"]))
		])


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_set_menu_open(not GameState.menu_open)
		get_viewport().set_input_as_handled()
	elif GameState.menu_open and event.is_action_pressed("ui_cancel"):
		_set_menu_open(false)
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	_sorted_label.text = "정리 %s / %s" % [
		Skills.fmt(GameState.total_sorted), Skills.fmt(GameState.TOTAL_TOYS)
	]
	_coin_label.text = "코인 %s" % Skills.fmt(GameState.coins)
	var skill_text := "스킬 포인트 %d (Tab: 스킬)" % GameState.skill_points
	var rate := GameState.auto_rate()
	if rate > 0.0:
		skill_text += "   자동 정리 초당 %s개" % Skills.fmt(int(rate))
	_skill_label.text = skill_text
	_skill_label.modulate = Color(1.0, 0.9, 0.3) if GameState.skill_points > 0 else Color.WHITE
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		_carry_label.text = "들고 있는 장난감 %d / %d (묶음 ×%s)" % [
			player.carried, player.carry_capacity(),
			Skills.fmt(Skills.bundle(GameState.level("bundle")))
		]
	_quest_label.text = QuestManager.text()
	_progress.value = GameState.total_sorted
	if GameState.menu_open:
		_refresh_menu()


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_timer.start(MESSAGE_SECONDS)


func _show_popup(text: String) -> void:
	var label := _make_label(24)
	label.text = text
	label.modulate = Color(0.6, 1.0, 0.6)
	add_child(label)
	var center := get_viewport().get_visible_rect().size / 2.0
	label.position = center + Vector2(randf_range(-90.0, 50.0), randf_range(-90.0, -50.0))
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 70.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)


func _on_game_completed() -> void:
	_message_label.text = "장난감 1,000만 개 정리 완료! 축하합니다!"
	_message_timer.start(60.0)
	Sfx.play("unlock")
	EventBus.shake_requested.emit(1.0)


func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.visible = false
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_menu)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_menu.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_menu_title = Label.new()
	_menu_title.add_theme_font_size_override("font_size", 24)
	column.add_child(_menu_title)

	for id in Skills.ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(210, 0)
		var effect_label := Label.new()
		effect_label.custom_minimum_size = Vector2(430, 0)
		effect_label.add_theme_font_size_override("font_size", 14)
		var button := Button.new()
		button.custom_minimum_size = Vector2(190, 0)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_skill_pressed.bind(id))
		row.add_child(name_label)
		row.add_child(effect_label)
		row.add_child(button)
		column.add_child(row)
		_rows[id] = {"name": name_label, "effect": effect_label, "button": button}

	var hint := Label.new()
	hint.text = "선반 하나를 완성하면 스킬 포인트 1개를 얻습니다. 포인트로 새 스킬을 배우거나 최대 레벨을 늘립니다."
	hint.add_theme_font_size_override("font_size", 14)
	column.add_child(hint)


func _set_menu_open(open: bool) -> void:
	GameState.menu_open = open
	_menu.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_refresh_menu()


func _refresh_menu() -> void:
	_menu_title.text = "스킬   ·   스킬 포인트 %d   ·   코인 %s   (Tab: 닫기)" % [
		GameState.skill_points, Skills.fmt(GameState.coins)
	]
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		var level := GameState.level(id)
		var limit := GameState.cap(id)
		var definition: Dictionary = Skills.DEFS[id]
		var button: Button = row["button"]
		if level <= 0:
			row["name"].text = "%s  (미습득)" % definition["name"]
			row["effect"].text = definition["desc"]
			button.text = "배우기 (포인트 1)"
			button.disabled = GameState.skill_points <= 0
		else:
			row["name"].text = "%s  Lv.%d / %d" % [definition["name"], level, limit]
			row["effect"].text = "%s\n지금: %s  →  다음: %s" % [
				definition["desc"], Skills.effect_text(id, level), Skills.effect_text(id, level + 1)
			]
			if level < limit:
				var price := Skills.cost(id, level)
				button.text = "강화 %s 코인" % Skills.fmt(price)
				button.disabled = GameState.coins < price
			else:
				button.text = "한계 돌파 (포인트 1)"
				button.disabled = GameState.skill_points <= 0


func _on_skill_pressed(id: String) -> void:
	var level := GameState.level(id)
	var done := false
	if level <= 0:
		done = GameState.learn(id)
	elif level < GameState.cap(id):
		done = GameState.upgrade(id)
	else:
		done = GameState.breakthrough(id)
	Sfx.play("buy" if done else "error")
	_refresh()


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
