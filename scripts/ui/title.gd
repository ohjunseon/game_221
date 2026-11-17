extends Control
## 시작 화면: 이어하기 · 새 게임 · 끝내기.
## 저장 슬롯은 하나라서, 저장이 있을 때 새 게임을 누르면 지워진다는 확인 팝업을 띄운다.
## 새 게임은 오프닝 카드를 보여 준 뒤 게임 화면으로 간다.

const MAIN_SCENE := "res://scenes/main.tscn"
const NAVY := Color(0.12, 0.15, 0.28)
const YELLOW := Color(1.0, 0.84, 0.32)
const MINT := Color(0.46, 0.94, 0.68)
const PINK := Color(1.0, 0.45, 0.5)

var continue_button: Button
var new_button: Button
var confirm: Control
var _info: Label


func _ready() -> void:
	SaveManager.in_game = false
	GameState.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var art := StoryArt.new()
	art.scene = "title"
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.05, 0.15, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	var title := _label("장난감 물류창고", 84, YELLOW)
	title.add_theme_color_override("font_outline_color", NAVY)
	title.add_theme_constant_override("outline_size", 18)
	column.add_child(title)
	column.add_child(_label("민준이의 1,000만 개 정리 꿈", 30, Color.WHITE))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	column.add_child(gap)

	var has_save := SaveManager.has_save()
	continue_button = _button("이어하기", MINT)
	continue_button.disabled = not has_save
	continue_button.pressed.connect(_on_continue)
	column.add_child(continue_button)
	_info = _label(_save_info() if has_save else "저장된 기록이 없어요", 18, Color(0.85, 0.88, 0.95))
	column.add_child(_info)
	new_button = _button("새 게임", YELLOW)
	new_button.pressed.connect(_on_new_game)
	column.add_child(new_button)
	var quit := _button("끝내기", Color(0.75, 0.78, 0.88))
	quit.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit)

	confirm = _build_confirm()
	add_child(confirm)
	(continue_button if has_save else new_button).grab_focus()


func _input(event: InputEvent) -> void:
	if confirm.visible and event.is_action_pressed("ui_cancel"):
		confirm.visible = false
		get_viewport().set_input_as_handled()


func _save_info() -> String:
	var data := SaveManager._read()
	return "정리한 장난감 %s개" % Skills.fmt(int(data.get("total_sorted", 0)))


func _on_continue() -> void:
	if SaveManager.load_game():
		_enter_game()
	else:
		continue_button.disabled = true
		_info.text = "저장을 불러오지 못했어요. 새 게임을 시작해 주세요"


func _on_new_game() -> void:
	if SaveManager.has_save():
		confirm.visible = true
	else:
		start_new_game()


## 저장을 지우고 오프닝을 본 뒤 게임으로 들어간다.
func start_new_game() -> void:
	confirm.visible = false
	SaveManager.new_game()
	var story := Story.play(self, Story.OPENING)
	story.finished.connect(_enter_game)


func _enter_game() -> void:
	GameState.menu_open = false
	get_tree().change_scene_to_file(MAIN_SCENE)


func _build_confirm() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := StyleBoxFlat.new()
	box.bg_color = NAVY
	box.set_corner_radius_all(24)
	box.set_border_width_all(5)
	box.border_color = PINK
	box.content_margin_left = 40.0
	box.content_margin_right = 40.0
	box.content_margin_top = 30.0
	box.content_margin_bottom = 30.0
	panel.add_theme_stylebox_override("panel", box)
	dim.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	column.add_child(_label("새 게임을 시작할까요?", 36, YELLOW))
	column.add_child(_label(
		"저장 칸은 하나뿐이에요.\n새로 시작하면 지금까지의 기록이 모두 지워지고\n되돌릴 수 없어요.", 24, Color.WHITE))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)
	var yes := _button("지우고 새로 시작", PINK)
	yes.pressed.connect(start_new_game)
	row.add_child(yes)
	var no := _button("취소", MINT)
	no.pressed.connect(func() -> void: dim.visible = false)
	row.add_child(no)
	return dim


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300, 64)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_color_override("font_color", NAVY)
	button.add_theme_color_override("font_hover_color", NAVY)
	button.add_theme_color_override("font_focus_color", NAVY)
	button.add_theme_color_override("font_pressed_color", NAVY)
	button.add_theme_color_override("font_disabled_color", Color(0.4, 0.42, 0.5))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(18)
		match state:
			"hover", "focus":
				style.bg_color = color.lightened(0.2)
				style.set_border_width_all(4)
				style.border_color = Color.WHITE
			"pressed":
				style.bg_color = color.darkened(0.15)
			"disabled":
				style.bg_color = Color(0.55, 0.57, 0.65, 0.7)
			_:
				style.bg_color = color
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(func() -> void: Sfx.play("pick"))
	return button
