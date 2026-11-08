extends CharacterBody3D
# Yoddha: talwar wala dushman. Level 2 me 6 baar copy hota hai, aage ke levels me bhi isi script se naye yoddha bana sakte ho.
# models/warrior.glb (ya .gltf / .fbx) ho to wahi dikhega, warna code se bana placeholder yoddha.

signal died(warrior)

enum State { GUARD, CHASE, WINDUP, STRIKE, RECOVER, HURT, DEAD }

const MODEL_YAW: float = 180.0        # zyadatar models +Z dekhte hain. Ulta dikhe to 0.0 kar do
const MODEL_HEIGHT: float = 1.9
const ADD_SWORD_TO_MODEL: bool = true # model ke paas apni talwar ho to false kar do

var max_health: int = 4
var health: int = 4
var move_speed: float = 3.2
var aggro_range: float = 24.0
var attack_range: float = 2.2
var windup_time: float = 0.55
var strike_time: float = 0.25
var recover_time: float = 0.9
var damage: float = 12.0

var player
var game_manager: Node
var home: Vector3 = Vector3.ZERO

var state: State = State.GUARD
var state_time: float = 0.0
var hit_done: bool = false

var visual: Node3D
var anim_player: AnimationPlayer
var anims: Dictionary = {}
var using_model: bool = false
var current_anim: String = ""

var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var walk_phase: float = 0.0

static var splat_texture: GradientTexture2D = null

func _ready() -> void:
	add_to_group("enemy")
	health = max_health

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	visual = Node3D.new()
	add_child(visual)
	using_model = try_model()
	if not using_model:
		build_placeholder()
	play_anim("idle")

func is_dead() -> bool:
	return state == State.DEAD

func sfx(base: String, fallback: String, volume_db: float = 0.0) -> void:
	if game_manager and game_manager.has_method("play_any"):
		game_manager.play_any(base, fallback, volume_db)

# ---------------- Model (optional) ----------------
func try_model() -> bool:
	var path: String = ""
	for ext in ["glb", "gltf", "fbx", "GLB", "GLTF", "FBX"]:
		var p: String = "res://models/warrior." + ext
		if ResourceLoader.exists(p):
			path = p
			break
	if path == "":
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	if model == null:
		return false

	var holder := Node3D.new()
	holder.rotation_degrees.y = MODEL_YAW
	visual.add_child(holder)
	holder.add_child(model)

	var box: AABB = model_aabb(holder)
	if box.size.y <= 0.001:
		holder.queue_free()
		return false
	holder.scale = Vector3.ONE * (MODEL_HEIGHT / box.size.y)
	box = model_aabb(holder)
	holder.position -= Vector3(box.position.x + box.size.x / 2.0, box.position.y, box.position.z + box.size.z / 2.0)

	anim_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		for n in anim_player.get_animation_list():
			var key: String = classify_anim(String(n))
			if key != "" and not anims.has(key):
				anims[key] = String(n)
		for k in ["idle", "walk", "run"]:
			if anims.has(k):
				var a: Animation = anim_player.get_animation(anims[k])
				if a:
					a.loop_mode = Animation.LOOP_LINEAR

	if ADD_SWORD_TO_MODEL:
		attach_sword_to_hand(model)
	return true

func classify_anim(anim_name: String) -> String:
	var n: String = anim_name.to_lower()
	if n.begins_with("reset"):
		return ""
	if "death" in n or "die" in n or "dead" in n or "defeat" in n:
		return "death"
	if "attack" in n or "slash" in n or "strike" in n or "swing" in n:
		return "attack"
	if "hurt" in n or "damage" in n or "hit" in n:
		return "hit"
	if "walk" in n:
		return "walk"
	if "run" in n:
		return "run"
	if "idle" in n:
		return "idle"
	return ""

func model_aabb(root: Node3D) -> AABB:
	var to_local: Transform3D = visual.global_transform.affine_inverse()
	var result := AABB()
	var first: bool = true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b: AABB = to_local * mi.global_transform * mi.get_aabb()
		if first:
			result = b
			first = false
		else:
			result = result.merge(b)
	return result

# Dayein haath ki haddi par talwar lagao (model ke paas talwar na ho to)
func attach_sword_to_hand(model: Node) -> void:
	var skels: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel := skels[0] as Skeleton3D
	var bone_name: String = ""
	for i in range(skel.get_bone_count()):
		var bn: String = skel.get_bone_name(i)
		var l: String = bn.to_lower()
		if not (l.contains("hand") or l.contains("palm")):
			continue
		if l.contains("thumb") or l.contains("index") or l.contains("middle") or l.contains("ring") or l.contains("pinky") or l.contains("finger"):
			continue
		if l.contains("right") or l.ends_with(".r") or l.ends_with("_r"):
			bone_name = bn
			break
	if bone_name == "":
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone_name
	skel.add_child(ba)
	var sword: Node3D = build_sword()
	ba.add_child(sword)
	var sc: float = skel.global_transform.basis.get_scale().x
	if sc > 0.0001:
		sword.scale = Vector3.ONE / sc

# ---------------- Sword (talwar) ----------------
func build_sword() -> Node3D:
	var root := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.82, 0.88)
	steel.roughness = 0.3
	steel.emission_enabled = true
	steel.emission = Color(0.3, 0.35, 0.42)
	steel.emission_energy_multiplier = 0.6
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.7, 0.5, 0.15)
	brass.roughness = 0.5

	root.add_child(part(BoxMesh.new(), steel, Vector3(0, 0.6, 0), Vector3(0.07, 1.0, 0.018)))   # phal
	root.add_child(part(BoxMesh.new(), brass, Vector3(0, 0.1, 0), Vector3(0.3, 0.05, 0.06)))    # guard
	root.add_child(part(BoxMesh.new(), brass, Vector3(0, -0.04, 0), Vector3(0.05, 0.2, 0.05)))  # mooth
	return root

func part(mesh: Mesh, material: Material, pos: Vector3, size: Vector3) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	return mi

# ---------------- Placeholder yoddha (code se bana) ----------------
func build_placeholder() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.62, 0.56, 0.52)   # rakh jaisa rang
	skin.roughness = 0.9
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.40, 0.06, 0.06)
	cloth.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.06, 0.06)
	dark.roughness = 1.0

	leg_l = limb(Vector3(-0.17, 0.95, 0), cloth, 0.13, 0.95, 0.47)
	leg_r = limb(Vector3(0.17, 0.95, 0), cloth, 0.13, 0.95, 0.47)

	var torso := CapsuleMesh.new()
	torso.radius = 0.3
	torso.height = 1.0
	visual.add_child(mesh_node(torso, skin, Vector3(0, 1.4, 0)))
	var belt := CylinderMesh.new()
	belt.top_radius = 0.33
	belt.bottom_radius = 0.36
	belt.height = 0.3
	visual.add_child(mesh_node(belt, cloth, Vector3(0, 0.98, 0)))

	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	visual.add_child(mesh_node(head, skin, Vector3(0, 2.0, 0)))
	var hair := CylinderMesh.new()
	hair.top_radius = 0.06
	hair.bottom_radius = 0.22
	hair.height = 0.35
	visual.add_child(mesh_node(hair, dark, Vector3(0, 2.2, 0)))

	arm_l = limb(Vector3(-0.42, 1.75, 0), skin, 0.09, 0.75, 0.37)
	arm_r = limb(Vector3(0.42, 1.75, 0), skin, 0.09, 0.75, 0.37)
	arm_r.rotation.x = -0.55

	# Talwar dayein haath me (phal haath ke saath aage ki taraf)
	var sword: Node3D = build_sword()
	sword.position = Vector3(0, -0.75, 0)
	sword.rotation_degrees = Vector3(-90, 0, 0)
	arm_r.add_child(sword)

func limb(pivot_pos: Vector3, material: Material, radius: float, length: float, down: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	visual.add_child(pivot)
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	pivot.add_child(mesh_node(cap, material, Vector3(0, -down, 0)))
	return pivot

func mesh_node(mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	return mi

# ---------------- Animation ----------------
func play_anim(key: String, once: bool = false) -> void:
	if anim_player == null:
		return
	var use: String = key
	if use == "run" and not anims.has("run"):
		use = "walk"
	if use == "walk" and not anims.has("walk") and anims.has("run"):
		use = "run"
	if not anims.has(use):
		return
	if current_anim == use and not once:
		return
	current_anim = use
	anim_player.speed_scale = 1.0
	anim_player.play(anims[use], 0.15)

func play_attack_anim() -> void:
	if anim_player and anims.has("attack"):
		var a: Animation = anim_player.get_animation(anims["attack"])
		current_anim = "attack"
		if a and a.length > 0.0:
			anim_player.speed_scale = a.length / (windup_time + strike_time)
		anim_player.play(anims["attack"], 0.1)

func animate(delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if using_model:
		if state == State.GUARD or state == State.CHASE or state == State.RECOVER:
			if speed > 0.5:
				play_anim("run" if state == State.CHASE else "walk")
			else:
				play_anim("idle")
		return

	# Placeholder: code se chalna aur talwar ghumana
	walk_phase += speed * delta * 2.4
	var amp: float = clampf(speed / 3.0, 0.0, 1.0)
	leg_l.rotation.x = sin(walk_phase) * 0.7 * amp
	leg_r.rotation.x = -sin(walk_phase) * 0.7 * amp
	arm_l.rotation.x = -sin(walk_phase) * 0.5 * amp

	var arm_target: float = -0.55
	match state:
		State.WINDUP:
			arm_target = lerpf(-0.55, -2.9, clampf(state_time / windup_time, 0.0, 1.0))
		State.STRIKE:
			arm_target = lerpf(-2.9, -0.15, clampf(state_time / strike_time, 0.0, 1.0))
		State.RECOVER:
			arm_target = lerpf(-0.15, -0.55, clampf(state_time / recover_time, 0.0, 1.0))
	arm_r.rotation.x = arm_target
	visual.rotation.x = -0.25 if state == State.HURT else 0.0
	visual.position.y = absf(sin(walk_phase)) * 0.05 * amp

# ---------------- AI ----------------
func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	hit_done = false
	match s:
		State.WINDUP:
			play_attack_anim()
		State.HURT:
			if anim_player and anims.has("hit"):
				play_anim("hit", true)
		State.GUARD, State.CHASE, State.RECOVER:
			current_anim = ""

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	state_time += delta
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	var to_p := Vector3.ZERO
	var dist: float = 9999.0
	if player:
		to_p = player.global_position - global_position
		to_p.y = 0.0
		dist = to_p.length()
	var dir: Vector3 = to_p / dist if dist > 0.01 else Vector3.ZERO

	match state:
		State.GUARD:
			var to_home: Vector3 = home - global_position
			to_home.y = 0.0
			if to_home.length() > 1.5:
				_move(to_home.normalized(), move_speed * 0.6, delta)
				_face(to_home.normalized(), delta)
			else:
				_stop(delta)
			if dist < aggro_range:
				_set_state(State.CHASE)
		State.CHASE:
			if dist <= attack_range:
				_set_state(State.WINDUP)
			elif dist > aggro_range * 2.2:
				_set_state(State.GUARD)
			else:
				_move(dir, move_speed, delta)
				_face(dir, delta)
		State.WINDUP:
			_stop(delta)
			_face(dir, delta)
			if state_time >= windup_time:
				_set_state(State.STRIKE)
		State.STRIKE:
			_stop(delta)
			if not hit_done:
				hit_done = true
				do_strike(dist, dir)
			if state_time >= strike_time:
				_set_state(State.RECOVER)
		State.RECOVER:
			_stop(delta)
			if state_time >= recover_time:
				_set_state(State.CHASE if dist < aggro_range * 2.2 else State.GUARD)
		State.HURT:
			_stop(delta)
			if state_time >= 0.4:
				_set_state(State.CHASE)

	move_and_slide()
	animate(delta)

func _move(dir: Vector3, speed: float, delta: float) -> void:
	velocity.x = move_toward(velocity.x, dir.x * speed, 25.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 25.0 * delta)

func _stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)

func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var target: float = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target, clampf(10.0 * delta, 0.0, 1.0))

func do_strike(dist: float, dir: Vector3) -> void:
	sfx("res://audio/sword_swing", "slash", -4.0)
	var forward: Vector3 = -global_transform.basis.z
	if dist <= attack_range + 0.9 and forward.dot(dir) > 0.3:
		if player and player.has_method("take_damage"):
			player.take_damage(damage, global_position)
			sfx("res://audio/sword_hit", "hit")

# ---------------- Damage / maut ----------------
func take_hit(amount: int, from_pos: Vector3) -> void:
	if state == State.DEAD:
		return
	health -= amount
	var away: Vector3 = global_position - from_pos
	away.y = 0.0
	if away.length() > 0.01:
		away = away.normalized()
	spawn_blood(global_position + Vector3(0, 1.3, 0), away, 26)
	spawn_splat(global_position + away * 0.6, randf_range(0.7, 1.2), false)
	if health <= 0:
		die(away)
		return
	velocity += away * 5.0
	_set_state(State.HURT)

func die(away: Vector3) -> void:
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	died.emit(self)
	sfx("res://audio/warrior_die", "hit", -2.0)
	spawn_blood(global_position + Vector3(0, 1.2, 0), away, 50)
	spawn_splat(global_position, 2.4, true)

	if using_model and anim_player and anims.has("death"):
		current_anim = "death"
		anim_player.speed_scale = 1.0
		anim_player.play(anims["death"], 0.1)
	else:
		var tw := create_tween()
		tw.tween_property(visual, "rotation_degrees:x", 88.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(visual, "position:y", 0.2, 0.7)

	await get_tree().create_timer(9.0).timeout
	if not is_inside_tree():
		return
	var fade := create_tween()
	fade.tween_property(visual, "scale", Vector3.ONE * 0.01, 1.0)
	fade.tween_callback(queue_free)

# Level 2 me khilaadi ke girne par yoddha apni jagah laut jate hain
func reset_to_home() -> void:
	if state == State.DEAD:
		return
	health = max_health
	global_position = home + Vector3(0, 0.1, 0)
	velocity = Vector3.ZERO
	_set_state(State.GUARD)

# ---------------- Khoon ----------------
func spawn_blood(pos: Vector3, dir: Vector3, amount: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.02, 0.02)
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.0, 0.0)
	mat.emission_energy_multiplier = 0.8

	var drop := SphereMesh.new()
	drop.radius = 0.035
	drop.height = 0.07
	drop.radial_segments = 6
	drop.rings = 3
	drop.material = mat

	var p := CPUParticles3D.new()
	p.mesh = drop
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = dir + Vector3(0, 0.8, 0)
	p.spread = 55.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -14.0, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.7
	get_parent().add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.8).timeout.connect(p.queue_free)

func get_splat_texture() -> GradientTexture2D:
	if splat_texture == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		g.colors = PackedColorArray([Color(0.5, 0.02, 0.02, 0.95), Color(0.35, 0.01, 0.01, 0.8), Color(0.3, 0.0, 0.0, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		splat_texture = t
	return splat_texture

# Zameen par khoon ka dhabba (dheere phailta hai, ~30 second baad gayab)
func spawn_splat(pos: Vector3, size: float, grow: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = get_splat_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.0, 0.0)
	mat.emission_energy_multiplier = 0.6

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.rotation_degrees = Vector3(-90.0, randf() * 360.0, 0.0)
	get_parent().add_child(mi)
	mi.global_position = Vector3(pos.x, 0.06, pos.z)

	var tw := mi.create_tween()
	if grow:
		mi.scale = Vector3.ONE * 0.2
		tw.tween_property(mi, "scale", Vector3.ONE, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(25.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 4.0)
	tw.tween_callback(mi.queue_free)
