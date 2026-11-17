extends CanvasLayer
## 정리 수·코인·퀘스트 카드, 진행 바, 조준 안내, 알림, 떠오르는 숫자,
## 화면 아래 스킬 슬롯 4칸(1~4 키), 스킬·업그레이드 메뉴(Tab).

const MESSAGE_SECONDS := 2.4
const MAX_FLYING_COINS := 12
const COIN_FLY_GAP_MSEC := 150
## 완료 축하 문구가 뜬 뒤 엔딩 카드가 나오기까지
const ENDING_DELAY := 2.5
const NAVY := Color(0.12, 0.15, 0.28)
const INK := Color(0.08, 0.1, 0.2)
const YELLOW := Color(1.0, 0.84, 0.32)
const MINT := Color(0.46, 0.94, 0.68)
const SKY := Color(0.44, 0.74, 1.0)
const PINK := Color(1.0, 0.58, 0.68)
const GRAY := Color(0.64, 0.68, 0.78)
const ICON_DIR := "res://assets/icons/"
## 액션 스킬별 아이콘(Kenney Game Icons)과 강조 색
const SLOT_ICONS := {"magnet": "target", "long_arm": "larger", "auto_sort": "gear", "jackpot": "star"}
const SLOT_COLORS := {"magnet": PINK, "long_arm": SKY, "auto_sort": MINT, "jackpot": YELLOW}

var _root: Control
var _sorted_label: Label
var _coin_label: Label
var _skill_label: Label
var _carry_label: Label
var _quest_label: Label
var _progress: ProgressBar
var _progress_label: Label
var _aim_label: Label
var _message_label: Label
var _message_timer: Timer
var _menu: PanelContainer
var _menu_title: Label
var _rows: Dictionary = {}
var _slot_labels: Array[Label] = []
var _slot_bars: Array[ProgressBar] = []
var _slot_icons: Array[TextureRect] = []
var _slot_styles: Array[StyleBoxFlat] = []
var _last_coins: int = 0
var _flying_coins: int = 0
var _last_fly_msec: int = 0
var _coin_style: StyleBoxFlat
var _coin_tween: Tween
var _pause: Control
var _pause_note: Label
var _ending_panel: Control


func _ready() -> void:
	if not InputMap.has_action("menu"):
		InputMap.add_action("menu")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_TAB
		InputMap.action_add_event("menu", key)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)

	_build_stats()
	_build_quest()
	_build_progress()

	var crosshair := Panel.new()
	var dot := _style(Color.WHITE, 6)
	dot.set_border_width_all(2)
	dot.border_color = INK
	crosshair.add_theme_stylebox_override("panel", dot)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -5.0
	crosshair.offset_top = -5.0
	crosshair.offset_right = 5.0
	crosshair.offset_bottom = 5.0
	_root.add_child(crosshair)

	_aim_label = _make_centered_label(20, 40.0)
	_message_label = _make_centered_label(32, 96.0)
	_message_label.add_theme_color_override("font_color", YELLOW)

	_message_timer = Timer.new()
	_message_timer.one_shot = true
	_message_timer.timeout.connect(func() -> void: _message_label.text = "")
	add_child(_message_timer)

	_build_slots()
	_build_menu()
	_pause = _build_choice_panel("잠깐 쉬기", "ESC: 닫기", [
		["계속하기", MINT, func() -> void: _set_pause_open(false)],
		["저장하기", SKY, _on_save_pressed],
		["저장하고 시작 화면으로", YELLOW, _go_to_title],
	])
	_ending_panel = _build_choice_panel("장난감 1,000만 개 정리 완료!", "정리 요원 민준, 수고했어요", [
		["계속 플레이", MINT, _close_ending_panel],
		["시작 화면으로", YELLOW, _go_to_title],
	])

	# 게임 화면에 들어오면 자동 저장을 켜고 바로 한 번 저장한다 (새 게임도 이어하기가 생긴다)
	SaveManager.in_game = true
	SaveManager.save_game()

	EventBus.toy_sorted.connect(func(_total: int) -> void: _refresh())
	EventBus.coins_changed.connect(_on_coins_changed)
	_last_coins = GameState.coins
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
	if _ending_panel.visible:
		return
	if _pause.visible:
		if event.is_action_pressed("ui_cancel"):
			_set_pause_open(false)
			get_viewport().set_input_as_handled()
		return
	if GameState.menu_open and not _menu.visible:
		return  # 오프닝·엔딩 카드가 떠 있음
	if event.is_action_pressed("menu"):
		_set_menu_open(not GameState.menu_open)
		get_viewport().set_input_as_handled()
	elif GameState.menu_open and event.is_action_pressed("ui_cancel"):
		_set_menu_open(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_set_pause_open(true)
		get_viewport().set_input_as_handled()


## ESC 메뉴: 계속하기 · 저장하기 · 저장하고 시작 화면으로
func _set_pause_open(open: bool) -> void:
	GameState.menu_open = open
	_pause.visible = open
	_pause_note.text = "ESC: 닫기"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _on_save_pressed() -> void:
	_pause_note.text = "저장했어요!" if SaveManager.save_game() else "저장하지 못했어요"
	Sfx.play("place")


func _go_to_title() -> void:
	SaveManager.save_game()
	SaveManager.in_game = false
	GameState.menu_open = false
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _close_ending_panel() -> void:
	_ending_panel.visible = false
	GameState.menu_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 가운데 패널에 제목, 버튼들, 아래 안내 문구를 둔다. 버튼은 [글자, 색, 함수].
func _build_choice_panel(title: String, note: String, buttons: Array) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var background := _style(NAVY, 24, 0.96)
	background.set_border_width_all(4)
	background.border_color = YELLOW
	background.content_margin_left = 40.0
	background.content_margin_right = 40.0
	background.content_margin_top = 28.0
	background.content_margin_bottom = 28.0
	panel.add_theme_stylebox_override("panel", background)
	dim.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var heading := _make_label(34)
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", YELLOW)
	column.add_child(heading)
	for spec: Array in buttons:
		var button := Button.new()
		button.text = spec[0]
		button.custom_minimum_size = Vector2(340, 58)
		button.add_theme_font_size_override("font_size", 26)
		var color: Color = spec[1]
		button.add_theme_stylebox_override("normal", _style(color.darkened(0.45), 16))
		button.add_theme_stylebox_override("hover", _style(color.darkened(0.2), 16))
		button.add_theme_stylebox_override("pressed", _style(color.darkened(0.6), 16))
		button.add_theme_stylebox_override("focus", _style(color.darkened(0.2), 16))
		button.pressed.connect(spec[2])
		column.add_child(button)
	var hint := _make_label(18)
	hint.text = note
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", GRAY)
	column.add_child(hint)
	if _pause_note == null:
		_pause_note = hint
	return dim


func _refresh() -> void:
	_sorted_label.text = "%s / %s" % [
		Skills.fmt(GameState.total_sorted), Skills.fmt(GameState.TOTAL_TOYS)
	]
	_coin_label.text = "코인 %s" % Skills.fmt(GameState.coins)
	_skill_label.text = "스킬 포인트 %d  (Tab)" % GameState.skill_points
	_skill_label.add_theme_color_override(
		"font_color", YELLOW if GameState.skill_points > 0 else Color.WHITE
	)
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		_carry_label.text = player.carry_text()
	_quest_label.text = QuestManager.text().trim_prefix("퀘스트: ")
	_progress.value = GameState.total_sorted
	var percent := 100.0 * GameState.total_sorted / GameState.TOTAL_TOYS
	_progress_label.text = ("%.3f%%" if percent < 1.0 else "%.1f%%") % percent
	if GameState.menu_open:
		_refresh_menu()


## 슬롯마다 잠김 / 준비 / 사용 중 / 쿨타임을 색과 막대로 보여 준다.
func _refresh_slots() -> void:
	for slot in Skills.ACTION_ORDER.size():
		var id := Skills.ACTION_ORDER[slot]
		var level := GameState.level(id)
		var label := _slot_labels[slot]
		var bar := _slot_bars[slot]
		var icon := _slot_icons[slot]
		var style := _slot_styles[slot]
		var color: Color = SLOT_COLORS[id]
		icon.texture = _icon(SLOT_ICONS[id] if level > 0 else "locked")
		style.bg_color = Color(NAVY, 0.86)
		if level <= 0:
			label.text = "잠김"
			label.modulate = GRAY
			icon.modulate = Color(GRAY, 0.7)
			style.border_color = Color(1.0, 1.0, 1.0, 0.15)
			bar.value = 0.0
		elif GameState.is_active(id):
			label.text = "사용 중 %.1f초" % GameState.active_left(id)
			label.modulate = color
			icon.modulate = color
			style.border_color = color
			style.bg_color = Color(color.darkened(0.7), 0.92)
			bar.value = GameState.active_left(id) / Skills.duration(id, level)
		elif GameState.cooldown_left(id) > 0.0:
			label.text = "쿨타임 %d초" % ceili(GameState.cooldown_left(id))
			label.modulate = GRAY
			icon.modulate = Color(GRAY, 0.7)
			style.border_color = Color(1.0, 1.0, 1.0, 0.2)
			bar.value = 1.0 - GameState.cooldown_left(id) / Skills.cooldown(id, level)
		else:
			label.text = "준비 완료"
			label.modulate = YELLOW
			icon.modulate = color
			style.border_color = YELLOW
			bar.value = 1.0


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_timer.start(MESSAGE_SECONDS)


func _show_popup(text: String) -> void:
	var label := _make_label(28)
	label.text = text
	label.add_theme_color_override("font_color", MINT)
	_root.add_child(label)
	var center := get_viewport().get_visible_rect().size / 2.0
	label.position = center + Vector2(randf_range(-90.0, 50.0), randf_range(-90.0, -50.0))
	label.scale = Vector2.ONE * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - 70.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


## 코인이 늘면 화면 가운데에서 동전이 튀어나와 코인 숫자로 날아간다.
func _on_coins_changed(coins: int) -> void:
	var gained := coins - _last_coins
	_last_coins = coins
	_refresh()
	var now := Time.get_ticks_msec()
	if gained <= 0 or _menu.visible or now - _last_fly_msec < COIN_FLY_GAP_MSEC:
		return
	_last_fly_msec = now
	if _coin_style == null:
		_coin_style = _style(YELLOW, 10)
		_coin_style.set_border_width_all(3)
		_coin_style.border_color = YELLOW.darkened(0.3)
	var center := get_viewport().get_visible_rect().size / 2.0
	var target := _coin_label.global_position + Vector2(-30.0, 2.0)
	for i in clampi(gained, 1, 6):
		if _flying_coins >= MAX_FLYING_COINS:
			return
		_flying_coins += 1
		var coin := Panel.new()
		coin.add_theme_stylebox_override("panel", _coin_style)
		coin.size = Vector2(20, 20)
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(coin)
		coin.position = center + Vector2(randf_range(-30.0, 30.0), randf_range(0.0, 40.0))
		var burst := coin.position + Vector2(randf_range(-80.0, 80.0), randf_range(-90.0, -20.0))
		var tween := coin.create_tween()
		tween.tween_interval(0.035 * i)
		tween.tween_property(coin, "position", burst, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(coin, "position", target, 0.34) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(_on_coin_arrived.bind(coin, i))


func _on_coin_arrived(coin: Control, index: int) -> void:
	coin.queue_free()
	_flying_coins -= 1
	Sfx.play("coin", 1.0 + 0.07 * index)
	# 코인 숫자가 통통 튄다
	if _coin_tween != null:
		_coin_tween.kill()
	_coin_label.pivot_offset = _coin_label.size / 2.0
	_coin_label.scale = Vector2.ONE * 1.25
	_coin_tween = create_tween()
	_coin_tween.tween_property(_coin_label, "scale", Vector2.ONE, 0.15)


## 엔딩: 축하 → 곰 반장 카드 → 거대 상자 낙하(3D) → 잠에서 깨는 카드 → 완료 패널
func _on_game_completed() -> void:
	_message_label.text = "장난감 1,000만 개 정리 완료! 축하합니다!"
	_message_timer.start(4.0)
	Sfx.play("fanfare")
	EventBus.shake_requested.emit(1.0)
	SaveManager.save_game()
	EventBus.ending_box_landed.connect(_on_ending_box_landed, CONNECT_ONE_SHOT)
	get_tree().create_timer(ENDING_DELAY).timeout.connect(func() -> void:
		_set_menu_open(false)
		_set_pause_open(false)
		var story := Story.play(self, Story.ENDING_BEFORE_BOX)
		story.finished.connect(func() -> void:
			# 상자가 떨어지는 동안은 조작하지 못하게 막는다
			GameState.menu_open = true
			EventBus.ending_box_requested.emit()
		)
	)


func _on_ending_box_landed() -> void:
	var story := Story.play(self, Story.ENDING_AFTER_BOX)
	story.finished.connect(func() -> void:
		GameState.menu_open = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_ending_panel.visible = true
	)


## 왼쪽 위 카드: 정리 수, 코인, 스킬 포인트, 손에 든 것
func _build_stats() -> void:
	var card := _card()
	card.position = Vector2(16, 14)
	_root.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	_sorted_label = _icon_row(box, "trophy", YELLOW, 26)
	_coin_label = _icon_row(box, "", YELLOW, 22)
	_skill_label = _icon_row(box, "star", MINT, 17)
	_carry_label = _make_label(17)
	box.add_child(_carry_label)


## 오른쪽 위 카드: 지금 퀘스트
func _build_quest() -> void:
	var card := _card()
	card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.offset_left = -16.0
	card.offset_right = -16.0
	card.offset_top = 14.0
	_root.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	var title := _make_label(15)
	title.text = "퀘스트"
	title.add_theme_color_override("font_color", MINT)
	box.add_child(title)
	_quest_label = _make_label(19)
	box.add_child(_quest_label)


func _build_progress() -> void:
	_progress = ProgressBar.new()
	_progress.max_value = GameState.TOTAL_TOYS
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(420, 28)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_progress.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_progress.offset_top = 16.0
	_root.add_child(_progress)
	_progress_label = _make_label(17)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_progress.add_child(_progress_label)


func _build_slots() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_bottom = -14.0
	_root.add_child(row)

	for slot in Skills.ACTION_ORDER.size():
		var id := Skills.ACTION_ORDER[slot]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(140, 0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := _style(NAVY, 16, 0.86)
		style.set_border_width_all(3)
		style.set_content_margin_all(8)
		panel.add_theme_stylebox_override("panel", style)
		row.add_child(panel)

		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(column)

		# 윗줄: 숫자키 배지 + 스킬 이름
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		column.add_child(head)
		var badge := PanelContainer.new()
		var badge_style := _style(YELLOW, 8)
		badge_style.set_content_margin_all(0)
		badge_style.content_margin_left = 8
		badge_style.content_margin_right = 8
		badge.add_theme_stylebox_override("panel", badge_style)
		head.add_child(badge)
		var key_label := Label.new()
		key_label.text = str(slot + 1)
		key_label.add_theme_font_size_override("font_size", 16)
		key_label.add_theme_color_override("font_color", INK)
		badge.add_child(key_label)
		var name_label := Label.new()
		name_label.text = Skills.DEFS[id]["name"]
		name_label.add_theme_font_size_override("font_size", 17)
		head.add_child(name_label)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(0, 42)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		column.add_child(icon)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		column.add_child(label)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(bar)

		_slot_labels.append(label)
		_slot_bars.append(bar)
		_slot_icons.append(icon)
		_slot_styles.append(style)


func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.visible = false
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	var background := _style(NAVY, 20, 0.97)
	background.set_border_width_all(3)
	background.border_color = Color(1.0, 1.0, 1.0, 0.3)
	background.set_content_margin_all(20)
	_menu.add_theme_stylebox_override("panel", background)
	_root.add_child(_menu)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_menu.add_child(column)

	_menu_title = Label.new()
	_menu_title.add_theme_font_size_override("font_size", 26)
	column.add_child(_menu_title)

	_add_section(column, "액션 스킬", "숫자키 1~4로 발동 · 스킬 포인트로 배운다", PINK)
	for id in Skills.ACTION_ORDER:
		_add_row(column, id)
	_add_section(column, "업그레이드", "항상 적용 · 코인으로 올린다", SKY)
	for id in Skills.UPGRADE_ORDER:
		_add_row(column, id)

	var hint := Label.new()
	hint.text = "선반 하나를 완성하면 스킬 포인트 1개를 얻습니다. 포인트로 액션 스킬을 배우거나 최대 레벨을 늘립니다."
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", GRAY)
	column.add_child(hint)


## 색 배지 제목 + 설명
func _add_section(column: VBoxContainer, title: String, text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	var chip := PanelContainer.new()
	var chip_style := _style(color, 10)
	chip_style.set_content_margin_all(2)
	chip_style.content_margin_left = 12
	chip_style.content_margin_right = 12
	chip.add_theme_stylebox_override("panel", chip_style)
	row.add_child(chip)
	var chip_label := Label.new()
	chip_label.text = title
	chip_label.add_theme_font_size_override("font_size", 17)
	chip_label.add_theme_color_override("font_color", INK)
	chip.add_child(chip_label)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", GRAY)
	row.add_child(label)


func _add_row(column: VBoxContainer, id: String) -> void:
	var panel := PanelContainer.new()
	var panel_style := _style(Color.WHITE, 12, 0.07)
	panel_style.set_content_margin_all(6)
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)
	column.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if Skills.is_action(id):
		icon.texture = _icon(SLOT_ICONS[id])
		icon.modulate = SLOT_COLORS[id]
	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(200, 0)
	name_label.add_theme_font_size_override("font_size", 19)
	var effect_label := Label.new()
	effect_label.custom_minimum_size = Vector2(470, 0)
	effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_label.add_theme_font_size_override("font_size", 14)
	var button := Button.new()
	button.custom_minimum_size = Vector2(190, 40)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_skill_pressed.bind(id))
	row.add_child(icon)
	row.add_child(name_label)
	row.add_child(effect_label)
	row.add_child(button)
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
			row["name"].text = "%s%s\n미습득" % [prefix, definition["name"]]
			row["effect"].text = "%s\n%s" % [definition["desc"], Skills.effect_text(id, 1)]
			button.text = "배우기 (포인트 1)"
			button.disabled = GameState.skill_points <= 0
			continue

		row["effect"].text = "%s\n지금: %s  →  다음: %s" % [
			definition["desc"], Skills.effect_text(id, level), Skills.effect_text(id, level + 1)
		]
		if is_action and level >= GameState.cap(id):
			row["name"].text = "%s%s\nLv.%d / %d" % [prefix, definition["name"], level, GameState.cap(id)]
			button.text = "한계 돌파 (포인트 1)"
			button.disabled = GameState.skill_points <= 0
			continue

		if is_action:
			row["name"].text = "%s%s\nLv.%d / %d" % [prefix, definition["name"], level, GameState.cap(id)]
		else:
			row["name"].text = "%s\nLv.%d" % [definition["name"], level]
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


## 버튼과 진행 막대의 공통 모양
func _make_theme() -> Theme:
	var theme := Theme.new()
	var states := {
		"normal": SKY.darkened(0.25), "hover": SKY.darkened(0.1),
		"pressed": SKY.darkened(0.4), "disabled": Color(0.3, 0.33, 0.46),
	}
	for state: String in states:
		var box := _style(states[state], 12)
		box.set_content_margin_all(6)
		box.border_width_bottom = 3
		box.border_color = (states[state] as Color).darkened(0.3)
		theme.set_stylebox(state, "Button", box)
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", GRAY)
	theme.set_font_size("font_size", "Button", 17)

	var background := _style(INK, 14, 0.75)
	background.set_content_margin_all(0)
	background.set_border_width_all(2)
	background.border_color = Color(1.0, 1.0, 1.0, 0.3)
	var fill := _style(MINT, 14)
	fill.set_content_margin_all(0)
	theme.set_stylebox("background", "ProgressBar", background)
	theme.set_stylebox("fill", "ProgressBar", fill)
	return theme


func _style(color: Color, radius: int, alpha: float = 1.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, alpha)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(10)
	return style


## 둥근 남색 카드
func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _style(NAVY, 16, 0.8)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 1.0, 1.0, 0.25)
	style.content_margin_left = 14
	style.content_margin_right = 14
	card.add_theme_stylebox_override("panel", style)
	return card


## 아이콘(없으면 동전 모양) + 글자 한 줄을 만들고 글자 Label을 돌려준다.
func _icon_row(parent: Control, icon_name: String, tint: Color, font_size: int) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	if icon_name == "":
		var coin := Panel.new()
		var coin_style := _style(tint, 11)
		coin_style.set_border_width_all(3)
		coin_style.border_color = tint.darkened(0.3)
		coin.add_theme_stylebox_override("panel", coin_style)
		coin.custom_minimum_size = Vector2(22, 22)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(coin)
	else:
		var icon := TextureRect.new()
		icon.texture = _icon(icon_name)
		icon.modulate = tint
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	var label := _make_label(font_size)
	row.add_child(label)
	return label


func _icon(icon_name: String) -> Texture2D:
	return load(ICON_DIR + icon_name + ".png")


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 6)
	return label


func _make_centered_label(font_size: int, offset_y: float) -> Label:
	var label := _make_label(font_size)
	label.add_theme_constant_override("outline_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.offset_top = offset_y
	label.offset_bottom = offset_y
	_root.add_child(label)
	return label
