extends CharacterBody3D
# Yoddha: ek hi script se teen tarah ke dushman
#   role "ground" = talwar wala sipahi      (models/tribal.glb)
#   role "guard"  = bhala + dhaal rakshak    (models/guard.glb)
#   role "boss"   = yoddha-raj, sunehri kavach (models/boss.glb)
# Model na mile to code se bana placeholder dikhta hai. Aage ke levels me bhi yahi script chalegi.

signal died(warrior)
signal blocked(warrior)

enum State { GUARD, CHASE, WINDUP, STRIKE, RECOVER, HURT, DEAD }

const MODEL_YAW: float = 180.0          # zyadatar models +Z dekhte hain. Ulta dikhe to 0.0 kar do
const ADD_SWORD_TO_MODEL: bool = true
const TINT_WARRIORS: bool = false       # sirf Quaternius knight ke liye (chhaya-grast look)
# Haath me talwar ki disha theek na dikhe to yahan (degree) badlo: jaise Vector3(90, 0, 0)
const WEAPON_HAND_ROT: Vector3 = Vector3(0, 0, 0)

# ---- Level script ye set karti hai (add_child se pehle) ----
var role: String = "ground"
var sword_pack_index: int = 1           # swords.glb me kaun si talwar (0..3)
var weapon_index: int = 0               # Quaternius fallback (Katana, Sword, ShortSword)
var player
var game_manager: Node
var home: Vector3 = Vector3.ZERO

# ---- Role ke hisaab se (apply_role me bharta hai) ----
var model_names: Array = ["tribal", "warrior", "KnightCharacter"]
var model_height: float = 1.85
var sword_length: float = 1.1
var has_sword: bool = true
var has_shield: bool = false
var shield_max: int = 3
var shield_hp: int = 0
var shield_regen: float = 0.0
var invulnerable: bool = false
var max_health: int = 4
var health: int = 4
var move_speed: float = 3.2
var aggro_range: float = 24.0
var attack_range: float = 2.2
var windup_time: float = 0.55
var strike_time: float = 0.25
var recover_time: float = 0.9
var damage: float = 12.0

var state: State = State.GUARD
var state_time: float = 0.0
var hit_done: bool = false

var visual: Node3D
var aura: MeshInstance3D
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

func apply_role() -> void:
	match role:
		"guard":
			model_names = ["guard", "spearman", "tribal", "warrior"]
			model_height = 1.95
			has_sword = false
			has_shield = true
			shield_hp = shield_max
			max_health = 4
			damage = 14.0
			move_speed = 3.0
			aggro_range = 70.0
			attack_range = 3.2
			windup_time = 0.7
			recover_time = 1.0
		"boss":
			model_names = ["boss", "indian_warrior", "tribal", "warrior"]
			model_height = 2.5
			sword_length = 1.7
			max_health = 16
			damage = 20.0
			move_speed = 3.6
			aggro_range = 90.0
			attack_range = 2.9
			windup_time = 0.45
			recover_time = 0.7
		_:
			model_names = ["tribal", "warrior", "KnightCharacter"]
	health = max_health

func _ready() -> void:
	add_to_group("enemy")
	apply_role()

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45 * (model_height / 1.85)
	cap.height = model_height
	col.shape = cap
	col.position = Vector3(0, model_height / 2.0, 0)
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

# Boss ka sunehri kavach (jab tak rakshak zinda hain, boss par vaar nahi lagta)
func set_invulnerable(on: bool) -> void:
	invulnerable = on
	if on and aura == null:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.8, 0.3, 0.16)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.2)
		mat.emission_energy_multiplier = 1.4
		var sphere := SphereMesh.new()
		sphere.radius = model_height * 0.62
		sphere.height = model_height * 1.24
		aura = MeshInstance3D.new()
		aura.mesh = sphere
		aura.material_override = mat
		aura.position = Vector3(0, model_height * 0.5, 0)
		aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(aura)
	elif not on and aura:
		aura.queue_free()
		aura = null

# ---------------- Model ----------------
func try_model() -> bool:
	var path: String = ""
	if game_manager and game_manager.has_method("find_model_path"):
		path = game_manager.find_model_path(model_names)
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
	holder.scale = Vector3.ONE * (model_height / box.size.y)
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

	if TINT_WARRIORS and path.to_lower().contains("knight"):
		var tint := StandardMaterial3D.new()
		tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tint.albedo_color = Color(0.22, 0.03, 0.08, 0.38)
		for node in model.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_overlay = tint

	if has_sword and ADD_SWORD_TO_MODEL:
		if not attach_sword_to_hand(model):
			attach_static_weapon()
	return true

func classify_anim(anim_name: String) -> String:
	var n: String = anim_name.to_lower()
	if n.begins_with("reset"):
		return ""
	if "death" in n or "die" in n or "dead" in n or "defeat" in n:
		return "death"
	if "attack" in n or "slash" in n or "strike" in n or "swing" in n or "stab" in n:
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

# Talwar banao: pehle swords.glb ki chuni hui talwar, phir Quaternius, phir code wali
func make_sword(parent_scale: float) -> Node3D:
	var sword: Node3D = null
	if game_manager and game_manager.has_method("make_pack_weapon"):
		sword = game_manager.make_pack_weapon(sword_pack_index, sword_length, parent_scale)
	if sword == null and game_manager and game_manager.has_method("make_weapon"):
		var names: Array = ["Katana", "Sword", "ShortSword"]
		sword = game_manager.make_weapon([names[weapon_index % names.size()]], sword_length, parent_scale)
	if sword == null:
		sword = build_sword()
		sword.scale = Vector3.ONE / maxf(parent_scale, 0.0001)
	return sword

# Dayein haath ki haddi par talwar lagao. Haddi na mile to false.
func attach_sword_to_hand(model: Node) -> bool:
	var skels: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return false
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
		return false
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone_name
	skel.add_child(ba)
	var sc: float = skel.global_transform.basis.get_scale().x
	if sc <= 0.0001:
		sc = 1.0
	var grip := Node3D.new()
	grip.rotation_degrees = WEAPON_HAND_ROT
	ba.add_child(grip)
	grip.add_child(make_sword(sc))
	return true

# Haddi wala model na ho to talwar seedhi daayein taraf (sharir ke saath hilti hai)
func attach_static_weapon() -> void:
	var sword: Node3D = make_sword(1.0)
	var s: float = model_height / 1.9
	sword.position = Vector3(0.42 * s, 1.0 * s, -0.12 * s)
	sword.rotation_degrees = Vector3(-60, 0, 0)
	visual.add_child(sword)

# ---------------- Code wali talwar / placeholder ----------------
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
	root.add_child(part(BoxMesh.new(), steel, Vector3(0, 0.6, 0), Vector3(0.07, 1.0, 0.018)))
	root.add_child(part(BoxMesh.new(), brass, Vector3(0, 0.1, 0), Vector3(0.3, 0.05, 0.06)))
	root.add_child(part(BoxMesh.new(), brass, Vector3(0, -0.04, 0), Vector3(0.05, 0.2, 0.05)))
	return root

func part(mesh: Mesh, material: Material, pos: Vector3, size: Vector3) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	return mi

func build_placeholder() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.62, 0.56, 0.52)
	skin.roughness = 0.9
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.40, 0.06, 0.06)
	if role == "boss":
		cloth.albedo_color = Color(0.85, 0.65, 0.2)
		cloth.emission_enabled = true
		cloth.emission = Color(0.8, 0.55, 0.1)
		cloth.emission_energy_multiplier = 0.4
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

	if role == "guard":
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.45, 0.3, 0.15)
		var spear := Node3D.new()
		spear.position = Vector3(0, -0.75, 0)
		spear.rotation_degrees = Vector3(-90, 0, 0)
		spear.add_child(part(BoxMesh.new(), wood, Vector3(0, 0.6, 0), Vector3(0.05, 2.2, 0.05)))
		spear.add_child(part(BoxMesh.new(), build_steel(), Vector3(0, 1.8, 0), Vector3(0.09, 0.3, 0.02)))
		arm_r.add_child(spear)
		var shield := CylinderMesh.new()
		shield.top_radius = 0.42
		shield.bottom_radius = 0.42
		shield.height = 0.06
		var sh := mesh_node(shield, wood, Vector3(-0.1, -0.45, -0.3))
		sh.rotation_degrees = Vector3(90, 0, 0)
		arm_l.add_child(sh)
	else:
		var sword: Node3D = build_sword()
		sword.position = Vector3(0, -0.75, 0)
		sword.rotation_degrees = Vector3(-90, 0, 0)
		arm_r.add_child(sword)

	visual.scale = Vector3.ONE * (model_height / 1.85)

func build_steel() -> StandardMaterial3D:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.82, 0.88)
	steel.roughness = 0.3
	return steel

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
	var has_loco: bool = anim_player != null and (anims.has("idle") or anims.has("walk") or anims.has("run"))
	if using_model and has_loco:
		if state == State.GUARD or state == State.CHASE or state == State.RECOVER:
			if speed > 0.5:
				play_anim("run" if state == State.CHASE else "walk")
			else:
				play_anim("idle")
		return
	if using_model:
		animate_static(delta, speed)
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
	visual.rotation.x = 0.25 if state == State.HURT else 0.0
	visual.position.y = absf(sin(walk_phase)) * 0.05 * amp

# Animation-rahit model (khadi mudra): poora sharir jhoomta, jhukta aur lunge karta hai
func animate_static(delta: float, speed: float) -> void:
	walk_phase += speed * delta * 2.6
	var amp: float = clampf(speed / 3.0, 0.0, 1.0)
	var rot: float = -0.10 * amp
	var zoff: float = 0.0
	match state:
		State.WINDUP:
			var k: float = clampf(state_time / windup_time, 0.0, 1.0)
			rot = 0.22 * k
			zoff = 0.15 * k
		State.STRIKE:
			var k2: float = clampf(state_time / strike_time, 0.0, 1.0)
			rot = lerpf(0.22, -0.40, k2)
			zoff = lerpf(0.15, -0.55, k2)
		State.RECOVER:
			var k3: float = clampf(state_time / recover_time, 0.0, 1.0)
			rot = lerpf(-0.40, 0.0, k3)
			zoff = lerpf(-0.55, 0.0, k3)
		State.HURT:
			rot = 0.30
	var f: float = clampf(14.0 * delta, 0.0, 1.0)
	visual.rotation.x = lerpf(visual.rotation.x, rot, f)
	visual.position.z = lerpf(visual.position.z, zoff, f)
	visual.position.y = absf(sin(walk_phase)) * 0.07 * amp

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

	# Dhaal toot gayi ho to kuch der baad wapas
	if has_shield and shield_hp <= 0:
		shield_regen -= delta
		if shield_regen <= 0.0:
			shield_hp = shield_max

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
			_face(dir, delta)
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
		# Khilaadi ki talwar bhi ghoom rahi ho to takrav (clash): kisi ko chot nahi
		if player and player.has_method("is_swinging") and player.is_swinging():
			on_clash(player.global_position)
			if player.has_method("nudge"):
				player.nudge(dir, 4.0)
			return
		if player and player.has_method("take_damage"):
			player.take_damage(damage, global_position)
			sfx("res://audio/sword_hit", "hit")

# ---------------- Takrav, dhaal, damage, maut ----------------
func on_clash(other_pos: Vector3) -> void:
	if state == State.DEAD:
		return
	var away: Vector3 = global_position - other_pos
	away.y = 0.0
	if away.length() > 0.01:
		away = away.normalized()
	spawn_sparks(global_position.lerp(other_pos, 0.5) + Vector3(0, 1.3, 0))
	if role == "guard":
		sfx("res://audio/shield_clash", "shield")
	else:
		sfx("res://audio/sword_clash", "clash")
	velocity += away * 4.0
	_set_state(State.RECOVER)
	state_time = -0.35   # takrane ke baad thodi der ladkhadate hain

# 0 = chot lagi, 1 = takrav / dhaal / kavach (chot nahi lagi)
func take_hit(amount: int, from_pos: Vector3) -> int:
	if state == State.DEAD:
		return 1
	if invulnerable:
		spawn_sparks(global_position + Vector3(0, model_height * 0.6, 0))
		sfx("res://audio/sword_clash", "clash")
		blocked.emit(self)
		return 1
	var to_att: Vector3 = from_pos - global_position
	to_att.y = 0.0
	if to_att.length() > 0.01:
		to_att = to_att.normalized()

	# Dushman ki talwar/bhala chal raha ho to takrav
	if state == State.WINDUP or state == State.STRIKE:
		on_clash(from_pos)
		if player and player.has_method("nudge"):
			player.nudge(to_att, 4.0)
		return 1

	# Dhaal: saamne se vaar rok leti hai (3 vaar me toot jati hai)
	if has_shield and shield_hp > 0 and (-global_transform.basis.z).dot(to_att) > 0.25:
		shield_hp -= 1
		spawn_sparks(global_position + Vector3(0, model_height * 0.65, 0) + to_att * 0.6)
		sfx("res://audio/shield_clash", "shield")
		if player and player.has_method("nudge"):
			player.nudge(to_att, 3.0)
		if shield_hp <= 0:
			shield_regen = 6.0
			_set_state(State.HURT)
			state_time = -1.0   # dhaal tooti: kuch der behosh, ab vaar lagega
		return 1

	health -= amount
	var away: Vector3 = -to_att
	spawn_blood(global_position + Vector3(0, model_height * 0.7, 0), away, 26)
	spawn_splat(global_position + away * 0.6, randf_range(0.7, 1.2), false)
	if health <= 0:
		die(away)
		return 0
	velocity += away * 5.0
	_set_state(State.HURT)
	return 0

func die(away: Vector3) -> void:
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if aura:
		aura.queue_free()
		aura = null
	died.emit(self)
	sfx("res://audio/warrior_die", "hit", -2.0)
	spawn_blood(global_position + Vector3(0, model_height * 0.65, 0), away, 50)
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

# Khilaadi ke girne par yoddha apni jagah laut jate hain
func reset_to_home() -> void:
	if state == State.DEAD:
		return
	health = max_health
	if has_shield:
		shield_hp = shield_max
	global_position = home + Vector3(0, 0.1, 0)
	velocity = Vector3.ZERO
	_set_state(State.GUARD)

# ---------------- Chingaari aur khoon ----------------
func spawn_sparks(pos: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	var spark := BoxMesh.new()
	spark.size = Vector3(0.03, 0.03, 0.12)
	spark.material = mat

	var p := CPUParticles3D.new()
	p.mesh = spark
	p.amount = 26
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -9.0, 0)
	get_parent().add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)

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
