extends CanvasLayer
## 정리 수·코인·퀘스트, 진행 바, 조준 안내, 알림, 떠오르는 숫자,
## 화면 아래 스킬 슬롯 4칸(1~4 키), 스킬·업그레이드 메뉴(Tab).

const MESSAGE_SECONDS := 2.2
const SLOT_READY := Color(1.0, 0.9, 0.3)
const SLOT_ACTIVE := Color(0.5, 1.0, 0.5)
const SLOT_WAITING := Color(0.65, 0.65, 0.7)

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
var _slot_labels: Array[Label] = []
var _slot_bars: Array[ProgressBar] = []


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

	_build_slots()
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


func _process(_delta: float) -> void:
	_refresh_slots()


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
	_skill_label.text = "스킬 포인트 %d (Tab: 스킬·업그레이드)" % GameState.skill_points
	_skill_label.modulate = Color(1.0, 0.9, 0.3) if GameState.skill_points > 0 else Color.WHITE
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		_carry_label.text = player.carry_text()
	_quest_label.text = QuestManager.text()
	_progress.value = GameState.total_sorted
	if GameState.menu_open:
		_refresh_menu()


## 슬롯마다 잠김 / 준비 / 사용 중 / 쿨타임을 보여 준다.
func _refresh_slots() -> void:
	for slot in Skills.ACTION_ORDER.size():
		var id := Skills.ACTION_ORDER[slot]
		var level := GameState.level(id)
		var label := _slot_labels[slot]
		var bar := _slot_bars[slot]
		var title := "[%d] %s" % [slot + 1, Skills.DEFS[id]["name"]]
		if level <= 0:
			label.text = "%s\n잠김" % title
			label.modulate = SLOT_WAITING
			bar.value = 0.0
		elif GameState.is_active(id):
			label.text = "%s\n사용 중 %.1f초" % [title, GameState.active_left(id)]
			label.modulate = SLOT_ACTIVE
			bar.value = GameState.active_left(id) / Skills.duration(id, level)
		elif GameState.cooldown_left(id) > 0.0:
			label.text = "%s\n쿨타임 %d초" % [title, ceili(GameState.cooldown_left(id))]
			label.modulate = SLOT_WAITING
			bar.value = 1.0 - GameState.cooldown_left(id) / Skills.cooldown(id, level)
		else:
			label.text = "%s\n준비 완료" % title
			label.modulate = SLOT_READY
			bar.value = 1.0


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


func _build_slots() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_bottom = -16.0
	add_child(row)

	for slot in Skills.ACTION_ORDER.size():
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(150, 70)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.1, 0.12, 0.16, 0.8)
		background.set_corner_radius_all(8)
		background.set_content_margin_all(6)
		panel.add_theme_stylebox_override("panel", background)
		row.add_child(panel)

		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(column)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 16)
		column.add_child(label)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(bar)
		_slot_labels.append(label)
		_slot_bars.append(bar)


func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.visible = false
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.1, 0.12, 0.16, 0.97)
	background.set_corner_radius_all(10)
	_menu.add_theme_stylebox_override("panel", background)
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

	_add_section(column, "액션 스킬  ·  숫자키 1~4로 발동, 스킬 포인트로 배운다")
	for id in Skills.ACTION_ORDER:
		_add_row(column, id)
	_add_section(column, "업그레이드  ·  항상 적용, 코인으로 올린다")
	for id in Skills.UPGRADE_ORDER:
		_add_row(column, id)

	var hint := Label.new()
	hint.text = "선반 하나를 완성하면 스킬 포인트 1개를 얻습니다. 포인트로 액션 스킬을 배우거나 최대 레벨을 늘립니다."
	hint.add_theme_font_size_override("font_size", 14)
	column.add_child(hint)


func _add_section(column: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.modulate = Color(1.0, 0.9, 0.3)
	column.add_child(label)


func _add_row(column: VBoxContainer, id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(220, 0)
	var effect_label := Label.new()
	effect_label.custom_minimum_size = Vector2(470, 0)
	effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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


func _set_menu_open(open: bool) -> void:
	GameState.menu_open = open
	_menu.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_refresh_menu()


func _refresh_menu() -> void:
	_menu_title.text = "스킬 포인트 %d   ·   코인 %s   (Tab: 닫기)" % [
		GameState.skill_points, Skills.fmt(GameState.coins)
	]
	for id: String in _rows:
		var row: Dictionary = _rows[id]
		var level := GameState.level(id)
		var definition: Dictionary = Skills.DEFS[id]
		var button: Button = row["button"]
		var is_action := Skills.is_action(id)
		var prefix := ""
		if is_action:
			prefix = "[%d] " % (Skills.ACTION_ORDER.find(id) + 1)

		if is_action and level <= 0:
			row["name"].text = "%s%s  (미습득)" % [prefix, definition["name"]]
			row["effect"].text = "%s\n%s" % [definition["desc"], Skills.effect_text(id, 1)]
			button.text = "배우기 (포인트 1)"
			button.disabled = GameState.skill_points <= 0
			continue

		row["effect"].text = "%s\n지금: %s  →  다음: %s" % [
			definition["desc"], Skills.effect_text(id, level), Skills.effect_text(id, level + 1)
		]
		if is_action and level >= GameState.cap(id):
			row["name"].text = "%s%s  Lv.%d / %d" % [prefix, definition["name"], level, GameState.cap(id)]
			button.text = "한계 돌파 (포인트 1)"
			button.disabled = GameState.skill_points <= 0
			continue

		if is_action:
			row["name"].text = "%s%s  Lv.%d / %d" % [prefix, definition["name"], level, GameState.cap(id)]
		else:
			row["name"].text = "%s  Lv.%d" % [definition["name"], level]
		var price := Skills.cost(id, level)
		button.text = "강화 %s 코인" % Skills.fmt(price)
		button.disabled = GameState.coins < price


func _on_skill_pressed(id: String) -> void:
	var level := GameState.level(id)
	var done := false
	if not Skills.is_action(id):
		done = GameState.upgrade(id)
	elif level <= 0:
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
