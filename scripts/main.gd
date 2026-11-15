extends Node3D
## Simulación de un viaje a la Luna en 8 etapas, cada una con sus cámaras,
## y un recuadro chico con el astronauta dentro de la cabina.
## Teclas: Espacio = pausa · flechas = etapa anterior / siguiente · 1 a 8 = ir a una etapa · H = ocultar textos

const SLS := "res://models/artemis_ii_-_space_launch_system_sls.glb"
const ORION := "res://models/agentic_0007_pack_glb_model.glb"
const EARTH := "res://models/tierra_v1.1.glb"
const MOON := "res://models/la_luna__viaje_virtual_guiado__3d___vr.glb"
const ASTRO := "res://models/astronautin.glb"
const ASTRO_SCRIPT := preload("res://scripts/astronaut.gd")

## Estado que manda la app (Firebase Realtime Database).
const FIREBASE_URL := "https://thedox-spacehealth-default-rtdb.firebaseio.com/simulation_controls/active_scenario.json"
const FIREBASE_EVERY := 1.0   # cada cuántos segundos pregunta
## Si la app manda una emergencia, se muestra este texto en vez del de la etapa.
const REMOTE_FEEL := {
	"warning": "Alerta enviada desde la app: la tripulación revisa los sistemas y se ajusta los cinturones.",
	"solarFlare": "Tormenta solar: la radiación sube de golpe. Qué hacer: refugiarse entre las bolsas de carga.",
	"hypoxia": "Baja el oxígeno: mareo y visión borrosa. Qué hacer: máscara de oxígeno y cerrar la fuga.",
}

const GREEN := Color("4ade80")
const YELLOW := Color("facc15")
const RED := Color("f87171")
const DIM := Color(0.62, 0.69, 0.78)
const FEED_W := 250.0
const FEED_H := 206.0
const SUN_LAUNCH := Vector3(0.35, 0.85, 0.4)
const SUN_SPACE := Vector3(0.55, 0.3, 0.78)

# dur = segundos en pantalla · t0/t1 = reloj simulado de la misión (segundos desde el despegue)
const STAGES := [
	{"name": "DESPEGUE", "dur": 36.0, "t0": 0.0, "t1": 486.0, "dist": "ALTITUD"},
	{"name": "SEPARACIÓN", "dur": 18.0, "t0": 486.0, "t1": 520.0, "dist": "ALTITUD"},
	{"name": "ÓRBITA TERRESTRE", "dur": 40.0, "t0": 1200.0, "t1": 6477.0, "dist": "ALTITUD"},
	{"name": "CINTURONES DE VAN ALLEN", "dur": 26.0, "t0": 6477.0, "t1": 24000.0, "dist": "ALTITUD"},
	{"name": "RUMBO A LA LUNA", "dur": 36.0, "t0": 91800.0, "t1": 259200.0, "dist": "DISTANCIA A LA TIERRA"},
	{"name": "TORMENTA SOLAR", "dur": 26.0, "t0": 259200.0, "t1": 266400.0, "dist": "DISTANCIA A LA TIERRA"},
	{"name": "FUGA DE OXÍGENO", "dur": 26.0, "t0": 345600.0, "t1": 347400.0, "dist": "DISTANCIA A LA TIERRA"},
	{"name": "ESTABILIZADO · LA LUNA", "dur": 32.0, "t0": 436980.0, "t1": 437160.0, "dist": "DISTANCIA A LA TIERRA"},
]

const SKY_SHADER := """
shader_type sky;
uniform float atmo = 0.0;
uniform float flare = 0.0;
uniform float tm = 0.0;
uniform vec3 sun_dir = vec3(0.55, 0.3, 0.78);
float h(vec3 p){ p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
vec3 stars(vec3 e, float dens, float scale, float bright){
	vec3 d = e * scale;
	vec3 c = floor(d);
	float r = h(c);
	float s = step(dens, r) * smoothstep(0.45, 0.0, length(fract(d) - 0.5));
	float tw = 0.75 + 0.25 * sin(tm * 2.0 + r * 40.0);
	vec3 tint = mix(vec3(0.75, 0.84, 1.0), vec3(1.0, 0.88, 0.72), h(c + 7.0));
	return tint * s * (0.45 + 0.9 * h(c + 3.0)) * tw * bright;
}
void sky(){
	vec3 e = normalize(EYEDIR);
	vec3 col = stars(EYEDIR, 0.988, 260.0, 1.0) + stars(EYEDIR, 0.9955, 90.0, 1.5);
	float band = pow(max(1.0 - abs(e.y * 2.4 + 0.3), 0.0), 3.0);
	col += vec3(0.05, 0.055, 0.085) * band;
	float sd = max(dot(e, normalize(sun_dir)), 0.0);
	float disc = smoothstep(0.9992, 0.9997, sd);
	float glow = pow(sd, 300.0) * 0.9 + pow(sd, 24.0) * (0.12 + 0.9 * flare) + pow(sd, 3.0) * 0.4 * flare;
	vec3 ax = normalize(cross(normalize(sun_dir), vec3(0.0, 1.0, 0.0)));
	float streak = pow(max(1.0 - abs(dot(e - normalize(sun_dir), ax)) * 7.0, 0.0), 2.5) * pow(sd, 2.0);
	col += vec3(1.0, 0.96, 0.88) * disc * 4.0 + vec3(1.0, 0.72, 0.42) * glow;
	col += vec3(1.0, 0.85, 0.6) * streak * (0.25 + 1.4 * flare);
	vec3 blue = mix(vec3(0.72, 0.85, 0.98), vec3(0.13, 0.38, 0.85), clamp(e.y * 1.1 + 0.25, 0.0, 1.0));
	blue += vec3(1.0, 0.95, 0.85) * (disc + pow(sd, 40.0) * 0.5);
	COLOR = mix(col, blue, atmo);
}
"""

## Halo de aire alrededor de la Tierra: brilla solo en el borde iluminado por el Sol.
const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never;
uniform vec3 sun = vec3(0.55, 0.3, 0.78);
uniform vec4 col : source_color = vec4(0.35, 0.62, 1.0, 1.0);
varying vec3 wn;
void vertex(){ wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment(){
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	float lit = clamp(dot(wn, normalize(sun)) * 1.3 + 0.22, 0.0, 1.0);
	ALBEDO = col.rgb;
	ALPHA = rim * lit * col.a;
}
"""

const VIGNETTE_SHADER := """
shader_type canvas_item;
void fragment(){
	float v = smoothstep(0.40, 0.98, length(SCREEN_UV - vec2(0.5)) * 1.38);
	COLOR = vec4(0.0, 0.0, 0.0, v * 0.5);
}
"""

const BELT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 col : source_color = vec4(0.5, 0.4, 1.0, 0.4);
void fragment(){
	ALBEDO = col.rgb;
	ALPHA = pow(abs(dot(NORMAL, VIEW)), 2.0) * col.a;
}
"""

# --- Mundo ---
var env: Environment
var sky_mat: ShaderMaterial
var halo_mat: ShaderMaterial
var sun: DirectionalLight3D
var earth: Node3D
var moon: Node3D
var ship: Node3D
var sls: Node3D
var orion: Node3D
var orion_anim: AnimationPlayer
var upper: Node3D           # etapa superior: sube la órbita y después se suelta
var upper_z := 0.0          # dónde va pegada, detrás de la cápsula
var belts: Node3D
var cam: Camera3D
var fx_light: OmniLight3D
var soft_tex: GradientTexture2D
var p_flame: CPUParticles3D
var p_smoke: CPUParticles3D
var p_air: CPUParticles3D
var p_oflame: CPUParticles3D
var p_uflame: CPUParticles3D
var p_belt: CPUParticles3D
var p_speed: CPUParticles3D
var p_storm: CPUParticles3D
var p_leak: CPUParticles3D
var fx_all: Array[CPUParticles3D] = []

# --- Cabina y textos ---
var astro: Node3D
var cab_cam: Camera3D
var cab_base: Vector3
var alarm: OmniLight3D
var hud: Control
var lbl := {}
var bar_fill: ColorRect
var live_dot: ColorRect
var brackets: Array[ColorRect] = []
var fade: ColorRect
var flash: ColorRect

# --- Estado ---
var stage := 0
var t_stage := 0.0
var prev_u := 0.0
var clock := 0.0
var playing := true
var scenario := "normal"
var remote := ""        # emergencia que manda la app ("" = la simulación decide sola)
var fb_req: HTTPRequest
var fb_busy := false
var tel_g := 1.0        # fuerza G
var tel_v := 0.0        # velocidad en km/h
var tel_d := 0.0        # altitud o distancia a la Tierra en km
var feel := ""          # qué siente el cuerpo y qué hacer
var cam_shake := 0.0
var cab_shake := 0.0
var fade_a := 1.0
var flash_a := 0.0

func _ready() -> void:
	_build_world()
	_build_fx()
	_build_hud()
	_enter(0)
	if FileAccess.file_exists("res://_pruebas/snap.flag"):
		_snapshots()
	if FileAccess.file_exists("res://_pruebas/fps.flag"):
		_fps_test()
	_start_firebase()

# =====================================================================
#  CONSTRUCCIÓN
# =====================================================================
func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = _mesh_xf(m) * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## Dónde se dibuja de verdad una malla. Las mallas con esqueleto (como la cápsula)
## no se dibujan donde está su nodo, sino donde las pone el esqueleto.
func _mesh_xf(m: MeshInstance3D) -> Transform3D:
	var sk := m.get_node_or_null(m.skeleton) as Skeleton3D
	if m.skin == null or sk == null or m.skin.get_bind_count() == 0:
		return m.global_transform
	var bone := m.skin.get_bind_bone(0)
	if bone < 0:
		bone = sk.find_bone(m.skin.get_bind_name(0))
	if bone < 0:
		return m.global_transform
	return sk.global_transform * sk.get_bone_global_pose(bone) * m.skin.get_bind_pose(0)

## Carga un modelo, lo centra y lo deja de tamaño 'size' (su lado más largo).
func _place(path: String, parent: Node3D, size: float) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	var model: Node3D = load(path).instantiate()
	pivot.add_child(model)
	var b := _aabb(model)
	model.scale *= size / maxf(b.size.x, maxf(b.size.y, b.size.z))
	model.position -= _aabb(model).get_center()
	return pivot

func _build_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 2.2
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.0
	for i in [1, 2, 3, 4]:
		env.set_glow_level(i, 1.0 if i < 4 else 0.6)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	add_child(sun)

	earth = _place(EARTH, self, 1.0)
	var halo := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.57
	sm.height = 1.14
	sm.radial_segments = 32
	sm.rings = 16
	halo.mesh = sm
	halo_mat = ShaderMaterial.new()
	var hsh := Shader.new()
	hsh.code = HALO_SHADER
	halo_mat.shader = hsh
	halo.material_override = halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	earth.add_child(halo)
	moon = _place(MOON, self, 1.0)
	ship = Node3D.new()
	add_child(ship)
	sls = _place(SLS, ship, 12.0)          # el modelo viene con la punta hacia arriba
	sls.rotation_degrees.x = -90.0         # -> punta hacia adelante (-Z)
	orion = _place(ORION, ship, 3.0)       # el modelo viene con la punta hacia +Z
	orion.rotation_degrees.y = 180.0       # -> punta hacia adelante (-Z)
	for ap in orion.find_children("*", "AnimationPlayer", true, false):
		orion_anim = ap
	_build_upper()

	belts = Node3D.new()
	add_child(belts)
	_belt(23.0, 41.0, Color(0.6, 0.4, 1.0, 0.13))
	_belt(48.0, 92.0, Color(0.3, 0.9, 0.75, 0.09))

	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	var fill := OmniLight3D.new()          # luz suave pegada a la cámara: la nave nunca queda negra
	fill.omni_range = 60.0
	fill.light_energy = 0.8
	cam.add_child(fill)
	fx_light = OmniLight3D.new()
	fx_light.omni_range = 14.0
	fx_light.light_energy = 0.0
	ship.add_child(fx_light)
	fx_light.position = Vector3(1.5, 1.5, 1.0)

## Etapa superior: un cilindro con tobera, pegado detrás de la cápsula.
func _build_upper() -> void:
	upper = Node3D.new()
	ship.add_child(upper)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.42
	cyl.height = 2.0
	body.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.66, 0.66, 0.64)
	m.roughness = 0.85
	body.material_override = m
	body.rotation_degrees.x = 90.0           # el cilindro queda acostado a lo largo de Z
	upper.add_child(body)
	var ring := MeshInstance3D.new()        # franja oscura para que se lea la forma
	var rc := CylinderMesh.new()
	rc.top_radius = 0.43
	rc.bottom_radius = 0.43
	rc.height = 0.18
	ring.mesh = rc
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.25, 0.26, 0.28)
	rm.roughness = 0.7
	ring.material_override = rm
	ring.rotation_degrees.x = 90.0
	ring.position.z = -0.8
	upper.add_child(ring)
	var noz := MeshInstance3D.new()
	var nc := CylinderMesh.new()
	nc.top_radius = 0.1
	nc.bottom_radius = 0.28
	nc.height = 0.5
	noz.mesh = nc
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(0.32, 0.3, 0.3)
	nm.metallic = 0.8
	nm.roughness = 0.35
	noz.material_override = nm
	noz.rotation_degrees.x = 90.0
	noz.position.z = 1.25
	upper.add_child(noz)
	upper_z = _aabb(orion).end.z + 0.88     # pegada a la cápsula, tapando su motor
	upper.position.z = upper_z

func _belt(r_in: float, r_out: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	mi.mesh = tm
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BELT_SHADER
	m.shader = sh
	m.set_shader_parameter("col", c)
	mi.material_override = m
	belts.add_child(mi)

func _grad(cols: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cs := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / float(cols.size() - 1))
		cs.append(cols[i])
	g.offsets = offs
	g.colors = cs
	return g

## Efecto de partículas (fuego, humo, gas, radiación). No son modelos: son puntos de luz.
func _fx(parent: Node3D, pos: Vector3, amount: int, life: float, size: float, cols: Array,
		dir: Vector3, spread: float, vmin: float, vmax: float, box := Vector3.ZERO, grow := 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_tex
	q.material = m
	p.mesh = q
	p.direction = dir.normalized()
	p.spread = spread
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.color_ramp = _grad(cols)
	if box != Vector3.ZERO:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = box
	if grow != 1.0:
		var cv := Curve.new()
		cv.max_value = grow
		cv.add_point(Vector2(0.0, 1.0))
		cv.add_point(Vector2(1.0, grow))
		p.scale_amount_curve = cv
	parent.add_child(p)
	p.position = pos
	fx_all.append(p)
	return p

func _build_fx() -> void:
	soft_tex = GradientTexture2D.new()
	soft_tex.width = 64
	soft_tex.height = 64
	soft_tex.fill = GradientTexture2D.FILL_RADIAL
	soft_tex.fill_from = Vector2(0.5, 0.5)
	soft_tex.fill_to = Vector2(1.0, 0.5)
	soft_tex.gradient = _grad([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	var back := Vector3(0, 0, 1)   # hacia atrás de la nave
	# Cohete SLS: fuego y estela
	p_flame = _fx(ship, Vector3(0, 0, 6.4), 260, 0.55, 1.7,
		[Color(1, 0.97, 0.8, 1), Color(1, 0.6, 0.15, 0.9), Color(0.7, 0.25, 0.05, 0)], back, 5.0, 30.0, 44.0, Vector3(1.0, 0.3, 0.1))
	p_smoke = _fx(ship, Vector3(0, 0, 8.0), 220, 2.6, 3.0,
		[Color(1, 0.8, 0.55, 0.3), Color(0.8, 0.8, 0.84, 0.2), Color(0.6, 0.6, 0.66, 0)], back, 3.0, 26.0, 34.0, Vector3(1.0, 0.3, 0.1), 2.6)
	# Aire que pasa a los costados mientras sube por la atmósfera
	p_air = _fx(ship, Vector3(0, 0, -18.0), 150, 0.45, 0.16,
		[Color(1, 1, 1, 0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)], back, 1.0, 70.0, 95.0, Vector3(9, 9, 2))
	# Motor de la cápsula
	p_oflame = _fx(ship, Vector3(0, 0, 0.85), 120, 0.2, 0.3,
		[Color(0.85, 0.93, 1, 1), Color(0.4, 0.6, 1, 0.8), Color(0.2, 0.3, 1, 0)], back, 3.0, 10.0, 14.0)
	# Motor de la etapa superior
	p_uflame = _fx(upper, Vector3(0, 0, 1.6), 140, 0.35, 0.5,
		[Color(1, 0.95, 0.8, 1), Color(1, 0.65, 0.3, 0.8), Color(0.6, 0.3, 0.1, 0)], back, 4.0, 12.0, 18.0)
	# Partículas de radiación de los cinturones
	p_belt = _fx(ship, Vector3(0, 0, -5.0), 240, 1.2, 0.16,
		[Color(0.7, 0.5, 1, 0), Color(0.6, 0.9, 1, 0.9), Color(0.7, 0.4, 1, 0)], Vector3(0.3, 0.1, 1), 8.0, 10.0, 18.0, Vector3(7, 5, 7))
	# Estrellas que pasan rápido (sensación de velocidad)
	p_speed = _fx(ship, Vector3(0, 0, -45.0), 140, 0.9, 0.12,
		[Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)], back, 0.5, 70.0, 110.0, Vector3(14, 9, 3))
	# Tormenta solar: partículas que llegan desde el Sol
	var s := SUN_SPACE.normalized()
	p_storm = _fx(self, s * 45.0, 420, 1.6, 0.22,
		[Color(1, 0.8, 0.4, 0), Color(1, 0.6, 0.2, 1), Color(1, 0.3, 0.1, 0)], -s, 6.0, 45.0, 70.0, Vector3(12, 12, 12))
	# Fuga de aire
	p_leak = _fx(ship, Vector3(0.5, 0.2, -0.45), 160, 1.2, 0.13,
		[Color(1, 1, 1, 0.7), Color(0.85, 0.92, 1, 0.3), Color(0.8, 0.9, 1, 0)], Vector3(1, 0.4, -0.2), 12.0, 2.5, 5.0, Vector3.ZERO, 2.4)

func _label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	parent.add_child(l)
	return l

## Tipografía: condensada para títulos y monoespaciada para los números,
## así las cifras no bailan al cambiar.
func _font(file: String, track := 0) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/" + file)
	if track != 0:
		fv.set_spacing(TextServer.SPACING_GLYPH, track)
	return fv

func _txt(parent: Node, font: FontVariation, size: int, color: Color, shadow := true) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 5)
	parent.add_child(l)
	return l

func _rule(parent: Node, w: float, h: float, c: Color, pos := Vector2.ZERO) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(w, h)
	r.size = Vector2(w, h)
	r.position = pos
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

func _build_hud() -> void:
	var fx_layer := CanvasLayer.new()
	add_child(fx_layer)
	var vig := ColorRect.new()
	var vm := ShaderMaterial.new()
	var vsh := Shader.new()
	vsh.code = VIGNETTE_SHADER
	vm.shader = vsh
	vig.material = vm
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(vig)
	flash = ColorRect.new()
	fade = ColorRect.new()
	for r in [flash, fade]:
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx_layer.add_child(r)
	fade.color = Color.BLACK
	flash.color = Color(1, 1, 1, 0)

	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	for up in [true, false]:
		var scrim := TextureRect.new()
		var gt := GradientTexture2D.new()
		gt.width = 8
		gt.height = 256
		gt.fill_from = Vector2(0, 1 if up else 0)
		gt.fill_to = Vector2(0, 0 if up else 1)
		gt.gradient = _grad([Color(0, 0, 0, 0), Color(0, 0, 0, 0.28), Color(0, 0, 0, 0.7)])
		scrim.texture = gt
		scrim.stretch_mode = TextureRect.STRETCH_SCALE
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scrim.set_anchors_preset(Control.PRESET_TOP_WIDE if up else Control.PRESET_BOTTOM_WIDE)
		scrim.offset_bottom = 150 if up else 0
		scrim.offset_top = 0 if up else -210
		hud.add_child(scrim)

	var f_title := _font("BarlowCondensed-SemiBold.ttf")
	var f_caps := _font("BarlowCondensed-Medium.ttf", 3)
	var f_body := _font("BarlowCondensed-Medium.ttf")
	var f_num := _font("Inconsolata-SemiBold.ttf", -1)

	# ---------- Arriba a la izquierda: misión, etapa y reloj ----------
	var top := Control.new()
	top.position = Vector2(34, 26)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	_rule(top, 26, 2, Color(0.95, 0.97, 1.0, 0.9), Vector2(0, 7))
	var mission := _txt(top, f_caps, 14, DIM)
	mission.text = "SIMULACIÓN   ·   VIAJE A LA LUNA"
	mission.position = Vector2(38, 0)
	lbl["title"] = _txt(top, f_title, 50, Color(0.97, 0.98, 1.0))
	lbl.title.position = Vector2(-3, 16)
	var meta := HBoxContainer.new()
	meta.position = Vector2(0, 74)
	meta.add_theme_constant_override("separation", 16)
	top.add_child(meta)
	lbl["stage"] = _txt(meta, f_num, 16, DIM)
	var sep := _txt(meta, f_num, 16, Color(1, 1, 1, 0.25))
	sep.text = "|"
	lbl["clock"] = _txt(meta, f_num, 16, Color(0.85, 0.89, 0.95))

	# ---------- Abajo a la izquierda: sensación del cuerpo + telemetría ----------
	var bl := VBoxContainer.new()
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.offset_left = 34
	bl.offset_bottom = -34
	bl.add_theme_constant_override("separation", 11)
	hud.add_child(bl)
	var feel_box := VBoxContainer.new()
	feel_box.add_theme_constant_override("separation", 3)
	bl.add_child(feel_box)
	var feel_cap := _txt(feel_box, f_caps, 11, DIM)
	feel_cap.text = "QUÉ SIENTE LA TRIPULACIÓN"
	var f := _txt(feel_box, f_body, 17, Color(0.96, 0.97, 1.0))
	f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	f.custom_minimum_size = Vector2(430, 0)
	lbl["feel"] = f
	_rule(bl, 430, 1, Color(1, 1, 1, 0.16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 38)
	bl.add_child(row)
	for k in ["g", "v", "d"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		lbl[k + "_cap"] = _txt(col, f_caps, 11, DIM)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 5)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		col.add_child(h)
		lbl[k] = _txt(h, f_num, 25, Color(0.97, 0.98, 1.0))
		lbl[k + "_u"] = _txt(h, f_body, 14, DIM)
		lbl[k + "_u"].vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lbl[k + "_u"].custom_minimum_size = Vector2(0, 31)
	lbl.g_cap.text = "FUERZA G"
	lbl.v_cap.text = "VELOCIDAD"
	lbl.g_u.text = "G"
	lbl.v_u.text = "km/h"
	lbl.d_u.text = "km"

	# ---------- Abajo a la derecha: cámara de cabina ----------
	var feed := Control.new()
	feed.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	feed.size = Vector2(FEED_W, FEED_H + 52)
	feed.offset_left = -FEED_W - 34
	feed.offset_top = -(FEED_H + 52) - 34
	feed.offset_right = -34
	feed.offset_bottom = -34
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(feed)
	live_dot = _rule(feed, 8, 8, RED, Vector2(0, 5))
	var cam_lbl := _txt(feed, f_caps, 12, DIM)
	cam_lbl.text = "CÁM 01   ·   CABINA"
	cam_lbl.position = Vector2(16, -3)
	var live := _txt(feed, f_caps, 12, Color(0.9, 0.3, 0.3))
	live.text = "EN VIVO"
	live.position = Vector2(FEED_W - 58, -3)
	_rule(feed, FEED_W, FEED_H, Color(0, 0, 0, 0.82), Vector2(0, 22))
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.position = Vector2(0, 22)
	svc.size = Vector2(FEED_W, FEED_H)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_child(svc)
	var sv := SubViewport.new()
	sv.size = Vector2i(FEED_W, FEED_H)
	sv.own_world_3d = true
	svc.add_child(sv)
	for c in [Vector2(0, 22), Vector2(FEED_W, 22), Vector2(0, 22 + FEED_H), Vector2(FEED_W, 22 + FEED_H)]:
		var sx: float = -1.0 if c.x > 0 else 1.0
		var sy: float = -1.0 if c.y > 30 else 1.0
		brackets.append(_rule(feed, 18, 2, Color.WHITE, c + Vector2(0 if sx > 0 else -18, 0 if sy > 0 else -2)))
		brackets.append(_rule(feed, 2, 18, Color.WHITE, c + Vector2(0 if sx > 0 else -2, 0 if sy > 0 else -18)))
	lbl["cab"] = _txt(feed, f_caps, 14, GREEN)
	lbl.cab.position = Vector2(0, FEED_H + 30)
	lbl.cab.size = Vector2(FEED_W, 20)
	lbl.cab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_cabin(sv)

	# ---------- Línea de avance, con una marca por etapa ----------
	var bar := Control.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -3
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bar)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(bg)
	bar_fill = ColorRect.new()
	bar_fill.color = Color(0.95, 0.97, 1.0, 0.9)
	bar_fill.anchor_bottom = 1.0
	bar.add_child(bar_fill)
	var total := 0.0
	for st in STAGES:
		total += st.dur
	var acc := 0.0
	for i in STAGES.size() - 1:
		acc += STAGES[i].dur
		var tick := ColorRect.new()
		tick.color = Color(0, 0, 0, 0.75)
		tick.anchor_left = acc / total
		tick.anchor_right = acc / total
		tick.anchor_bottom = 1.0
		tick.offset_right = 2
		bar.add_child(tick)

func _build_cabin(sv: SubViewport) -> void:
	var room := Node3D.new()
	sv.add_child(room)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.22, 0.25, 0.32)
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 2.0
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_hdr_threshold = 1.05
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = e
	room.add_child(we)
	sv.msaa_3d = Viewport.MSAA_4X
	var key := DirectionalLight3D.new()          # luz principal, cálida
	key.rotation_degrees = Vector3(-32, 28, 0)
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.95, 0.88)
	key.shadow_enabled = true
	room.add_child(key)
	var fill := DirectionalLight3D.new()         # relleno frío del otro lado
	fill.rotation_degrees = Vector3(-10, -65, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.68, 0.78, 1.0)
	room.add_child(fill)
	var rim := DirectionalLight3D.new()          # contraluz: dibuja el borde del traje
	rim.rotation_degrees = Vector3(-6, 168, 0)
	rim.light_energy = 2.2
	rim.light_color = Color(0.72, 0.85, 1.0)
	room.add_child(rim)
	alarm = OmniLight3D.new()
	alarm.position = Vector3(0, 2.4, 1.2)
	alarm.omni_range = 6.0
	alarm.light_color = RED
	alarm.light_energy = 0.0
	room.add_child(alarm)
	astro = Node3D.new()
	astro.set_script(ASTRO_SCRIPT)
	room.add_child(astro)
	var model: Node3D = load(ASTRO).instantiate()
	astro.add_child(model)
	astro.setup(model)
	astro.fit_height(model, 1.8)
	cab_cam = Camera3D.new()
	room.add_child(cab_cam)
	cab_base = Vector3(1.05, 1.25, 2.35)
	cab_cam.position = cab_base
	cab_cam.look_at(Vector3(0, 1.15, 0.18))
	cab_cam.fov = 40
	cab_cam.current = true

# =====================================================================
#  AYUDAS
# =====================================================================
func _sky(atmo: float, flare_amt: float) -> void:
	sky_mat.set_shader_parameter("atmo", atmo)
	sky_mat.set_shader_parameter("flare", flare_amt)
	env.ambient_light_color = Color(0.1, 0.11, 0.16).lerp(Color(0.5, 0.55, 0.65), atmo)

func _set_sun(dir: Vector3, energy: float, color: Color) -> void:
	sun.look_at_from_position(dir.normalized() * 100.0, Vector3.ZERO)
	sun.light_energy = energy
	sun.light_color = color
	sky_mat.set_shader_parameter("sun_dir", dir.normalized())
	halo_mat.set_shader_parameter("sun", dir.normalized())

func _cam(pos: Vector3, target: Vector3, fov: float) -> void:
	var j := Vector3(sin(clock * 47.3), sin(clock * 61.7 + 1.3), sin(clock * 53.1 + 2.1)) * cam_shake
	cam.position = pos + j
	var d := (target - cam.position).normalized()
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	cam.look_at(target + j * 0.5, up)
	cam.fov = fov

func _face(dir: Vector3) -> void:
	var up := Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	ship.look_at(ship.position + dir, up)

## Valor que cambia siguiendo una lista de puntos [avance, valor].
func _kf(u: float, k: Array) -> float:
	for i in range(k.size() - 1):
		var a: float = k[i][0]
		var b: float = k[i + 1][0]
		if u <= b:
			var va: float = k[i][1]
			var vb: float = k[i + 1][1]
			return lerpf(va, vb, clampf(inverse_lerp(a, b, u), 0.0, 1.0))
	var last: float = k[k.size() - 1][1]
	return last

func _bump(x: float, a: float, b: float) -> float:
	return clampf(1.0 - absf((x - (a + b) * 0.5) / ((b - a) * 0.5)), 0.0, 1.0)

func _fmt(v: float) -> String:
	var s := str(int(round(v)))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

func _orion_play(anim: String) -> void:
	if orion_anim and orion_anim.has_animation(anim):
		orion_anim.stop()
		orion_anim.play(anim)

## Cambia el escenario de salud (el mismo nombre que usa la app de Diego).
## AQUÍ se conectará Firebase: escribir simulation_controls/active_scenario.
func _scenario(s: String) -> void:
	if remote != "":        # lo que manda la app gana sobre la etapa
		s = remote
	if s == scenario:
		return
	scenario = s
	astro.state = s

# =====================================================================
#  FIREBASE: la app manda el estado y la simulación obedece
#  "normal" (o nada) = la simulación sigue su historia sola
#  "warning" / "solarFlare" / "hypoxia" = se fuerza ese estado
# =====================================================================
func _start_firebase() -> void:
	fb_req = HTTPRequest.new()
	fb_req.timeout = 5.0
	add_child(fb_req)
	fb_req.request_completed.connect(_on_firebase)
	var t := Timer.new()
	t.wait_time = FIREBASE_EVERY
	t.autostart = true
	t.timeout.connect(_poll_firebase)
	add_child(t)
	_poll_firebase()

func _poll_firebase() -> void:
	if fb_busy:             # todavía no respondió la pregunta anterior
		return
	if fb_req.request(FIREBASE_URL) == OK:
		fb_busy = true

func _on_firebase(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	fb_busy = false
	if code != 200:
		print("Firebase: sin respuesta (resultado %d, código %d)" % [_result, code])
		return              # sin internet o error: la simulación sigue sola
	var j = JSON.parse_string(body.get_string_from_utf8())
	var r: String = j if j is String and REMOTE_FEEL.has(j) else ""
	if r != remote:
		print("Firebase: la app manda '%s'" % (r if r != "" else "normal"))
	remote = r

# =====================================================================
#  ETAPAS
# =====================================================================
func _enter(i: int) -> void:
	stage = i
	t_stage = 0.0
	prev_u = 0.0
	fade_a = 1.0
	cam_shake = 0.0
	cab_shake = 0.0
	for p in fx_all:
		p.emitting = false
	belts.visible = false
	earth.visible = true
	moon.visible = true
	sls.visible = false
	sls.position = Vector3.ZERO
	sls.rotation_degrees = Vector3(-90, 0, 0)
	orion.visible = true
	upper.visible = false
	upper.position = Vector3(0, 0, upper_z)
	upper.rotation = Vector3.ZERO
	ship.position = Vector3.ZERO
	ship.rotation = Vector3.ZERO
	fx_light.light_energy = 0.0
	_sky(0.0, 0.0)
	_set_sun(SUN_SPACE, 2.0, Color.WHITE)
	earth.rotation_degrees = Vector3(15, 120, 0)
	match i:
		0, 1:
			_set_sun(SUN_LAUNCH, 2.2, Color.WHITE)
			earth.scale = Vector3.ONE * 300.0
			earth.position = Vector3(0, -375, 0)
			earth.rotation_degrees = Vector3(61.5, 0, 0)   # Florida mirando hacia arriba
			moon.visible = false
		2:
			earth.scale = Vector3.ONE * 60.0
			earth.position = Vector3.ZERO
			moon.scale = Vector3.ONE * 5.0
			moon.position = Vector3(-260, 50, -520)
			_orion_play("solar_acquire")
		3:
			earth.scale = Vector3.ONE * 30.0
			earth.position = Vector3.ZERO
			moon.scale = Vector3.ONE * 5.0
			moon.position = Vector3(-260, 50, -520)
			belts.visible = true
		4:
			earth.scale = Vector3.ONE * 30.0
			moon.scale = Vector3.ONE * 10.0
			_set_sun(Vector3(0.9, 0.3, 0.25), 2.0, Color.WHITE)
			_orion_play("engine_trim")
		5:
			earth.scale = Vector3.ONE * 30.0
			earth.position = Vector3(25, -12, 330)
			moon.scale = Vector3.ONE * 10.0
			moon.position = Vector3(-10, 5, -95)
		6:
			earth.scale = Vector3.ONE * 30.0
			earth.position = Vector3(25, -12, 360)
			moon.scale = Vector3.ONE * 12.0
			moon.position = Vector3(-9, 5, -75)
		7:
			moon.scale = Vector3.ONE * 60.0
			moon.position = Vector3(-18, -22, -70)
			earth.scale = Vector3.ONE * 40.0
			earth.position = Vector3(45, 20, -500)
			_set_sun(Vector3(0.75, 0.35, 0.56), 1.5, Color(1.0, 0.98, 0.95))
			_orion_play("antenna_acquire")

func _update(i: int, u: float) -> void:
	match i:
		0: _s_launch(u)
		1: _s_separation(u)
		2: _s_orbit(u)
		3: _s_belts(u)
		4: _s_to_moon(u)
		5: _s_storm(u)
		6: _s_leak(u)
		7: _s_moon(u)

# 1) DESPEGUE: el SLS sube, el cielo pasa de azul a negro
func _s_launch(u: float) -> void:
	var atmo: float = 1.0 - smoothstep(0.3, 0.62, u)
	_sky(atmo, 0.0)
	sls.visible = true
	orion.visible = false
	earth.visible = u > 0.62
	ship.rotation_degrees = Vector3(90.0 - 55.0 * smoothstep(0.25, 0.9, u), 0, sin(clock * 0.7) * 1.5)
	var nose: Vector3 = -ship.basis.z
	p_flame.emitting = true
	p_smoke.emitting = true
	p_air.emitting = atmo > 0.25
	fx_light.light_color = Color(1.0, 0.6, 0.25)
	fx_light.light_energy = 2.5 + sin(clock * 30.0) * 0.6
	tel_g = _kf(u, [[0.0, 1.3], [0.15, 2.0], [0.25, 2.5], [0.29, 1.1], [0.6, 2.0], [0.95, 4.0], [1.0, 4.0]])
	tel_v = _kf(u, [[0.0, 0.0], [0.185, 4200.0], [0.263, 5100.0], [1.0, 28000.0]])
	tel_d = _kf(u, [[0.0, 0.0], [0.185, 22.0], [0.37, 78.0], [1.0, 160.0]])
	_scenario("warning" if tel_g >= 3.0 else "normal")
	cab_shake = lerpf(1.0, 0.3, u)
	if u < 0.24:
		feel = "Vibración fuerte y ruido. El cuerpo pesa el doble contra el asiento."
	elif u < 0.34:
		feel = "Se sueltan los cohetes laterales: el empuje baja unos segundos."
	elif u < 0.62:
		feel = "Se acaba el aire y el cielo se vuelve negro. La presión vuelve a subir."
	else:
		feel = "4 veces su peso: cuesta respirar. Qué hacer: respirar corto y tensar las piernas."
	if u < 0.32:
		var k := u / 0.32
		cam_shake = 0.12
		_cam(Vector3(4.0 + 1.0 * k, -10.5 - 2.5 * k, 6.0), Vector3(0, -1.0, 0), 68.0)
	elif u < 0.66:
		var k := inverse_lerp(0.32, 0.66, u)
		cam_shake = 0.04
		_cam(Vector3(24.0 - 4.0 * k, 2.0 + 3.0 * k, 22.0), Vector3(0, -2, 0), 42.0)
	else:
		var k := inverse_lerp(0.66, 1.0, u)
		cam_shake = 0.02
		_cam(nose * 15.0 + Vector3(4.0 + 2.0 * k, 6.0, 0.0), Vector3.ZERO, 55.0)

# 2) SEPARACIÓN: se suelta la etapa principal; la cápsula sigue unida a la etapa superior
func _s_separation(u: float) -> void:
	ship.rotation_degrees = Vector3(35, 0, 0)
	var nose: Vector3 = -ship.basis.z
	var after := u >= 0.42
	if after and prev_u < 0.42:
		flash.color = Color(1, 1, 1, 1)
		flash_a = 1.0
	sls.visible = true
	orion.visible = after
	upper.visible = after
	if after:
		var k := inverse_lerp(0.42, 1.0, u)
		sls.position = Vector3(1.5 * k, -4.0 * k, 9.0 + 50.0 * k)
		sls.rotation_degrees = Vector3(-90.0 + 50.0 * k, 30.0 * k, 0)
		_cam(nose * (6.0 + 1.5 * k) + Vector3(2.5, 3.0 + k, 0.0), Vector3(0, -0.4, 0.6), 50.0)
	else:
		var k := u / 0.42
		_cam(nose * (15.0 - 2.0 * k) + Vector3(6.0, 6.0, 0.0), Vector3.ZERO, 55.0)
	tel_g = 0.0
	tel_v = 28000.0
	tel_d = lerpf(160.0, 185.0, u)
	_scenario("normal")
	if after:
		feel = "Se suelta la etapa principal. La cápsula sigue unida a una etapa más chica. De golpe no pesa nada."
	else:
		feel = "Motores apagados. La etapa principal está por soltarse."

func _orbit_pos(u: float) -> Vector3:
	var a: float = 0.2 + u * TAU * 0.5
	var r: float = 72.0 + 34.0 * smoothstep(0.45, 1.0, u)
	return Vector3(cos(a) * r, sin(a) * 6.0, sin(a) * r)

# 3) ÓRBITA TERRESTRE: vueltas a la Tierra, cada vez más altas
func _s_orbit(u: float) -> void:
	earth.rotation_degrees = Vector3(15, 120.0 + clock * 1.2, 0)
	var p := _orbit_pos(u)
	ship.position = p
	_face(_orbit_pos(u + 0.002) - p)
	# Primero la etapa superior se enciende y sube la órbita; luego se suelta y se aleja
	var burn := u < 0.3
	upper.visible = u < 0.85
	p_uflame.emitting = burn
	fx_light.light_color = Color(1.0, 0.7, 0.4)
	fx_light.light_energy = 1.4 if burn else 0.0
	if u >= 0.4:
		var k := inverse_lerp(0.4, 0.85, u)
		upper.position = Vector3(0.3 * k, -0.4 * k, upper_z + 7.0 * k)
		upper.rotation = Vector3(0.5 * k, 0.8 * k, 0.3 * k)
	tel_g = 0.2 if burn else 0.0
	tel_v = lerpf(28000.0, 22000.0, u)
	tel_d = lerpf(185.0, 2200.0, smoothstep(0.3, 1.0, u))
	_scenario("normal")
	if burn:
		feel = "La etapa superior se enciende para subir la órbita: un empujón suave contra el asiento."
	elif u < 0.6:
		feel = "Se suelta la etapa superior. Desde aquí la cápsula sigue sola con su propio motor."
	else:
		feel = "Sin peso la sangre sube a la cabeza: cara hinchada y mareo. Qué hacer: tomar agua."
	if u < 0.4:
		_cam(ship.transform * Vector3(-6.5, 1.8, 1.0), ship.transform * Vector3(0.0, 0.0, 1.0), 46.0)
	elif u < 0.72:
		_cam(ship.transform * Vector3(-3.8, 1.6, -4.0), ship.transform * Vector3(0.0, 0.0, 2.5), 50.0)
	else:
		_cam(ship.transform * Vector3(-4.5, 1.3, -5.5), ship.transform * Vector3(1.5, 0, 0), 48.0)

# 4) CINTURONES DE VAN ALLEN: dos zonas de radiación alrededor de la Tierra
func _s_belts(u: float) -> void:
	earth.rotation_degrees = Vector3(15, 150.0 + clock * 1.2, 0)
	var a: float = 0.7 + 0.45 * u
	var r: float = 30.0 + 75.0 * u
	var p := Vector3(cos(a) * r, 1.5 + 2.0 * u, sin(a) * r)
	var a2: float = 0.7 + 0.45 * (u + 0.002)
	var r2: float = 30.0 + 75.0 * (u + 0.002)
	ship.position = p
	_face(Vector3(cos(a2) * r2, p.y, sin(a2) * r2) - p)
	var rad := p.normalized()
	var side := rad.cross(Vector3.UP).normalized()
	var inten: float = maxf(_bump(r, 23.0, 41.0), _bump(r, 48.0, 92.0))
	p_belt.emitting = inten > 0.1
	fx_light.light_color = Color(0.65, 0.45, 1.0).lerp(Color(0.3, 1.0, 0.8), smoothstep(41.0, 55.0, r))
	fx_light.light_energy = 4.0 * inten
	cab_shake = 0.08 * inten
	tel_g = 0.0
	tel_v = lerpf(22000.0, 8000.0, u)
	tel_d = lerpf(2200.0, 58000.0, u)
	_scenario("warning")
	feel = "Radiación atrapada por el imán de la Tierra. No se siente, pero se acumula."
	if u < 0.5:
		_cam(p + rad * 9.0 + Vector3(0, 2.5, 0) + side * 3.0, p - rad * 4.0, 50.0)
	else:
		_cam(ship.transform * Vector3(4.5, 0.9, -1.5), p, 45.0)

# 5) RUMBO A LA LUNA: encendido del motor y viaje rápido
func _s_to_moon(u: float) -> void:
	var e: float = smoothstep(0.0, 1.0, u)
	earth.position = Vector3(6, -4, 42.0 + 420.0 * e)
	earth.rotation_degrees = Vector3(15, 200, 0)
	moon.position = Vector3(-8, 5, -(520.0 - 440.0 * e))
	ship.rotation = Vector3(0, 0, sin(clock * 0.25) * 0.06)
	var burn := u < 0.22
	p_oflame.emitting = burn
	p_speed.emitting = true
	fx_light.light_color = Color(0.5, 0.7, 1.0)
	fx_light.light_energy = 1.5 if burn else 0.0
	tel_g = 0.1 if burn else 0.0
	tel_v = _kf(u, [[0.0, 28000.0], [0.22, 39000.0], [1.0, 5000.0]])
	tel_d = _kf(u, [[0.0, 300.0], [0.22, 2500.0], [1.0, 300000.0]])
	_scenario("normal")
	if burn:
		feel = "Encendido rumbo a la Luna: un empujón suave contra el asiento."
	else:
		feel = "Días sin peso: músculos y huesos se debilitan. Qué hacer: ejercicio diario."
	if u < 0.25:
		cam_shake = 0.015
		_cam(Vector3(4.5, 1.6, 5.0), Vector3(0, 0.3, -0.5), lerpf(46.0, 58.0, smoothstep(0.0, 0.2, u)))
	elif u < 0.55:
		_cam(Vector3(3.5, 1.5, -8.0), Vector3(0, -0.6, 0), 50.0)
	elif u < 0.8:
		var k := inverse_lerp(0.55, 0.8, u)
		_cam(Vector3(7.0, 1.0, lerpf(-38.0, 30.0, k)), Vector3.ZERO, 50.0)
	else:
		_cam(Vector3(-1.2, 1.4, 7.5), Vector3(-3.0, -2.5, -30.0), 40.0)

# 6) TORMENTA SOLAR: llega una ola de radiación desde el Sol
func _s_storm(u: float) -> void:
	var s := SUN_SPACE.normalized()
	var fl: float = 0.6 * smoothstep(0.08, 0.3, u) * (1.0 - smoothstep(0.88, 1.0, u))
	_sky(0.0, fl)
	_set_sun(SUN_SPACE, 2.0 + 1.2 * fl, Color.WHITE.lerp(Color(1.0, 0.62, 0.3), fl))
	p_storm.emitting = fl > 0.1
	ship.rotation = Vector3(0, 0.3 * u, sin(clock * 0.3) * 0.08)
	fx_light.light_color = Color(1.0, 0.5, 0.2)
	fx_light.light_energy = 2.0 * fl
	if fl > 0.4 and fmod(clock, 1.9) < 0.05 and flash_a < 0.05:
		flash.color = Color(1.0, 0.7, 0.4, 1)
		flash_a = 0.3
	cab_shake = 0.12 * fl
	tel_g = 0.0
	tel_v = 4500.0
	tel_d = lerpf(310000.0, 316000.0, u)
	_scenario("warning" if u < 0.1 else "solarFlare")
	feel = "La radiación sube de golpe y daña por dentro. Qué hacer: refugiarse entre las bolsas de carga."
	if u < 0.5:
		_cam(-s * 8.0 + Vector3(-2.5, 0.5, 1.0), s * 12.0, 55.0)
	else:
		_cam(Vector3(4.5, 2.2, 3.5), Vector3.ZERO, 45.0)

# 7) FUGA DE OXÍGENO: se escapa aire de la cabina
func _s_leak(u: float) -> void:
	var k: float = smoothstep(0.0, 0.72, u)
	p_leak.emitting = u < 0.72
	ship.rotation = Vector3(0.05 * sin(clock * 0.4), 0.5 * k, 0.25 * k)
	fx_light.light_color = Color(1.0, 0.15, 0.1)
	fx_light.light_energy = 3.0 * (0.5 + 0.5 * sin(clock * 8.0))
	tel_g = 0.0
	tel_v = 4000.0
	tel_d = lerpf(352000.0, 356000.0, u)
	_scenario("warning" if u < 0.08 else "hypoxia")
	if u < 0.72:
		feel = "Baja el oxígeno: mareo y visión borrosa. Qué hacer: máscara de oxígeno y cerrar la fuga."
	else:
		feel = "Fuga cerrada. El oxígeno sube: el cuerpo tarda minutos en recuperarse."
	if u < 0.5:
		_cam(Vector3(6.5, 2.0, -3.5), Vector3(0.8, 0.4, 0), 45.0)
	else:
		_cam(Vector3(7.0, 3.5, 8.0), Vector3.ZERO, 42.0)

# 8) ESTABILIZADO: todo vuelve a la normalidad y la nave pasa junto a la Luna
func _s_moon(u: float) -> void:
	moon.rotation.y = clock * 0.01
	earth.rotation_degrees = Vector3(15, 250, 0)
	var p := Vector3(4.0, 0.0, lerpf(22.0, -10.0, u))
	ship.position = p
	ship.rotation = Vector3(0, 0, 0.05)
	tel_g = 0.0
	tel_v = lerpf(4200.0, 5200.0, u)
	tel_d = lerpf(404000.0, 406773.0, u)
	_scenario("normal")
	feel = "Oxígeno normal y radiación baja. A más de 400.000 km de casa."
	if u < 0.55:
		_cam(p + Vector3(3.0, 1.5, 8.0), Vector3(-6, -6, -40), 50.0)
	else:
		var out := (p - moon.position).normalized()
		_cam(p + out * 9.0 + Vector3(0, 1.0, 0), p, 45.0)

# =====================================================================
#  CADA CUADRO
# =====================================================================
func _process(dt: float) -> void:
	clock += dt
	if playing:
		t_stage += dt
	var dur: float = STAGES[stage].dur
	if t_stage >= dur:
		_enter((stage + 1) % STAGES.size())
		dur = STAGES[stage].dur
	sky_mat.set_shader_parameter("tm", clock)
	var u: float = clampf(t_stage / dur, 0.0, 1.0)
	_update(stage, u)
	prev_u = u
	if remote != "":
		feel = REMOTE_FEEL[remote]

	fade_a = move_toward(fade_a, 0.0, dt * 2.5)
	flash_a = move_toward(flash_a, 0.0, dt * 1.6)
	fade.color.a = fade_a
	flash.color.a = flash_a

	# Cabina: el astronauta siente la fuerza G y la vibración; la cámara tiembla
	astro.g = tel_g
	astro.shake = cab_shake
	var j := Vector3(sin(clock * 39.0), sin(clock * 53.0 + 1.0), sin(clock * 31.0 + 2.0)) * cab_shake
	cab_cam.position = cab_base + j * 0.045
	cab_cam.rotation.z = j.x * 0.02
	var crit := scenario == "solarFlare" or scenario == "hypoxia"
	alarm.light_energy = (0.5 + 0.5 * sin(clock * 8.0)) * 3.0 if crit else 0.0
	var st_col := RED if crit else (YELLOW if scenario == "warning" else GREEN)
	for br in brackets:
		br.color = st_col
	live_dot.color = Color(0.9, 0.3, 0.3, 0.35 + 0.65 * (0.5 + 0.5 * sin(clock * 3.2)))
	lbl.cab.text = "CRÍTICO" if crit else ("ADVERTENCIA" if scenario == "warning" else "NORMAL")
	lbl.cab.add_theme_color_override("font_color", st_col)

	# Textos
	var sd: Dictionary = STAGES[stage]
	lbl.title.text = sd.name
	lbl.stage.text = "ETAPA %02d/%02d" % [stage + 1, STAGES.size()]
	var secs: float = lerpf(sd.t0, sd.t1, u)
	var days := int(secs / 86400.0)
	var hh := int(fmod(secs, 86400.0) / 3600.0)
	var mm := int(fmod(secs, 3600.0) / 60.0)
	var ss := int(fmod(secs, 60.0))
	if days > 0:
		lbl.clock.text = "T+ %dd %02d:%02d" % [days, hh, mm]
	else:
		lbl.clock.text = "T+ %02d:%02d:%02d" % [hh, mm, ss]
	lbl.feel.text = feel
	lbl.g.text = ("%.1f" % tel_g).replace(".", ",")
	var g_col := YELLOW if tel_g >= 3.0 else Color(0.97, 0.98, 1.0)
	lbl.g.add_theme_color_override("font_color", g_col)
	lbl.g_u.add_theme_color_override("font_color", g_col if tel_g >= 3.0 else DIM)
	lbl.v.text = _fmt(round(tel_v / 10.0) * 10.0)
	lbl.d_cap.text = sd.dist
	lbl.d.text = _fmt(tel_d)
	var total := 0.0
	var done := 0.0
	for i in STAGES.size():
		var d: float = STAGES[i].dur
		total += d
		if i < stage:
			done += d
	bar_fill.anchor_right = (done + t_stage) / total

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_SPACE:
				playing = not playing
			KEY_RIGHT:
				_enter((stage + 1) % STAGES.size())
			KEY_LEFT:
				_enter((stage - 1 + STAGES.size()) % STAGES.size())
			KEY_H:
				hud.visible = not hud.visible
			_:
				var n: int = ev.keycode - KEY_1
				if n >= 0 and n < STAGES.size():
					_enter(n)

## Mide los cuadros por segundo de cada etapa (solo si existe _pruebas/fps.flag).
func _fps_test() -> void:
	var out := ""
	for i in STAGES.size():
		_enter(i)
		await get_tree().create_timer(1.2).timeout
		var acc := 0.0
		var n := 0
		for k in 45:
			await get_tree().process_frame
			acc += Engine.get_frames_per_second()
			n += 1
		out += "etapa %d: %d fps\n" % [i + 1, int(acc / float(n))]
	var f := FileAccess.open("res://_pruebas/fps.txt", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	get_tree().quit()

# =====================================================================
#  CAPTURAS DE PRUEBA (solo si existe _pruebas/snap.flag)
# =====================================================================
func _snapshots() -> void:
	playing = false
	var shots := [[0, 0.85], [5, 0.35]]
	var last := -1
	for s in shots:
		var i: int = s[0]
		var u: float = s[1]
		if i != last:
			_enter(i)
			last = i
		t_stage = maxf(u - 0.08, 0.0) * float(STAGES[i].dur)
		playing = true
		await get_tree().create_timer(0.08 * float(STAGES[i].dur)).timeout
		playing = false
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://_pruebas/e%d_%02d.png" % [i + 1, int(u * 100)])
	get_tree().quit()
