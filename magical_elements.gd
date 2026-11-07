extends Node3D

const GOLD: Color = Color(0.88, 0.72, 0.30)
const CREAM: Color = Color(0.96, 0.91, 0.78)

var scroll_ui: Control
var dim: ColorRect
var card: PanelContainer
var body_label: Label
var is_scroll_open: bool = false
var _scroll_token: int = 0
var _scroll_tween: Tween

var tts_voice: String = ""
var tts_checked: bool = false
var tts_speaking: bool = false

func _ready() -> void:
	generate_codex_mountains()
	setup_magical_scroll_ui()

# ---------------- Codex mountains ----------------
func generate_codex_mountains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.14, 0.20)
	mat.roughness = 0.9

	for i in range(8):
		var box := BoxMesh.new()
		box.size = Vector3(15, rng.randf_range(25, 40), 15)

		var mountain := MeshInstance3D.new()
		mountain.mesh = box
		mountain.material_override = mat

		var angle: float = i * (PI / 4.0)
		var distance := 60.0
		mountain.position = Vector3(cos(angle) * distance, box.size.y / 2.0, sin(angle) * distance)
		mountain.rotation.y = atan2(-cos(angle), -sin(angle))
		add_child(mountain)

		var label_3d := Label3D.new()
		label_3d.text = "CODEX"
		label_3d.font_size = 64
		label_3d.modulate = Color(0.0, 1.0, 0.6)
		label_3d.pixel_size = 0.05
		label_3d.position = Vector3(0, -box.size.y / 2.0 + 8.0, 7.6)
		mountain.add_child(label_3d)

# ---------------- Royal invitation card ----------------
func setup_magical_scroll_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	scroll_ui = Control.new()
	scroll_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_ui.visible = false
	canvas.add_child(scroll_ui)

	# Peeche halka andhera, taaki card par dhyan jaye
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_ui.add_child(dim)

	# Hindi ke liye system font
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans Devanagari", "Noto Sans", "sans-serif"])

	# Card: dark mahogany + sunehri border
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.10, 0.07, 0.05, 0.97)
	card_style.border_color = GOLD
	card_style.set_border_width_all(4)
	card_style.set_corner_radius_all(28)
	card_style.content_margin_left = 52
	card_style.content_margin_right = 52
	card_style.content_margin_top = 44
	card_style.content_margin_bottom = 40
	card_style.shadow_color = Color(0, 0, 0, 0.7)
	card_style.shadow_size = 40

	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", card_style)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(920, 0)
	card.resized.connect(func(): card.pivot_offset = card.size / 2.0)
	scroll_ui.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	card.add_child(box)

	var subtitle := Label.new()
	subtitle.text = "— हातिम की पहेली —"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", font)
	subtitle.add_theme_font_size_override("font_size", 26)
	subtitle.add_theme_color_override("font_color", Color(GOLD.r, GOLD.g, GOLD.b, 0.75))
	box.add_child(subtitle)

	var title := Label.new()
	title.text = "शाही आमंत्रण"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)

	var divider := ColorRect.new()
	divider.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.8)
	divider.custom_minimum_size = Vector2(0, 3)
	box.add_child(divider)

	body_label = Label.new()
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(800, 200)
	body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_label.add_theme_font_override("font", font)
	body_label.add_theme_font_size_override("font_size", 34)
	body_label.add_theme_constant_override("line_spacing", 12)
	body_label.add_theme_color_override("font_color", CREAM)
	box.add_child(body_label)

	var btn := Button.new()
	btn.text = "ठीक है"
	btn.custom_minimum_size = Vector2(280, 80)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 32)
	btn.add_theme_color_override("font_color", Color(0.15, 0.08, 0.02))
	btn.add_theme_color_override("font_pressed_color", Color(0.15, 0.08, 0.02))
	btn.add_theme_color_override("font_hover_color", Color(0.15, 0.08, 0.02))
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = GOLD if state != "pressed" else Color(0.7, 0.55, 0.2)
		sb.set_corner_radius_all(40)
		btn.add_theme_stylebox_override(state, sb)
	btn.pressed.connect(close_scroll)
	box.add_child(btn)

# ---------------- Mysterious voice ----------------
func find_tts_voice() -> String:
	if tts_checked:
		return tts_voice
	tts_checked = true
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		print("TTS: feature available nahi")
		return ""
	var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("hi")
	print("TTS: Hindi voices mili = ", voices.size())
	if not voices.is_empty():
		tts_voice = voices[0]
	return tts_voice

func speak_mysterious(text: String) -> void:
	var voice: String = find_tts_voice()
	if voice == "":
		# Hindi voice nahi mili: fusfusahat wali awaaz bajao, chup nahi
		play_game_sfx("whisper")
		return
	tts_speaking = true
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, voice, 90, 0.6, 0.85)

func play_game_sfx(sfx_name: String) -> void:
	var gm := get_node_or_null("../GameManager")
	if gm and gm.has_method("play_sfx"):
		gm.play_sfx(sfx_name)

# ---------------- Show / close ----------------
func trigger_hatim_scroll(puzzle_text: String) -> void:
	_scroll_token += 1
	var token := _scroll_token

	body_label.text = puzzle_text
	scroll_ui.visible = true
	play_game_sfx("scroll")

	if not is_scroll_open:
		is_scroll_open = true
		card.modulate.a = 0.0
		card.scale = Vector2(0.88, 0.88)
		dim.modulate.a = 0.0

	if _scroll_tween:
		_scroll_tween.kill()
	_scroll_tween = create_tween().set_parallel(true)
	_scroll_tween.tween_property(card, "modulate:a", 1.0, 0.35)
	_scroll_tween.tween_property(card, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_property(dim, "modulate:a", 1.0, 0.35)

	speak_mysterious(puzzle_text)

	# Awaaz poori hone tak card khula rahe (player "ठीक है" dabakar jaldi band kar sakta hai)
	var duration: float = clampf(puzzle_text.length() * 0.16, 6.0, 32.0)
	await get_tree().create_timer(duration).timeout
	if token != _scroll_token:
		return
	close_scroll()

func close_scroll() -> void:
	_scroll_token += 1
	var token := _scroll_token

	if tts_speaking:
		DisplayServer.tts_stop()
		tts_speaking = false

	if _scroll_tween:
		_scroll_tween.kill()
	_scroll_tween = create_tween().set_parallel(true)
	_scroll_tween.tween_property(card, "modulate:a", 0.0, 0.25)
	_scroll_tween.tween_property(card, "scale", Vector2(0.92, 0.92), 0.25)
	_scroll_tween.tween_property(dim, "modulate:a", 0.0, 0.25)
	await _scroll_tween.finished
	if token != _scroll_token:
		return

	scroll_ui.visible = false
	is_scroll_open = false
