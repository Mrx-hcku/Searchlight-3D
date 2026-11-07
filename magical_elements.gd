extends Node3D

var scroll_ui: Control
var scroll_label: Label
var is_scroll_open: bool = false

func _ready() -> void:
	generate_codex_mountains()
	setup_magical_scroll_ui()

func generate_codex_mountains() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for i in range(8):
		var mountain = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(15, rng.randf_range(25, 40), 15)
		mountain.mesh = box
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.04, 0.04, 0.06)
		mat.roughness = 0.9
		mountain.material_override = mat
		
		var angle = i * (PI / 4)
		var distance = 60.0
		mountain.position = Vector3(cos(angle) * distance, box.size.y / 2, sin(angle) * distance)
		add_child(mountain)
		
		var label_3d = Label3D.new()
		label_3d.text = "CODEX"
		label_3d.font_size = 64
		label_3d.modulate = Color(0.0, 1.0, 0.6)
		label_3d.pixel_size = 0.05
		label_3d.position = Vector3(0, 0, 7.6)
		mountain.add_child(label_3d)

func setup_magical_scroll_ui() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	scroll_ui = Control.new()
	scroll_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll_ui.visible = false
	canvas.add_child(scroll_ui)
	
	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.1, 0.05, 0.9)
	bg.custom_minimum_size = Vector2(700, 400)
	bg.set_anchors_preset(Control.PRESET_CENTER)
	bg.position -= Vector2(350, 200)
	scroll_ui.add_child(bg)
	
	scroll_label = Label.new()
	scroll_label.text = ""
	scroll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scroll_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(scroll_label)

func trigger_hatim_scroll(puzzle_text: String) -> void:
	if is_scroll_open: return
	is_scroll_open = true
	
	scroll_label.text = "📜 [ शाही आमंत्रण / पहेली ] 📜\n\n" + puzzle_text
	scroll_ui.visible = true
	
	scroll_ui.scale = Vector2(0.1, 0.1)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(scroll_ui, "scale", Vector2(1, 1), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	print("Audio Manager: Reading puzzle aloud -> ", puzzle_text)
	
	var close_timer = get_tree().create_timer(8.0)
	close_timer.timeout.connect(func():
		var close_tween = create_tween()
		close_tween.tween_property(scroll_ui, "scale", Vector2(0.1, 0.1), 0.4)
		await close_tween.finished
		scroll_ui.visible = false
		is_scroll_open = false
	)
