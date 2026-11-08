extends Node3D

const GOLD: Color = Color(0.93, 0.78, 0.38)
const GOLD_SOFT: Color = Color(0.98, 0.86, 0.50)
const CRIMSON: Color = Color(0.58, 0.05, 0.08)

var scroll_ui: Control
var dim: ColorRect
var card: MarginContainer
var body_label: Label
var voice_player: AudioStreamPlayer

var is_scroll_open: bool = false
var _scroll_token: int = 0
var _scroll_tween: Tween
var _type_tween: Tween

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

# ---------------- Royal invitation scroll (laal kagaz, sunehri border) ----------------
func setup_magical_scroll_ui() -> void:
	voice_player = AudioStreamPlayer.new()
	add_child(voice_player)

	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	scroll_ui = Control.new()
	scroll_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_ui.visible = false
	canvas.add_child(scroll_ui)

	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_ui.add_child(dim)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans Devanagari", "Noto Sans", "sans-serif"])

	# Card: andar ka hissa (margin) text ke liye, border aur rods paint_card() banata hai
	card = MarginContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(900, 720)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_constant_override("margin_left", 110)
	card.add_theme_constant_override("margin_right", 110)
	card.add_theme_constant_override("margin_top", 115)
	card.add_theme_constant_override("margin_bottom", 115)
	card.draw.connect(paint_card)
	card.resized.connect(on_card_resized)
	scroll_ui.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	var subtitle := make_label("— हातिम की पहेली —", font, 26, Color(GOLD.r, GOLD.g, GOLD.b, 0.8))
	box.add_child(subtitle)

	var title := make_label("शाही आमंत्रण", font, 54, GOLD)
	box.add_child(title)

	var divider := Control.new()
	divider.custom_minimum_size = Vector2(0, 30)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.draw.connect(paint_divider.bind(divider))
	box.add_child(divider)

	body_label = make_label("", font, 36, GOLD_SOFT)
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_label.custom_minimum_size = Vector2(680, 200)
	body_label.add_theme_constant_override("line_spacing", 12)
	box.add_child(body_label)

	var btn := Button.new()
	btn.text = "ठीक है"
	btn.custom_minimum_size = Vector2(260, 76)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 32)
	for c in ["font_color", "font_pressed_color", "font_hover_color"]:
		btn.add_theme_color_override(c, Color(0.35, 0.03, 0.05))
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = GOLD if state != "pressed" else Color(0.75, 0.58, 0.22)
		sb.set_corner_radius_all(38)
		btn.add_theme_stylebox_override(state, sb)
	btn.pressed.connect(close_scroll)
	box.add_child(btn)

func make_label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func on_card_resized() -> void:
	card.pivot_offset = card.size / 2.0
	card.queue_redraw()

# Laal kagaz + sunehri border + lakdi ke rods (sunehri topi ke saath)
func paint_card() -> void:
	var w: float = card.size.x
	var h: float = card.size.y
	var rod: float = 36.0
	var paper := Rect2(Vector2(34.0, rod * 0.6), Vector2(w - 68.0, h - rod * 1.2))

	# Kagaz + beech me halki chamak
	card.draw_rect(paper, CRIMSON)
	for i in range(8):
		var glow := paper.grow(-(20.0 + i * 22.0))
		if glow.size.x <= 0.0 or glow.size.y <= 0.0:
			break
		card.draw_rect(glow, Color(1.0, 0.25, 0.2, 0.035))

	# Dohri sunehri border
	card.draw_rect(paper.grow(-12.0), GOLD, false, 3.0)
	card.draw_rect(paper.grow(-36.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.8), false, 1.5)

	# Border ke beech ki naqqashi (heere ki lady)
	var band := paper.grow(-24.0)
	var tr := Vector2(band.end.x, band.position.y)
	var bl := Vector2(band.position.x, band.end.y)
	draw_diamond_row(band.position, tr)
	draw_diamond_row(bl, band.end)
	draw_diamond_row(band.position, bl)
	draw_diamond_row(tr, band.end)
	for c in [band.position, tr, bl, band.end]:
		card.draw_circle(c, 14.0, CRIMSON)
		card.draw_arc(c, 14.0, 0.0, TAU, 24, GOLD, 3.0)
		card.draw_circle(c, 5.0, GOLD)

	# Upar aur neeche ke rods
	for y in [rod * 0.5, h - rod * 0.5]:
		card.draw_rect(Rect2(Vector2(40.0, y - 14.0), Vector2(w - 80.0, 28.0)), Color(0.30, 0.04, 0.06))
		card.draw_rect(Rect2(Vector2(40.0, y - 14.0), Vector2(w - 80.0, 6.0)), Color(1, 1, 1, 0.12))
		for x in [26.0, w - 26.0]:
			card.draw_circle(Vector2(x, y), 22.0, GOLD)
			card.draw_circle(Vector2(x, y), 13.0, Color(0.75, 0.55, 0.2))
			card.draw_circle(Vector2(x - 4.0, y - 4.0), 5.0, Color(1, 0.95, 0.7, 0.6))

func draw_diamond_row(from: Vector2, to: Vector2) -> void:
	var dist: float = from.distance_to(to)
	var dir: Vector2 = (to - from).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var count: int = int(dist / 26.0)
	for i in range(1, count):
		var c: Vector2 = from + dir * (dist * i / count)
		var s: float = 6.0
		card.draw_colored_polygon(PackedVector2Array([c + dir * s, c + perp * s * 0.8, c - dir * s, c - perp * s * 0.8]), GOLD)

func paint_divider(ctrl: Control) -> void:
	var cw: float = ctrl.size.x
	var cy: float = ctrl.size.y / 2.0
	ctrl.draw_line(Vector2(0, cy), Vector2(cw * 0.5 - 26.0, cy), GOLD, 2.0)
	ctrl.draw_line(Vector2(cw * 0.5 + 26.0, cy), Vector2(cw, cy), GOLD, 2.0)
	ctrl.draw_colored_polygon(PackedVector2Array([
		Vector2(cw * 0.5, cy - 10.0), Vector2(cw * 0.5 + 15.0, cy),
		Vector2(cw * 0.5, cy + 10.0), Vector2(cw * 0.5 - 15.0, cy)]), GOLD)

# ---------------- Voice (ElevenLabs wali file, koi bhi mp3/ogg/wav) ----------------
func play_voice(path: String) -> float:
	voice_player.stop()
	if path == "":
		return -1.0
	var stream: AudioStream = null
	var gm := get_node_or_null("../GameManager")
	if gm and gm.has_method("load_audio"):
		stream = gm.load_audio(path)
	if stream:
		voice_player.stream = stream
		voice_player.volume_db = 2.0
		voice_player.play()
		return stream.get_length()
	return -1.0

func play_game_sfx(sfx_name: String) -> void:
	var gm := get_node_or_null("../GameManager")
	if gm and gm.has_method("play_sfx"):
		gm.play_sfx(sfx_name)

# ---------------- Show / close ----------------
func trigger_hatim_scroll(puzzle_text: String, voice_path: String = "") -> void:
	_scroll_token += 1
	var token := _scroll_token

	body_label.text = puzzle_text
	body_label.visible_ratio = 0.0
	scroll_ui.visible = true
	play_game_sfx("scroll")

	if not is_scroll_open:
		is_scroll_open = true
		card.modulate.a = 0.0
		card.scale = Vector2(1.0, 0.08)  # scroll upar se neeche khulta hai
		dim.modulate.a = 0.0

	var voice_len: float = play_voice(voice_path)

	if _scroll_tween:
		_scroll_tween.kill()
	_scroll_tween = create_tween().set_parallel(true)
	_scroll_tween.tween_property(card, "modulate:a", 1.0, 0.3)
	_scroll_tween.tween_property(card, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_property(dim, "modulate:a", 1.0, 0.3)

	# Awaaz ke saath saath text akshar-akshar sunehri likhawat me ubharta hai
	var type_time: float = voice_len * 0.85 if voice_len > 0.0 else clampf(puzzle_text.length() * 0.05, 2.0, 8.0)
	if _type_tween:
		_type_tween.kill()
	_type_tween = create_tween()
	_type_tween.tween_property(body_label, "visible_ratio", 1.0, type_time).set_delay(0.6)

	var duration: float = voice_len + 1.5 if voice_len > 0.0 else maxf(type_time + 3.0, 5.0)
	await get_tree().create_timer(duration).timeout
	if token != _scroll_token:
		return
	close_scroll()

# "ठीक है" dabane par sirf card band hota hai, awaaz poori bajti hai
func close_scroll() -> void:
	_scroll_token += 1
	var token := _scroll_token

	if _scroll_tween:
		_scroll_tween.kill()
	_scroll_tween = create_tween().set_parallel(true)
	_scroll_tween.tween_property(card, "modulate:a", 0.0, 0.25)
	_scroll_tween.tween_property(card, "scale", Vector2(1.0, 0.08), 0.3)
	_scroll_tween.tween_property(dim, "modulate:a", 0.0, 0.25)
	await _scroll_tween.finished
	if token != _scroll_token:
		return

	scroll_ui.visible = false
	is_scroll_open = false
