extends CharacterBody3D

signal died

# ---- Tuning (yahan se feel badal sakte ho) ----
@export var max_speed: float = 5.5
@export var accel: float = 45.0              # jitna zyada, utna turant response
@export var look_sensitivity: float = 0.0055 # radian per pixel: right zone (540px) ka ek swipe ~170 degree
@export var base_torch_energy: float = 9.0

const JOY_RADIUS: float = 110.0   # joystick ka radius (1080 wide screen ke hisaab se)
const JOY_DEADZONE: float = 0.10
const LOOK_SLOP: float = 8.0       # itna hilne par hi camera ghumega (ungli ke chhote kampan ignore)
const LOOK_SMOOTH: float = 0.03    # camera smoothing (second)
const LOOK_Y_SCALE: float = 0.75   # upar-neeche thoda dheema, taaki camera bhatke nahi
const LOOK_PITCH_LIMIT: float = 75.0
const SWORD_RANGE: float = 3.0      # talwar kitni door tak lagti hai (meter)
const SWORD_COOLDOWN: float = 0.6
const MAX_HEALTH: float = 150.0      # tumhari energy (pehle 100 thi)
# Talwar ulti dikhe (mooth upar, phal neeche) to true kar do
const PLAYER_SWORD_FLIP: bool = false
const PLAYER_SWORD_INDEX: int = 0     # swords.glb me kaun si talwar (0..3), pasand na aaye to badlo
const FOV_BASE: float = 72.0         # landscape ke liye (chauda nazaara apne aap bante hai)
const SPRINT_MULT: float = 1.6
const FOV_SPRINT: float = 8.0

var camera: Camera3D
var spot_light: SpotLight3D
var game_manager: Node

# Touch state
var touch_screen_size: Vector2
var look_touch_index: int = -1
var look_start_pos: Vector2 = Vector2.ZERO
var look_started: bool = false
var look_pending: Vector2 = Vector2.ZERO
var look_sens_eff: float = 0.0055
var move_touch_index: int = -1
var move_joystick_center: Vector2 = Vector2.ZERO
var joy_default_center: Vector2 = Vector2.ZERO
var move_input: Vector2 = Vector2.ZERO   # raw, length 0..1

var is_torch_on: bool = true
var step_timer: float = 0.0
var step_player: AudioStreamPlayer
var step_stream: AudioStream
var step_is_loop: bool = false
var step_loop_active: bool = false
var _step_tween: Tween

var torch_btn: Button
var attack_btn: Button
var sprint_btn: Button
var sprint_on: bool = false
var step_interval: float = 0.42
var health_bar: ProgressBar
var damage_flash: ColorRect
var sword_pivot: Node3D
var sword_tween: Tween

# Ladai
var combat_enabled: bool = false   # Level 2 me chalu hoti hai
var health: float = MAX_HEALTH
var dead: bool = false
var attack_cooldown: float = 0.0
var swing_active: bool = false     # talwar ghoom rahi hai (takrav ke liye)
var joy_base: Panel
var joy_knob: Panel

func _ready() -> void:
	touch_screen_size = get_viewport().get_visible_rect().size
	look_sens_eff = look_sensitivity * 1080.0 / maxf(touch_screen_size.x, 1.0)
	joy_default_center = Vector2(260.0, touch_screen_size.y - 250.0)
	move_joystick_center = joy_default_center
	game_manager = get_node_or_null("../GameManager")
	add_to_group("player")

	# Tumhari footstep file (audio/footstep, koi bhi mp3/ogg/wav). Na mile to code wali awaaz.
	step_player = AudioStreamPlayer.new()
	add_child(step_player)
	if game_manager and game_manager.has_method("load_audio"):
		step_stream = game_manager.load_audio("res://audio/footstep")
	if step_stream:
		step_player.stream = step_stream
		step_player.volume_db = -2.0
		# 1.2 second se lambi file = chalne ki loop, chhoti = ek kadam
		step_is_loop = step_stream.get_length() > 1.2
		if step_is_loop:
			# mp3/ogg ko seedha loop par rakho, baaki (wav) khatam hone par dobara bajegi
			if step_stream is AudioStreamMP3 or step_stream is AudioStreamOggVorbis:
				step_stream.set("loop", true)
			step_player.finished.connect(_on_step_finished)

	# Collision
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = 1.8
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# Camera
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.7, 0)
	camera.near = 0.08
	camera.fov = FOV_BASE
	add_child(camera)

	# Searchlight torch
	spot_light = SpotLight3D.new()
	spot_light.light_color = Color(0.9, 0.95, 1.0)
	spot_light.light_energy = base_torch_energy
	spot_light.spot_range = 35.0
	spot_light.spot_angle = 35.0
	spot_light.shadow_enabled = true
	camera.add_child(spot_light)

	build_fp_sword()
	setup_touch_ui()

func play_sfx(sfx_name: String) -> void:
	if game_manager and game_manager.has_method("play_sfx"):
		game_manager.play_sfx(sfx_name)

# ---------------- UI ----------------
func setup_touch_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var w: float = touch_screen_size.x
	var h: float = touch_screen_size.y

	# Gol Torch button (neeche right, anguthe ki pahunch me)
	torch_btn = Button.new()
	torch_btn.custom_minimum_size = Vector2(120, 120)
	torch_btn.size = Vector2(120, 120)
	torch_btn.position = Vector2(w - 180, h - 520)
	torch_btn.focus_mode = Control.FOCUS_NONE
	torch_btn.add_theme_font_size_override("font_size", 22)
	torch_btn.pressed.connect(toggle_torch)
	canvas.add_child(torch_btn)
	update_torch_button()

	# Crosshair
	var dot := make_circle(10.0, Color(1, 1, 1, 0.5))
	dot.position = Vector2(w / 2.0 - 5.0, h / 2.0 - 5.0)
	canvas.add_child(dot)

	# Joystick: idle me halka ring dikhta hai, touch par wahin aa jata hai
	joy_base = make_circle(JOY_RADIUS * 2.0, Color(1, 1, 1, 0.10))
	joy_knob = make_circle(90.0, Color(1, 1, 1, 0.35))
	canvas.add_child(joy_base)
	canvas.add_child(joy_knob)

	# Talwar ka hamla button (bada, anguthe ki pahunch me)
	attack_btn = Button.new()
	attack_btn.custom_minimum_size = Vector2(150, 150)
	attack_btn.size = Vector2(150, 150)
	attack_btn.position = Vector2(w - 300, h - 330)
	attack_btn.focus_mode = Control.FOCUS_NONE
	attack_btn.text = "ATTACK"
	attack_btn.add_theme_font_size_override("font_size", 22)
	var atk_style := StyleBoxFlat.new()
	atk_style.bg_color = Color(0.8, 0.1, 0.1, 0.4)
	atk_style.border_color = Color(1.0, 0.4, 0.3, 0.9)
	atk_style.set_border_width_all(3)
	atk_style.set_corner_radius_all(75)
	for state in ["normal", "hover", "pressed", "focus"]:
		attack_btn.add_theme_stylebox_override(state, atk_style)
	attack_btn.button_down.connect(attack)
	attack_btn.visible = false
	canvas.add_child(attack_btn)

	# Daudne (RUN) ka button: dabao to tez, dobara dabao ya joystick chhodo to band
	sprint_btn = Button.new()
	sprint_btn.custom_minimum_size = Vector2(120, 120)
	sprint_btn.size = Vector2(120, 120)
	sprint_btn.position = Vector2(70, h - 560)
	sprint_btn.focus_mode = Control.FOCUS_NONE
	sprint_btn.add_theme_font_size_override("font_size", 24)
	sprint_btn.button_down.connect(toggle_sprint)
	canvas.add_child(sprint_btn)
	update_sprint_button()

	# Health bar (upar bayein)
	health_bar = ProgressBar.new()
	health_bar.min_value = 0.0
	health_bar.max_value = MAX_HEALTH
	health_bar.value = MAX_HEALTH
	health_bar.show_percentage = false
	health_bar.size = Vector2(360, 22)
	health_bar.position = Vector2(40, 40)
	var hb_bg := StyleBoxFlat.new()
	hb_bg.bg_color = Color(0, 0, 0, 0.5)
	hb_bg.set_corner_radius_all(11)
	var hb_fill := StyleBoxFlat.new()
	hb_fill.bg_color = Color(0.8, 0.1, 0.1, 0.95)
	hb_fill.set_corner_radius_all(11)
	health_bar.add_theme_stylebox_override("background", hb_bg)
	health_bar.add_theme_stylebox_override("fill", hb_fill)
	health_bar.visible = false
	canvas.add_child(health_bar)

	# Chot lagne par laal chamak
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.7, 0.0, 0.0, 0.0)
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(damage_flash)
	canvas.move_child(damage_flash, 0)

func make_circle(diameter: float, color: Color) -> Panel:
	var p := Panel.new()
	p.size = Vector2(diameter, diameter)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(diameter / 2.0))
	sb.border_color = Color(1, 1, 1, 0.4)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	return p

func update_torch_button() -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(60)
	sb.set_border_width_all(3)
	if is_torch_on:
		sb.bg_color = Color(1.0, 0.85, 0.3, 0.35)
		sb.border_color = Color(1.0, 0.9, 0.5, 0.9)
		torch_btn.text = "TORCH\nON"
	else:
		sb.bg_color = Color(0.1, 0.1, 0.1, 0.35)
		sb.border_color = Color(1, 1, 1, 0.4)
		torch_btn.text = "TORCH\nOFF"
	for state in ["normal", "hover", "pressed", "focus"]:
		torch_btn.add_theme_stylebox_override(state, sb)

func update_sprint_button() -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(60)
	sb.set_border_width_all(3)
	if sprint_on:
		sb.bg_color = Color(0.2, 0.6, 1.0, 0.45)
		sb.border_color = Color(0.6, 0.85, 1.0, 0.95)
		sprint_btn.text = "RUN\nON"
	else:
		sb.bg_color = Color(0.1, 0.1, 0.1, 0.35)
		sb.border_color = Color(1, 1, 1, 0.4)
		sprint_btn.text = "RUN"
	for state in ["normal", "hover", "pressed", "focus"]:
		sprint_btn.add_theme_stylebox_override(state, sb)

func toggle_sprint() -> void:
	sprint_on = not sprint_on
	update_sprint_button()

func toggle_torch() -> void:
	is_torch_on = !is_torch_on
	spot_light.visible = is_torch_on
	update_torch_button()
	play_sfx("click")

func _process(delta: float) -> void:
	var fov_target: float = FOV_BASE + (FOV_SPRINT if (sprint_on and move_input.length() > 0.3) else 0.0)
	camera.fov = lerpf(camera.fov, fov_target, clampf(8.0 * delta, 0.0, 1.0))
	# Camera smoothing: input thoda thoda karke lagta hai, jhatka nahi
	if look_pending != Vector2.ZERO:
		var k: float = 1.0 - exp(-delta / LOOK_SMOOTH)
		var step: Vector2 = look_pending * k
		look_pending -= step
		rotate_y(-step.x * look_sens_eff)
		camera.rotate_x(-step.y * look_sens_eff * LOOK_Y_SCALE)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-LOOK_PITCH_LIMIT), deg_to_rad(LOOK_PITCH_LIMIT))

	var active: bool = move_touch_index != -1
	var center: Vector2 = move_joystick_center if active else joy_default_center
	var knob_off: Vector2 = move_input * JOY_RADIUS if active else Vector2.ZERO
	joy_base.position = center - joy_base.size / 2.0
	joy_knob.position = center + knob_off - joy_knob.size / 2.0
	var a: float = 1.0 if active else 0.35
	joy_base.modulate.a = lerpf(joy_base.modulate.a, a, 14.0 * delta)
	joy_knob.modulate.a = joy_base.modulate.a

# ---------------- Input ----------------
# Zones (Free Fire / PUBG / COD Mobile jaisa):
#  - Left half ka neeche wala 70%  -> movement joystick (jahan ungli rakho wahin banta hai)
#  - Baaki sab (right half + left-upar) -> camera ghumana
#  - Torch button par touch -> sirf button
func is_move_zone(p: Vector2) -> bool:
	return p.x < touch_screen_size.x * 0.5 and p.y > touch_screen_size.y * 0.3

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if torch_btn.get_global_rect().has_point(event.position):
				return
			if attack_btn.visible and attack_btn.get_global_rect().has_point(event.position):
				return
			if sprint_btn.get_global_rect().has_point(event.position):
				return
			if is_move_zone(event.position):
				if move_touch_index == -1:
					move_touch_index = event.index
					move_joystick_center = event.position
					move_input = Vector2.ZERO
			elif look_touch_index == -1:
				look_touch_index = event.index
				look_start_pos = event.position
				look_started = false
				look_pending = Vector2.ZERO
		else:
			if event.index == look_touch_index:
				look_touch_index = -1
			elif event.index == move_touch_index:
				move_touch_index = -1
				move_input = Vector2.ZERO
				if sprint_on:
					sprint_on = false
					update_sprint_button()

	elif event is InputEventScreenDrag:
		if event.index == look_touch_index:
			# Ungli thodi hile tabhi camera chale (touch slop)
			if not look_started and event.position.distance_to(look_start_pos) >= LOOK_SLOP:
				look_started = true
			if look_started:
				var rel: Vector2 = event.relative
				# Bahut halka speed-acceleration (max 25%), taaki aim consistent rahe
				var amp: float = 1.0 + clampf((rel.length() - 15.0) / 80.0, 0.0, 0.25)
				look_pending += rel * amp

		elif event.index == move_touch_index:
			var offset: Vector2 = event.position - move_joystick_center
			# Ungli radius se bahar gayi to joystick uske saath khisakta hai
			if offset.length() > JOY_RADIUS:
				move_joystick_center += offset.normalized() * (offset.length() - JOY_RADIUS)
				offset = event.position - move_joystick_center
			move_input = offset / JOY_RADIUS

# ---------------- Movement ----------------
func _physics_process(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	step_interval = 0.42 / (SPRINT_MULT if sprint_on else 1.0)
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	var mag: float = move_input.length()
	var wish := Vector3.ZERO
	if mag > JOY_DEADZONE:
		var strength: float = clampf((mag - JOY_DEADZONE) / (1.0 - JOY_DEADZONE), 0.0, 1.0)
		strength = pow(strength, 0.8) # halka dhakka bhi achhi speed de
		var dir2: Vector2 = move_input.normalized() * strength
		var speed_now: float = max_speed * (SPRINT_MULT if sprint_on else 1.0)
		wish = transform.basis * Vector3(dir2.x, 0, dir2.y) * speed_now

	velocity.x = move_toward(velocity.x, wish.x, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z, accel * delta)
	move_and_slide()

	update_torch_energy()

	# Footsteps
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 1.0 and is_on_floor()
	if step_stream == null:
		if moving:
			step_timer += delta
			if step_timer >= step_interval:
				step_timer = 0.0
				play_sfx("step")
		else:
			step_timer = 0.3
	elif step_is_loop:
		if moving and not step_loop_active:
			step_loop_active = true
			start_step_loop()
		elif not moving and step_loop_active:
			step_loop_active = false
			stop_step_loop()
	else:
		if moving:
			step_timer += delta
			if step_timer >= step_interval:
				step_timer = 0.0
				step_player.play()
		else:
			step_timer = 0.3

# Lambi walking-loop: chalte hi dheere se shuru, rukte hi dheere se band (wahin se aage chalegi)
func start_step_loop() -> void:
	if _step_tween:
		_step_tween.kill()
	if not step_player.playing:
		step_player.volume_db = -30.0
		step_player.play()
	step_player.stream_paused = false
	_step_tween = create_tween()
	_step_tween.tween_property(step_player, "volume_db", -2.0, 0.12)

func stop_step_loop() -> void:
	if not step_player.playing or step_player.stream_paused:
		return
	if _step_tween:
		_step_tween.kill()
	_step_tween = create_tween()
	_step_tween.tween_property(step_player, "volume_db", -40.0, 0.15)
	_step_tween.tween_callback(pause_step_loop)

func pause_step_loop() -> void:
	step_player.stream_paused = true

func _on_step_finished() -> void:
	if step_loop_active:
		step_player.play()

# ---------------- Ladai (Level 2 se) ----------------
func set_combat_enabled(on: bool) -> void:
	combat_enabled = on
	attack_btn.visible = on
	health_bar.visible = on
	sword_pivot.visible = false   # talwar sirf vaar karte waqt dikhti hai

func play_any(base: String, fallback: String, volume_db: float = 0.0) -> void:
	if game_manager and game_manager.has_method("play_any"):
		game_manager.play_any(base, fallback, volume_db)

# Pahle-person talwar (camera ke saath)
func build_fp_sword() -> void:
	sword_pivot = Node3D.new()
	sword_pivot.position = Vector3(0.22, -0.34, -0.6)
	sword_pivot.rotation_degrees = Vector3(-30, 8, -18)
	sword_pivot.visible = false
	camera.add_child(sword_pivot)

	# Pehle swords.glb ki chuni hui talwar
	if game_manager and game_manager.has_method("make_pack_weapon"):
		var pack_sword: Node3D = game_manager.make_pack_weapon(PLAYER_SWORD_INDEX, 0.85, 1.0, PLAYER_SWORD_FLIP)
		if pack_sword:
			sword_pivot.add_child(pack_sword)
			return

	# Phir Quaternius (Katana > Sword > ShortSword), na mile to code wali
	if game_manager and game_manager.has_method("make_weapon"):
		var file_sword: Node3D = game_manager.make_weapon(["Katana", "Sword", "ShortSword"], 0.95)
		if file_sword:
			sword_pivot.add_child(file_sword)
			return

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.8, 0.84, 0.9)
	steel.roughness = 0.3
	steel.emission_enabled = true
	steel.emission = Color(0.3, 0.35, 0.42)
	steel.emission_energy_multiplier = 0.3
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.75, 0.55, 0.2)
	brass.roughness = 0.5

	sword_pivot.add_child(sword_piece(Vector3(0.06, 0.85, 0.015), Vector3(0, 0.55, 0), steel))   # phal
	sword_pivot.add_child(sword_piece(Vector3(0.28, 0.05, 0.05), Vector3(0, 0.12, 0), brass))    # guard
	sword_pivot.add_child(sword_piece(Vector3(0.045, 0.2, 0.045), Vector3(0, -0.02, 0), brass))  # mooth

func sword_piece(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = material
	mi.position = pos
	return mi

func swing_sword() -> void:
	if sword_tween:
		sword_tween.kill()
	sword_tween = create_tween()
	sword_tween.tween_property(sword_pivot, "rotation_degrees", Vector3(-95, -55, 75), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sword_tween.parallel().tween_property(sword_pivot, "position", Vector3(0.05, -0.3, -0.85), 0.12)
	sword_tween.tween_property(sword_pivot, "rotation_degrees", Vector3(-30, 8, -18), 0.3)
	sword_tween.parallel().tween_property(sword_pivot, "position", Vector3(0.22, -0.34, -0.6), 0.3)

func attack() -> void:
	if not combat_enabled or dead or attack_cooldown > 0.0:
		return
	attack_cooldown = SWORD_COOLDOWN
	swing_active = true
	sword_pivot.visible = true
	swing_sword()
	play_any("res://audio/sword_swing", "slash", -2.0)
	await get_tree().create_timer(0.14).timeout
	apply_sword_hits()
	await get_tree().create_timer(0.22).timeout
	swing_active = false
	await get_tree().create_timer(0.25).timeout
	if not swing_active and attack_cooldown <= 0.2:
		sword_pivot.visible = false

func apply_sword_hits() -> void:
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var hit_any: bool = false
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.has_method("is_dead") and e.is_dead():
			continue
		var d: Vector3 = e.global_position - global_position
		d.y = 0.0
		var dist: float = d.length()
		if dist > 0.01 and dist <= SWORD_RANGE and fwd.dot(d / dist) > 0.35:
			var res: int = e.take_hit(1, global_position)
			if res == 0:
				hit_any = true
	if hit_any:
		play_any("res://audio/sword_hit", "hit")

# Takrav dikhao: talwar beech me aakar dushman ki talwar se takrati hai, camera hilta hai
func clash_visual() -> void:
	if sword_tween:
		sword_tween.kill()
	sword_pivot.visible = true
	sword_tween = create_tween()
	sword_tween.tween_property(sword_pivot, "rotation_degrees", Vector3(-70, 10, 20), 0.05)
	sword_tween.parallel().tween_property(sword_pivot, "position", Vector3(0.0, -0.2, -0.75), 0.05)
	sword_tween.tween_property(sword_pivot, "position", Vector3(0.03, -0.22, -0.72), 0.04)
	sword_tween.tween_property(sword_pivot, "rotation_degrees", Vector3(-30, 8, -18), 0.25)
	sword_tween.parallel().tween_property(sword_pivot, "position", Vector3(0.22, -0.34, -0.6), 0.25)
	shake_camera(0.05, 0.22)
	await get_tree().create_timer(0.55).timeout
	if not swing_active and attack_cooldown <= 0.3:
		sword_pivot.visible = false

func shake_camera(strength: float, duration: float) -> void:
	var t := create_tween()
	var steps: int = 5
	for i in range(steps):
		var s: float = strength * (1.0 - float(i) / float(steps))
		t.tween_property(camera, "h_offset", randf_range(-s, s), duration / steps)
		t.parallel().tween_property(camera, "v_offset", randf_range(-s, s), duration / steps)
	t.tween_property(camera, "h_offset", 0.0, 0.03)
	t.parallel().tween_property(camera, "v_offset", 0.0, 0.03)

func is_swinging() -> bool:
	return swing_active

# Takrav ya dhaal se tumhe peeche dhakelna
func nudge(dir: Vector3, strength: float = 4.0) -> void:
	velocity += dir * strength

# ---------------- Save / Resume ----------------
func get_save_data() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"pitch": camera.rotation.x,
		"health": health,
		"torch": is_torch_on
	}

func apply_save_data(d: Dictionary) -> void:
	var pos: Array = d.get("pos", [])
	if pos.size() == 3:
		global_position = Vector3(float(pos[0]), float(pos[1]) + 0.3, float(pos[2]))
	rotation.y = float(d.get("yaw", 0.0))
	camera.rotation.x = float(d.get("pitch", 0.0))
	health = clampf(float(d.get("health", MAX_HEALTH)), 1.0, MAX_HEALTH)
	health_bar.value = health
	is_torch_on = bool(d.get("torch", true))
	spot_light.visible = is_torch_on
	update_torch_button()
	velocity = Vector3.ZERO
	dead = false

func take_damage(amount: float, from_pos: Vector3) -> void:
	if dead or not combat_enabled:
		return
	health = maxf(0.0, health - amount)
	health_bar.value = health
	damage_flash.color = Color(0.7, 0.0, 0.0, 0.5)
	create_tween().tween_property(damage_flash, "color:a", 0.0, 0.6)
	var away: Vector3 = global_position - from_pos
	away.y = 0.0
	if away.length() > 0.01:
		velocity += away.normalized() * 5.0
	if health <= 0.0:
		dead = true
		died.emit()

func respawn_at(pos: Vector3) -> void:
	dead = false
	health = MAX_HEALTH
	health_bar.value = MAX_HEALTH
	global_position = pos
	velocity = Vector3.ZERO

# Deewar ke bilkul paas torch ki roshni dheemi, taaki screen safed na ho jaye
func update_torch_energy() -> void:
	if not is_torch_on:
		return
	var origin: Vector3 = camera.global_position
	var fwd: Vector3 = -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 4.0)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var f: float = 1.0
	if not hit.is_empty():
		var d: float = origin.distance_to(hit["position"])
		f = clampf((d - 0.4) / 3.5, 0.12, 1.0)
	spot_light.light_energy = lerpf(spot_light.light_energy, base_torch_energy * f, 0.3)
