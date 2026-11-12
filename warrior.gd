extends CharacterBody3D
# Yoddha: ek hi script se teen tarah ke dushman
#   role "ground" = talwar wala sipahi      (models/tribal.glb)
#   role "guard"  = bhala + dhaal rakshak    (models/guard.glb)
#   role "boss"   = yoddha-raj, sunehri kavach (models/boss.glb)
# Model na mile to code se bana placeholder dikhta hai. Aage ke levels me bhi yahi script chalegi.

signal died(warrior)
signal blocked(warrior)

# Code wala "auto-rig": model me haddi/animation na ho to bhi haath-pair hilte hain.
# Har vertex ki jagah dekhkar (pair / haath ka hissa) use hip/kandhe ke aas-paas ghumaya jata hai.
const RIG_SHADER: String = """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_off = vec2(0.0);
uniform float use_orm = 0.0;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float metallic_val = 0.0;
uniform float roughness_val = 1.0;
uniform float use_normal = 0.0;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 1.0;
uniform float use_emission = 0.0;
uniform sampler2D emission_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 emission_col : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform float alpha_cut = -1.0;

uniform mat4 to_model;
uniform mat4 from_model;
uniform vec4 body = vec4(0.0, 0.0, 0.0, 1.0);
uniform float arm_ymin = 0.38;
uniform float elbow_use = 1.0;

uniform float leg_neg = 0.0;
uniform float leg_pos = 0.0;
uniform float knee_neg = 0.0;
uniform float knee_pos = 0.0;
uniform float twist = 0.0;
uniform float lean = 0.0;
uniform float elbow_neg = 0.0;
uniform float elbow_pos = 0.0;
uniform vec4 arm_neg = vec4(0.0);
uniform vec4 arm_pos = vec4(0.0);

uniform vec3 piv_hip = vec3(0.0);
uniform vec3 piv_leg_neg = vec3(0.0);
uniform vec3 piv_leg_pos = vec3(0.0);
uniform vec3 piv_knee_neg = vec3(0.0);
uniform vec3 piv_knee_pos = vec3(0.0);
uniform vec3 piv_arm_neg = vec3(0.0);
uniform vec3 piv_arm_pos = vec3(0.0);
uniform vec3 piv_elbow_neg = vec3(0.0);
uniform vec3 piv_elbow_pos = vec3(0.0);

vec3 rotx(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
}

// Dhad ka ghumav (twist) aur jhukav (lean): kamar ke aas-paas
vec3 torso_xf(vec3 p) {
	vec3 q = p - piv_hip;
	float c = cos(twist);
	float s = sin(twist);
	q = vec3(q.x * c + q.z * s, q.y, -q.x * s + q.z * c);
	q = rotx(q, lean);
	return piv_hip + q;
}

void vertex() {
	vec3 p = (to_model * vec4(VERTEX, 1.0)).xyz;
	float h = max(body.w, 0.001);
	vec3 u = vec3((p.x - body.x) / h, (p.y - body.y) / h, (p.z - body.z) / h);
	float side = smoothstep(-0.035, 0.035, u.x);
	float ax = smoothstep(0.16, 0.22, abs(u.x));
	float ay = 1.0;
	if (arm_ymin > 0.0) {
		ay = smoothstep(arm_ymin - 0.04, arm_ymin + 0.04, u.y);
	}
	float arm_gate = ax * ay;
	float tw = max(smoothstep(0.48, 0.58, u.y), arm_gate);
	float lw = (1.0 - smoothstep(0.46, 0.56, u.y)) * (1.0 - arm_gate);
	float shin = 1.0 - smoothstep(0.24, 0.32, u.y);

	// Pair: jaangh (hip) se, phir ghutna (knee) se
	vec3 pa_n = piv_leg_neg + rotx(p - piv_leg_neg, leg_neg);
	vec3 kn_n = piv_leg_neg + rotx(piv_knee_neg - piv_leg_neg, leg_neg);
	vec3 leg_n = mix(pa_n, kn_n + rotx(pa_n - kn_n, knee_neg), shin);
	vec3 pa_p = piv_leg_pos + rotx(p - piv_leg_pos, leg_pos);
	vec3 kn_p = piv_leg_pos + rotx(piv_knee_pos - piv_leg_pos, leg_pos);
	vec3 leg_p = mix(pa_p, kn_p + rotx(pa_p - kn_p, knee_pos), shin);
	vec3 legs_res = mix(leg_n, leg_p, side);

	// Upar ka sharir: dhad ghuma, phir haath kandhe se, phir kohni se
	vec3 pt = mix(p, torso_xf(p), tw);
	vec3 sn = torso_xf(piv_arm_neg);
	vec3 an = sn + rotx(pt - sn, arm_neg.x) + arm_neg.yzw;
	vec3 en = sn + rotx(torso_xf(piv_elbow_neg) - sn, arm_neg.x) + arm_neg.yzw;
	float fa_n = smoothstep(0.24, 0.30, abs(u.x)) * elbow_use;
	vec3 arm_n = mix(an, en + rotx(an - en, elbow_neg), fa_n);
	vec3 sp = torso_xf(piv_arm_pos);
	vec3 ap = sp + rotx(pt - sp, arm_pos.x) + arm_pos.yzw;
	vec3 ep = sp + rotx(torso_xf(piv_elbow_pos) - sp, arm_pos.x) + arm_pos.yzw;
	float fa_p = smoothstep(0.24, 0.30, abs(u.x)) * elbow_use;
	vec3 arm_p = mix(ap, ep + rotx(ap - ep, elbow_pos), fa_p);
	vec3 arms_res = mix(arm_n, arm_p, side);

	vec3 body_res = mix(pt, arms_res, arm_gate);
	vec3 final_p = mix(body_res, legs_res, lw);
	VERTEX = (from_model * vec4(final_p, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale + uv_off;
	vec4 a = texture(albedo_tex, uv) * albedo_col;
	if (a.a < alpha_cut) {
		discard;
	}
	ALBEDO = a.rgb;
	if (use_orm > 0.5) {
		vec3 orm = texture(orm_tex, uv).rgb;
		ROUGHNESS = orm.g * roughness_val;
		METALLIC = orm.b * metallic_val;
	} else {
		ROUGHNESS = roughness_val;
		METALLIC = metallic_val;
	}
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (use_emission > 0.5) {
		EMISSION = texture(emission_tex, uv).rgb * emission_col * emission_energy;
	}
}
"""

enum State { GUARD, CHASE, WINDUP, STRIKE, RECOVER, HURT, DEAD }

const MODEL_YAW: float = 180.0          # zyadatar models +Z dekhte hain. Ulta dikhe to 0.0 kar do
const ADD_SWORD_TO_MODEL: bool = true
# Talwar ulti (phal neeche, mooth upar) dikhe to true kar do
const WARRIOR_SWORD_FLIP: bool = false
# Haddi wale model me talwar ki disha theek na dikhe to yahan (degree) badlo: jaise Vector3(90, 0, 0)
const WEAPON_HAND_ROT: Vector3 = Vector3(0, 0, 0)
# Bina haddi wale (khadi mudra) model me talwar haath se aage-upar ko jhuki rehti hai
const STATIC_SWORD_TILT: Vector3 = Vector3(-60, 0, 0)

# ---- Level script ye set karti hai (add_child se pehle) ----
var role: String = "ground"
var sword_pack_index: int = 1           # swords.glb me kaun si talwar (0..3)
var weapon_index: int = 0               # Quaternius fallback (Katana, Sword, ShortSword)
var player
var game_manager: Node
var home: Vector3 = Vector3.ZERO

# ---- Role ke hisaab se (apply_role me bharta hai) ----
var model_names: Array = ["tribal", "warrior", "KnightCharacter"]
var anim_prefix: String = "tribal"
var model_height: float = 1.85
var sword_length: float = 1.1
var has_sword: bool = true
var has_shield: bool = false
var shield_max: int = 3
var shield_hp: int = 0
var shield_regen: float = 0.0
var invulnerable: bool = false
var parry_chance: float = 0.3           # dushman kabhi-kabhi khud talwar se vaar rok leta hai (random)
var max_health: int = 4
var health: int = 4
var move_speed: float = 3.2
var aggro_range: float = 24.0
var attack_range: float = 2.2
var windup_time: float = 0.55
var windup_cur: float = 0.55
var strike_time: float = 0.25
var recover_time: float = 0.9
var damage: float = 10.0

var state: State = State.GUARD
var state_time: float = 0.0
var hit_done: bool = false
var parry_time: float = 0.0
var shield_pop: float = 0.0

var visual: Node3D
var aura: MeshInstance3D
var anim_player: AnimationPlayer
var anims: Dictionary = {}
var using_model: bool = false
var current_anim: String = ""

# Talwar / bhala / dhaal
var weapon_pivot: Node3D
var sword_node: Node3D
var spear_node: Node3D
var shield_node: Node3D
var spear_rest: Vector3 = Vector3.ZERO
var shield_rest: Vector3 = Vector3.ZERO

# Placeholder ke ang
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var walk_phase: float = 0.0

static var splat_texture: GradientTexture2D = null
static var rig_shader: Shader = null
static var body_cache: Dictionary = {}

# ---- Auto-rig ki sthiti ----
var rig_ok: bool = false
var rig_mats: Array = []
var rig_piv_arm_neg: Vector3 = Vector3.ZERO   # neg = character ka dayan (model +Z dekhta ho to -X)
var rig_shoulder_neg: Vector3 = Vector3.ZERO
var rig_elbow_neg: Vector3 = Vector3.ZERO
var rig_piv_hip: Vector3 = Vector3.ZERO
var rig_piv_arm_pos: Vector3 = Vector3.ZERO
var rig_hand: Vector3 = Vector3.ZERO          # dayein haath ki jagah (model space)
var t_mv: Transform3D = Transform3D.IDENTITY  # model space -> visual space

func apply_role() -> void:
	match role:
		"guard":
			model_names = ["guard", "spearman", "tribal", "warrior"]
			anim_prefix = "guard"
			model_height = 1.95
			has_sword = false
			has_shield = true
			shield_hp = shield_max
			parry_chance = 0.0
			max_health = 4
			damage = 12.0
			move_speed = 3.0
			aggro_range = 70.0
			attack_range = 3.2
			windup_time = 0.7
			recover_time = 1.0
		"boss":
			model_names = ["boss", "indian_warrior", "tribal", "warrior"]
			anim_prefix = "boss"
			model_height = 2.5
			sword_length = 1.7
			parry_chance = 0.35
			max_health = 16
			damage = 16.0
			move_speed = 3.6
			aggro_range = 90.0
			attack_range = 2.9
			windup_time = 0.45
			recover_time = 0.7
		_:
			model_names = ["tribal", "warrior", "KnightCharacter"]
			anim_prefix = "tribal"
	windup_cur = windup_time
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

# base, base_1, base_2... me se koi ek random file bajao (na mile to code wali awaaz)
func sfx_variant(base: String, fallback: String, volume_db: float = 0.0) -> void:
	if game_manager and game_manager.has_method("play_variant"):
		game_manager.play_variant(base, fallback, volume_db)

# Boss ka sunehri kavach (jab tak rakshak zinda hain, boss na ladta hai na uspar vaar lagta hai)
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

	# Sharir ki asli unchai (bhala/talwar jaise bahar nikle hisse chhodkar) se size aur jagah tay karo
	var stats: Dictionary = compute_body_stats(model, path)
	if stats.is_empty():
		var box: AABB = model_aabb(holder)
		if box.size.y <= 0.001:
			holder.queue_free()
			return false
		holder.scale = Vector3.ONE * (model_height / box.size.y)
		box = model_aabb(holder)
		holder.position -= Vector3(box.position.x + box.size.x / 2.0, box.position.y, box.position.z + box.size.z / 2.0)
	else:
		holder.scale = Vector3.ONE * (model_height / float(stats["H"]))
		var feet: Vector3 = model.transform * Vector3(float(stats["cx"]), float(stats["y0"]), float(stats["cz"]))
		holder.position = -(holder.transform.basis * feet)
	t_mv = visual.global_transform.affine_inverse() * model.global_transform

	anim_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		for n in anim_player.get_animation_list():
			var key: String = classify_anim(String(n))
			if key != "" and not anims.has(key):
				anims[key] = String(n)
	# Alag files se animation (Mixamo): tribal_walk, tribal_attack, boss_idle, guard_walk ... (koi bhi extension)
	load_extra_anims(model)
	for k in ["idle", "walk", "run"]:
		if anims.has(k) and anim_player:
			var a: Animation = anim_player.get_animation(anims[k])
			if a:
				a.loop_mode = Animation.LOOP_LINEAR

	# Animation na ho to code wala auto-rig (haath-pair hilte hain)
	var has_loco_anim: bool = anim_player != null and (anims.has("idle") or anims.has("walk") or anims.has("run"))
	if not has_loco_anim and not stats.is_empty():
		rig_ok = build_rig(model, stats)

	if role == "guard" and not rig_ok:
		find_guard_props(model)

	if has_sword and ADD_SWORD_TO_MODEL:
		if rig_ok:
			attach_static_weapon(model)     # talwar rig ke haath ke saath chalti hai
		elif not attach_sword_to_hand(model):
			attach_static_weapon(model)
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

# models/<prefix>_<naam> files (jaise tribal_walk.fbx) se animation utha kar is model par lagao
func load_extra_anims(model: Node3D) -> void:
	if game_manager == null or not game_manager.has_method("find_model_path"):
		return
	for key in ["idle", "walk", "run", "attack", "hit", "death"]:
		if anims.has(key):
			continue
		var path: String = game_manager.find_model_path([anim_prefix + "_" + key])
		if path == "":
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var inst := scene.instantiate()
		var src := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if src:
			var chosen: String = ""
			for n in src.get_animation_list():
				if not String(n).to_lower().begins_with("reset"):
					chosen = String(n)
					break
			if chosen != "":
				if anim_player == null:
					anim_player = AnimationPlayer.new()
					model.add_child(anim_player)
				var lib: AnimationLibrary = anim_player.get_animation_library("")
				if lib == null:
					lib = AnimationLibrary.new()
					anim_player.add_animation_library("", lib)
				lib.add_animation(key, src.get_animation(chosen).duplicate())
				anims[key] = key
		inst.free()

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

# Model ke vertices se sharir ki unchai, beech aur dayein haath ki jagah (ek baar nikal kar cache)
func compute_body_stats(model: Node3D, path: String) -> Dictionary:
	if body_cache.has(path):
		return body_cache[path]
	var inv: Transform3D = model.global_transform.affine_inverse()
	var verts := PackedVector3Array()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var step: int = maxi(1, int(faces.size() / 8000.0))
		var i: int = 0
		while i < faces.size():
			verts.append(xf * faces[i])
			i += step
	if verts.size() < 60:
		return {}
	var ys := PackedFloat32Array()
	for v in verts:
		ys.append(v.y)
	ys.sort()
	var n: int = ys.size()
	var top_pct: float = 0.95 if role == "guard" else 0.995   # guard ka bhala ooncha nikla hota hai
	var y0: float = ys[int(n * 0.005)]
	var y1: float = ys[mini(int(n * top_pct), n - 1)]
	var h: float = y1 - y0
	if h < 0.001:
		return {}
	# Kamar/jaangh ke hisse se sharir ka beech
	var cx: float = 0.0
	var cz: float = 0.0
	var cnt: int = 0
	for v in verts:
		if v.y >= y0 + 0.2 * h and v.y <= y0 + 0.5 * h:
			cx += v.x
			cz += v.z
			cnt += 1
	if cnt == 0:
		return {}
	cx /= float(cnt)
	cz /= float(cnt)
	# Dayein haath (model +Z dekhe to dayein taraf -X): sabse bahar ke 4% jaalon ka beech
	var min_x: float = verts[0].x
	var max_x: float = verts[0].x
	for v in verts:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
	var width: float = max_x - min_x
	var hs := Vector3.ZERO
	var hn: int = 0
	for v in verts:
		if v.x <= min_x + width * 0.04:
			hs += v
			hn += 1
	var hand: Vector3 = hs / float(maxi(hn, 1))
	var d: Dictionary = {"H": h, "y0": y0, "cx": cx, "cz": cz, "hand": hand}
	body_cache[path] = d
	return d

func rotx_v(v: Vector3, a: float) -> Vector3:
	var c: float = cos(a)
	var sn: float = sin(a)
	return Vector3(v.x, v.y * c - v.z * sn, v.y * sn + v.z * c)

# Har surface ke liye wahi texture wala naya ShaderMaterial banao (tabhi vertex hilaye ja sakte hain)
func build_rig(model: Node3D, stats: Dictionary) -> bool:
	if rig_shader == null:
		rig_shader = Shader.new()
		rig_shader.code = RIG_SHADER
	var inv: Transform3D = model.global_transform.affine_inverse()
	var h: float = float(stats["H"])
	var y0: float = float(stats["y0"])
	var cx: float = float(stats["cx"])
	var cz: float = float(stats["cz"])
	rig_hand = stats["hand"]
	rig_shoulder_neg = Vector3(cx - 0.17 * h, y0 + 0.80 * h, cz)
	rig_elbow_neg = Vector3(cx - 0.27 * h, y0 + 0.62 * h, cz)
	rig_piv_hip = Vector3(cx, y0 + 0.50 * h, cz)
	rig_piv_arm_neg = rig_shoulder_neg
	rig_piv_arm_pos = Vector3(cx + 0.17 * h, y0 + 0.80 * h, cz)
	if role == "guard":
		# Bhala dayein haath me, dhaal bayein: bhale ko uski pakad (haath) par ghumao
		rig_piv_arm_neg = rig_hand
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		for si in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_active_material(si)
			var sm: ShaderMaterial = make_rig_material(src, xf, stats)
			if sm:
				mi.set_surface_override_material(si, sm)
				rig_mats.append(sm)
	return not rig_mats.is_empty()

func make_rig_material(src: Material, xf: Transform3D, stats: Dictionary) -> ShaderMaterial:
	if not (src is StandardMaterial3D):
		return null
	var m := src as StandardMaterial3D
	var sm := ShaderMaterial.new()
	sm.shader = rig_shader
	sm.set_shader_parameter("albedo_col", m.albedo_color)
	if m.albedo_texture:
		sm.set_shader_parameter("albedo_tex", m.albedo_texture)
	sm.set_shader_parameter("uv_scale", Vector2(m.uv1_scale.x, m.uv1_scale.y))
	sm.set_shader_parameter("uv_off", Vector2(m.uv1_offset.x, m.uv1_offset.y))
	var orm: Texture2D = m.roughness_texture if m.roughness_texture else m.metallic_texture
	if orm:
		sm.set_shader_parameter("orm_tex", orm)
		sm.set_shader_parameter("use_orm", 1.0)
	sm.set_shader_parameter("metallic_val", m.metallic)
	sm.set_shader_parameter("roughness_val", m.roughness)
	if m.normal_enabled and m.normal_texture:
		sm.set_shader_parameter("normal_tex", m.normal_texture)
		sm.set_shader_parameter("use_normal", 1.0)
		sm.set_shader_parameter("normal_scale", m.normal_scale)
	if m.emission_enabled:
		sm.set_shader_parameter("use_emission", 1.0)
		sm.set_shader_parameter("emission_col", Vector3(m.emission.r, m.emission.g, m.emission.b))
		sm.set_shader_parameter("emission_energy", m.emission_energy_multiplier)
		if m.emission_texture:
			sm.set_shader_parameter("emission_tex", m.emission_texture)
	if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		sm.set_shader_parameter("alpha_cut", m.alpha_scissor_threshold)
	elif m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		sm.set_shader_parameter("alpha_cut", 0.5)

	var h: float = float(stats["H"])
	var y0: float = float(stats["y0"])
	var cx: float = float(stats["cx"])
	var cz: float = float(stats["cz"])
	sm.set_shader_parameter("to_model", Projection(xf))
	sm.set_shader_parameter("from_model", Projection(xf.affine_inverse()))
	sm.set_shader_parameter("body", Vector4(cx, y0, cz, h))
	sm.set_shader_parameter("arm_ymin", 0.0 if role == "guard" else 0.38)
	sm.set_shader_parameter("piv_arm_neg", rig_piv_arm_neg)
	sm.set_shader_parameter("piv_arm_pos", rig_piv_arm_pos)
	sm.set_shader_parameter("piv_hip", rig_piv_hip)
	sm.set_shader_parameter("piv_leg_neg", Vector3(cx - 0.07 * h, y0 + 0.50 * h, cz))
	sm.set_shader_parameter("piv_leg_pos", Vector3(cx + 0.07 * h, y0 + 0.50 * h, cz))
	sm.set_shader_parameter("piv_knee_neg", Vector3(cx - 0.07 * h, y0 + 0.27 * h, cz))
	sm.set_shader_parameter("piv_knee_pos", Vector3(cx + 0.07 * h, y0 + 0.27 * h, cz))
	sm.set_shader_parameter("piv_elbow_neg", Vector3(cx - 0.27 * h, y0 + 0.62 * h, cz))
	sm.set_shader_parameter("piv_elbow_pos", Vector3(cx + 0.27 * h, y0 + 0.62 * h, cz))
	sm.set_shader_parameter("elbow_use", 0.0 if role == "guard" else 1.0)
	return sm

# Guard ke model me bhala aur dhaal alag nodes ho to unhe alag se hila sakte hain
func find_guard_props(model: Node3D) -> void:
	for node in model.find_children("*", "Node3D", true, false):
		var n: String = String(node.name).to_lower()
		if spear_node == null and (n.contains("spear") or n.contains("lance") or n.contains("javelin") or n.contains("pike") or n.contains("bhala")):
			spear_node = node as Node3D
		elif shield_node == null and (n.contains("shield") or n.contains("buckler") or n.contains("dhal")):
			shield_node = node as Node3D
	if spear_node:
		spear_rest = spear_node.position
	if shield_node:
		shield_rest = shield_node.position

# ---------------- Talwar ----------------
# Talwar banao: pehle swords.glb ki chuni hui talwar, phir Quaternius, phir code wali
func make_sword(parent_scale: float) -> Node3D:
	var sword: Node3D = null
	if game_manager and game_manager.has_method("make_pack_weapon"):
		sword = game_manager.make_pack_weapon(sword_pack_index, sword_length, parent_scale, WARRIOR_SWORD_FLIP)
	if sword == null and game_manager and game_manager.has_method("make_weapon"):
		var names: Array = ["Katana", "Sword", "ShortSword"]
		sword = game_manager.make_weapon([names[weapon_index % names.size()]], sword_length, parent_scale)
	if sword == null:
		sword = build_sword()
		sword.scale = Vector3.ONE / maxf(parent_scale, 0.0001)
	return sword

func is_right_hand_bone(l: String) -> bool:
	if not (l.contains("hand") or l.contains("palm")):
		return false
	for bad in ["thumb", "index", "middle", "ring", "pinky", "finger"]:
		if l.contains(bad):
			return false
	if l.contains("right"):
		return true
	var tokens: PackedStringArray = l.replace(".", "_").replace(":", "_").replace("-", "_").split("_")
	return tokens.has("r")

# Dayein haath ki haddi par talwar lagao (haddi na mile to false)
func attach_sword_to_hand(model: Node) -> bool:
	var skels: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return false
	var skel := skels[0] as Skeleton3D
	var bone_name: String = ""
	for i in range(skel.get_bone_count()):
		var bn: String = skel.get_bone_name(i)
		if is_right_hand_bone(bn.to_lower()):
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
	sword_node = make_sword(sc)
	grip.add_child(sword_node)
	return true

# Talwar haath ki jagah ek pivot par lagti hai (rig me ye pivot hilte haath ke saath chalta hai)
func attach_static_weapon(model: Node3D) -> void:
	var s: float = model_height / 1.9
	var hand: Vector3 = Vector3(0.45 * s, 0.95 * s, -0.05 * s)
	if rig_hand != Vector3.ZERO:
		hand = t_mv * rig_hand            # rig ka haath (model space -> visual space)
	else:
		var found: Vector3 = find_right_hand_pos(model)   # visual space
		if found != Vector3.ZERO:
			hand = found
	weapon_pivot = Node3D.new()
	weapon_pivot.position = hand
	visual.add_child(weapon_pivot)
	var tilt := Node3D.new()
	tilt.rotation_degrees = STATIC_SWORD_TILT
	weapon_pivot.add_child(tilt)
	sword_node = make_sword(1.0)
	tilt.add_child(sword_node)

# Rig na ho to purana tareeka: sharir ke dayein kinare ke jaalon ka beech (visual space)
func find_right_hand_pos(model: Node3D) -> Vector3:
	var to_local: Transform3D = visual.global_transform.affine_inverse()
	var verts := PackedVector3Array()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D = to_local * mi.global_transform
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var step: int = maxi(1, int(faces.size() / 6000.0))
		var i: int = 0
		while i < faces.size():
			verts.append(xf * faces[i])
			i += step
	if verts.size() < 30:
		return Vector3.ZERO
	var max_x: float = verts[0].x
	var min_x: float = verts[0].x
	for v in verts:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
	var width: float = max_x - min_x
	var sum := Vector3.ZERO
	var n: int = 0
	for v in verts:
		if v.x >= max_x - width * 0.04:
			sum += v
			n += 1
	if n == 0:
		return Vector3.ZERO
	return (sum / float(n))

# Talwar ke beech ka sthan (chingaari wahin se nikalti hai)
func get_sword_mid() -> Vector3:
	if sword_node and is_instance_valid(sword_node):
		var ref := sword_node.get_parent() as Node3D
		if ref:
			return ref.global_position + ref.global_transform.basis.y.normalized() * (sword_length * 0.5)
	return global_position + Vector3(0, model_height * 0.65, 0)

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

func build_steel() -> StandardMaterial3D:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.82, 0.88)
	steel.roughness = 0.3
	return steel

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
		sword_node = sword

	visual.scale = Vector3.ONE * (model_height / 1.85)

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
			anim_player.speed_scale = a.length / (windup_cur + strike_time)
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
	if using_model and rig_ok:
		animate_rig(delta, speed)
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
	if parry_time > 0.0:
		arm_target = -1.4
	else:
		match state:
			State.WINDUP:
				arm_target = lerpf(-0.55, -2.9, clampf(state_time / windup_cur, 0.0, 1.0))
			State.STRIKE:
				arm_target = lerpf(-2.9, -0.15, clampf(state_time / strike_time, 0.0, 1.0))
			State.RECOVER:
				arm_target = lerpf(-0.15, -0.55, clampf(state_time / recover_time, 0.0, 1.0))
	arm_r.rotation.x = arm_target
	visual.rotation.x = 0.2 if state == State.HURT else 0.0
	visual.position.y = absf(sin(walk_phase)) * 0.05 * amp

func rig_set(pname: String, value) -> void:
	for m in rig_mats:
		(m as ShaderMaterial).set_shader_parameter(pname, value)

func torso_xf_v(p: Vector3, twist: float, lean: float) -> Vector3:
	var q: Vector3 = p - rig_piv_hip
	var c: float = cos(twist)
	var sn: float = sin(twist)
	q = Vector3(q.x * c + q.z * sn, q.y, -q.x * sn + q.z * c)
	q = rotx_v(q, lean)
	return rig_piv_hip + q

# Code wala "auto-rig": chalna (jaangh + ghutna), dhad ka ghumav, kohni, talwar/bhale ki chaal
func animate_rig(delta: float, speed: float) -> void:
	walk_phase += speed * delta * 2.8
	var amp: float = clampf(speed / 3.2, 0.0, 1.0)
	var ph: float = walk_phase
	var t_now: float = Time.get_ticks_msec() / 1000.0
	var breathe: float = sin(t_now * 1.6) * 0.025

	# Chalna: jaangh aage-peeche, ghutna swing ke samay mudta hai
	var leg_p: float = -0.65 * sin(ph) * amp
	var leg_n: float = 0.65 * sin(ph) * amp
	var knee_p: float = 0.9 * maxf(0.0, cos(ph)) * amp
	var knee_n: float = 0.9 * maxf(0.0, -cos(ph)) * amp
	# Haath pair ke ulte
	var arm_n: float = -0.5 * sin(ph) * amp + breathe
	var arm_p: float = 0.5 * sin(ph) * amp - breathe
	var elb_n: float = -0.28 - 0.1 * amp
	var elb_p: float = -0.28 - 0.1 * amp
	var off_n := Vector3.ZERO
	var off_p := Vector3.ZERO
	var twist: float = 0.06 * sin(ph) * amp
	var lean: float = -0.05 * amp
	var px: float = 0.0
	var pz: float = 0.0

	if role == "guard":
		arm_n = 0.06 * sin(ph) * amp
		arm_p = 0.0
		var fwd: float = 0.1 if shield_hp > 0 else -0.1
		var up: float = 0.0 if shield_hp > 0 else -0.35
		off_p = Vector3(0.0, up + shield_pop * 0.12, fwd + shield_pop * 0.9)
		arm_p = -0.5 * (shield_pop / 0.25) if shield_hp > 0 else 0.4
	match state:
		State.WINDUP:
			var k: float = clampf(state_time / windup_cur, 0.0, 1.0)
			twist = lerpf(0.06 * sin(ph) * amp, -0.35, k)
			lean = lerpf(lean, 0.12, k)
			leg_p = lerpf(leg_p, 0.25, k)
			leg_n = lerpf(leg_n, -0.2, k)
			if role == "guard":
				arm_n = lerpf(0.0, -0.3, k)
				off_n = Vector3(0.0, 0.0, -0.35 * k)
			else:
				arm_n = lerpf(arm_n, 2.4, k)
				elb_n = lerpf(elb_n, -1.3, k)
				arm_p = lerpf(arm_p, -0.6, k)
				px = lerpf(0.0, 85.0, k)
		State.STRIKE:
			var k2: float = clampf(state_time / strike_time, 0.0, 1.0)
			twist = lerpf(-0.35, 0.45, k2)
			lean = lerpf(0.12, -0.22, k2)
			leg_p = lerpf(0.25, -0.5, k2)
			leg_n = lerpf(-0.2, 0.3, k2)
			knee_p = lerpf(0.0, 0.35, k2)
			if role == "guard":
				arm_n = lerpf(-0.3, 0.9, k2)
				off_n = Vector3(0.0, 0.0, lerpf(-0.35, 1.0, k2))
			else:
				arm_n = lerpf(2.4, -0.7, k2)
				elb_n = lerpf(-1.3, -0.2, k2)
				arm_p = lerpf(-0.6, 0.5, k2)
				px = lerpf(85.0, -55.0, k2)
		State.RECOVER:
			var k3: float = clampf(state_time / recover_time, 0.0, 1.0)
			twist = lerpf(0.45, 0.0, k3)
			lean = lerpf(-0.22, 0.0, k3)
			leg_p = lerpf(-0.5, 0.0, k3)
			leg_n = lerpf(0.3, 0.0, k3)
			if role == "guard":
				arm_n = lerpf(0.9, 0.0, k3)
				off_n = Vector3(0.0, 0.0, lerpf(1.0, 0.0, k3))
			else:
				arm_n = lerpf(-0.7, 0.0, k3)
				elb_n = lerpf(-0.2, -0.28, k3)
				arm_p = lerpf(0.5, 0.0, k3)
				px = lerpf(-55.0, 0.0, k3)
		State.HURT:
			lean = 0.25
			arm_n = 0.3
			arm_p = 0.3
	if parry_time > 0.0 and role != "guard":
		arm_n = -1.0          # takrav: talwar wala haath aage-upar aakar rokta hai
		elb_n = -1.2
		twist = 0.1
		px = 40.0
		pz = -30.0

	# Sab surfaces par pose bhejo
	rig_set("leg_neg", leg_n)
	rig_set("leg_pos", leg_p)
	rig_set("knee_neg", knee_n)
	rig_set("knee_pos", knee_p)
	rig_set("twist", twist)
	rig_set("lean", lean)
	rig_set("elbow_neg", elb_n)
	rig_set("elbow_pos", elb_p)
	rig_set("arm_neg", Vector4(arm_n, off_n.x, off_n.y, off_n.z))
	rig_set("arm_pos", Vector4(arm_p, off_p.x, off_p.y, off_p.z))

	visual.position.y = absf(sin(ph)) * 0.04 * amp
	visual.position.z = lerpf(visual.position.z, 0.0, clampf(10.0 * delta, 0.0, 1.0))

	# Talwar uske haath ke saath chalti hai (kandha -> kohni -> haath)
	if weapon_pivot:
		var sh: Vector3 = torso_xf_v(rig_shoulder_neg, twist, lean)
		var el: Vector3 = sh + rotx_v(torso_xf_v(rig_elbow_neg, twist, lean) - sh, arm_n) + off_n
		var ha: Vector3 = sh + rotx_v(torso_xf_v(rig_hand, twist, lean) - sh, arm_n) + off_n
		var hb: Vector3 = el + rotx_v(ha - el, elb_n)
		weapon_pivot.position = t_mv * hb
		var f: float = clampf(16.0 * delta, 0.0, 1.0)
		weapon_pivot.rotation_degrees.x = lerpf(weapon_pivot.rotation_degrees.x, px, f)
		weapon_pivot.rotation_degrees.z = lerpf(weapon_pivot.rotation_degrees.z, pz, f)

# Animation-rahit model (khadi mudra): halka hilna-dulna, vaar par lunge aur talwar/bhala ki chaal
func animate_static(delta: float, speed: float) -> void:
	walk_phase += speed * delta * 3.0
	var amp: float = clampf(speed / 3.0, 0.0, 1.0)
	var rot: float = 0.0          # sharir aage nahi jhukta (sirf vaar ke samay thoda)
	var zoff: float = 0.0
	var px: float = 0.0           # talwar ka pivot (degree)
	var pz: float = 0.0
	var thrust: float = 0.0       # bhala aage/peeche (meter)
	match state:
		State.WINDUP:
			var k: float = clampf(state_time / windup_cur, 0.0, 1.0)
			rot = 0.10 * k
			zoff = 0.10 * k
			px = lerpf(0.0, 85.0, k)
			thrust = lerpf(0.0, -0.35, k)
		State.STRIKE:
			var k2: float = clampf(state_time / strike_time, 0.0, 1.0)
			rot = lerpf(0.10, -0.15, k2)
			zoff = lerpf(0.10, -0.45, k2)
			px = lerpf(85.0, -55.0, k2)
			thrust = lerpf(-0.35, 1.0, k2)
		State.RECOVER:
			var k3: float = clampf(state_time / recover_time, 0.0, 1.0)
			rot = lerpf(-0.15, 0.0, k3)
			zoff = lerpf(-0.45, 0.0, k3)
			px = lerpf(-55.0, 0.0, k3)
			thrust = lerpf(1.0, 0.0, k3)
		State.HURT:
			rot = 0.20
	if parry_time > 0.0:
		px = 40.0   # takrav: talwar aage aakar rokti hai
		pz = -30.0
	var f: float = clampf(16.0 * delta, 0.0, 1.0)
	visual.rotation.x = lerpf(visual.rotation.x, rot, f)
	visual.rotation.z = sin(walk_phase) * 0.05 * amp
	visual.position.z = lerpf(visual.position.z, zoff, f)
	visual.position.y = absf(sin(walk_phase)) * 0.08 * amp
	if weapon_pivot:
		weapon_pivot.rotation_degrees.x = lerpf(weapon_pivot.rotation_degrees.x, px, f)
		weapon_pivot.rotation_degrees.z = lerpf(weapon_pivot.rotation_degrees.z, pz, f)
	if spear_node:
		offset_node(spear_node, spear_rest, thrust, 0.0)
	if shield_node:
		var up: float = 0.0
		var fwd: float = 0.1 if shield_hp > 0 else -0.1
		if shield_hp <= 0:
			up = -0.35
		fwd += shield_pop * 0.8
		offset_node(shield_node, shield_rest, fwd, up)

# Node ko visual ke hisaab se aage (meter) aur upar (meter) khiskao
func offset_node(n: Node3D, rest: Vector3, fwd_dist: float, up_dist: float) -> void:
	var par := n.get_parent() as Node3D
	if par == null:
		return
	var inv: Basis = par.global_transform.basis.inverse()
	var fwd: Vector3 = (inv * (visual.global_transform.basis * Vector3(0, 0, -1))).normalized()
	var up: Vector3 = (inv * Vector3.UP).normalized()
	var sp: float = maxf(par.global_transform.basis.get_scale().x, 0.0001)
	n.position = rest + fwd * (fwd_dist / sp) + up * (up_dist / sp)

# ---------------- AI ----------------
func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	hit_done = false
	match s:
		State.WINDUP:
			windup_cur = windup_time * randf_range(0.85, 1.25)   # har baar thoda alag samay (random)
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
	parry_time = maxf(0.0, parry_time - delta)
	shield_pop = maxf(0.0, shield_pop - delta)
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
				if invulnerable:
					_face(dir, delta)   # boss rakshakon ke peeche khada khilaadi ko dekhta rehta hai
			if dist < aggro_range and not invulnerable:
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
			if state_time >= windup_cur:
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
				_set_state(State.CHASE if (dist < aggro_range * 2.2 and not invulnerable) else State.GUARD)
		State.HURT:
			_stop(delta)
			if state_time >= 0.4:
				_set_state(State.CHASE if not invulnerable else State.GUARD)

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
		# Khilaadi ki talwar bhi ghoom rahi ho to aksar takrav (random): kisi ko chot nahi
		if player and player.has_method("is_swinging") and player.is_swinging() and randf() < 0.75:
			on_clash(player.global_position)
			if player.has_method("nudge"):
				player.nudge(dir, 4.0)
			return
		if player and player.has_method("take_damage"):
			player.take_damage(damage, global_position)
			sfx_variant("res://audio/sword_hit", "hit")

# ---------------- Takrav, dhaal, damage, maut ----------------
# Dono talwarein takrati dikhti hain: dushman ki talwar aage aakar rokti hai, beech me chingaari udti hai
func on_clash(other_pos: Vector3) -> void:
	if state == State.DEAD:
		return
	var away: Vector3 = global_position - other_pos
	away.y = 0.0
	if away.length() > 0.01:
		away = away.normalized()
	parry_time = 0.45
	spawn_sparks(get_sword_mid())
	if role == "guard":
		shield_pop = 0.25
		sfx_variant("res://audio/shield_clash", "shield")
	else:
		sfx_variant("res://audio/sword_clash", "clash")
	if player and player.has_method("clash_visual"):
		player.clash_visual()
	velocity += away * 4.0
	_set_state(State.RECOVER)
	state_time = -0.35   # takrane ke baad thodi der ladkhadate hain

# 0 = chot lagi, 1 = takrav / dhaal / kavach (chot nahi lagi)
func take_hit(amount: int, from_pos: Vector3) -> int:
	if state == State.DEAD:
		return 1
	if invulnerable:
		spawn_sparks(get_sword_mid())
		sfx_variant("res://audio/sword_clash", "clash")
		if player and player.has_method("clash_visual"):
			player.clash_visual()
		blocked.emit(self)
		return 1
	var to_att: Vector3 = from_pos - global_position
	to_att.y = 0.0
	if to_att.length() > 0.01:
		to_att = to_att.normalized()

	# Dushman ki talwar/bhala chal raha ho to aksar takrav (random)
	if (state == State.WINDUP or state == State.STRIKE) and randf() < 0.8:
		on_clash(from_pos)
		if player and player.has_method("nudge"):
			player.nudge(to_att, 4.0)
		return 1

	# Dushman kabhi-kabhi khud talwar utha kar vaar rok leta hai (random parry)
	if not has_shield and state != State.HURT and randf() < parry_chance:
		on_clash(from_pos)
		if player and player.has_method("nudge"):
			player.nudge(to_att, 4.0)
		return 1

	# Dhaal: saamne se vaar rok leti hai (3 vaar me toot jati hai)
	if has_shield and shield_hp > 0 and (-global_transform.basis.z).dot(to_att) > 0.25:
		shield_hp -= 1
		shield_pop = 0.25
		spawn_sparks(global_position + Vector3(0, model_height * 0.65, 0) + to_att * 0.6)
		sfx_variant("res://audio/shield_clash", "shield")
		if player and player.has_method("clash_visual"):
			player.clash_visual()
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

# Khilaadi ke girne par dushman apni jagah laut jate hain
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
	spark.size = Vector3(0.03, 0.03, 0.14)
	spark.material = mat

	var p := CPUParticles3D.new()
	p.mesh = spark
	p.amount = 40
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -9.0, 0)
	get_parent().add_child(p)
	p.global_position = pos
	p.emitting = true

	# Takrav ki ek chhoti sunehri roshni
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.45)
	flash.light_energy = 3.0
	flash.omni_range = 6.0
	get_parent().add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.2)
	tw.tween_callback(flash.queue_free)
	get_tree().create_timer(0.9).timeout.connect(p.queue_free)

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
