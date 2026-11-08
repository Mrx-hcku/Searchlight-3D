extends CharacterBody3D

# ---- Tuning (yahan se feel badal sakte ho) ----
@export var max_speed: float = 5.5
@export var accel: float = 45.0              # jitna zyada, utna turant response
@export var look_sensitivity: float = 0.0055 # radian per pixel: right zone (540px) ka ek swipe ~170 degree
@export var base_torch_energy: float = 14.0

const JOY_RADIUS: float = 110.0   # joystick ka radius (1080 wide screen ke hisaab se)
const JOY_DEADZONE: float = 0.10
const LOOK_SLOP: float = 8.0       # itna hilne par hi camera ghumega (ungli ke chhote kampan ignore)
const LOOK_SMOOTH: float = 0.03    # camera smoothing (second)
const LOOK_Y_SCALE: float = 0.75   # upar-neeche thoda dheema, taaki camera bhatke nahi
const LOOK_PITCH_LIMIT: float = 75.0

var camera: Camera3D
var spot_light: SpotLight3D
var game_manager: Node

# Touch state
var touch_screen_size: Vector2
var look_touch_index: int = -1
var look_start_pos: Vector2 = Vector2.ZERO
var look_started: bool = false
var look_pending: Vector2 = Vector2.ZERO
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
var joy_base: Panel
var joy_knob: Panel

func _ready() -> void:
	touch_screen_size = get_viewport().get_visible_rect().size
	joy_default_center = Vector2(240, touch_screen_size.y - 430)
	move_joystick_center = joy_default_center
	game_manager = get_node_or_null("../GameManager")

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
	add_child(camera)

	# Searchlight torch
	spot_light = SpotLight3D.new()
	spot_light.light_color = Color(0.9, 0.95, 1.0)
	spot_light.light_energy = base_torch_energy
	spot_light.spot_range = 35.0
	spot_light.spot_angle = 35.0
	spot_light.shadow_enabled = true
	camera.add_child(spot_light)

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
	torch_btn.position = Vector2(w - 170, h - 400)
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

func toggle_torch() -> void:
	is_torch_on = !is_torch_on
	spot_light.visible = is_torch_on
	update_torch_button()
	play_sfx("click")

func _process(delta: float) -> void:
	# Camera smoothing: input thoda thoda karke lagta hai, jhatka nahi
	if look_pending != Vector2.ZERO:
		var k: float = 1.0 - exp(-delta / LOOK_SMOOTH)
		var step: Vector2 = look_pending * k
		look_pending -= step
		rotate_y(-step.x * look_sensitivity)
		camera.rotate_x(-step.y * look_sensitivity * LOOK_Y_SCALE)
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
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	var mag: float = move_input.length()
	var wish := Vector3.ZERO
	if mag > JOY_DEADZONE:
		var strength: float = clampf((mag - JOY_DEADZONE) / (1.0 - JOY_DEADZONE), 0.0, 1.0)
		strength = pow(strength, 0.8) # halka dhakka bhi achhi speed de
		var dir2: Vector2 = move_input.normalized() * strength
		wish = transform.basis * Vector3(dir2.x, 0, dir2.y) * max_speed

	velocity.x = move_toward(velocity.x, wish.x, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z, accel * delta)
	move_and_slide()

	update_torch_energy()

	# Footsteps
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 1.0 and is_on_floor()
	if step_stream == null:
		if moving:
			step_timer += delta
			if step_timer >= 0.42:
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
			if step_timer >= 0.42:
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
		f = clampf((d - 0.4) / 2.0, 0.1, 1.0)
	spot_light.light_energy = lerpf(spot_light.light_energy, base_torch_energy * f, 0.3)
