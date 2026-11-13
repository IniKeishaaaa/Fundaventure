@tool
class_name BattleVFX
extends Control

# VFX hitam putih, digambar lewat kode (tanpa gambar tambahan):
# - attack()    : goresan tebasan + percikan tinta di target
# - shield()    : perisai muncul + cincin menyebar di target
# - hit_shake() : target berkedip putih dan bergetar sedikit

const INK := Color(0.05, 0.05, 0.08)   # hitam (garis tepi)
const PAPER := Color(1, 1, 1)          # putih (isi)

# ===== PENGATURAN (bebas kamu ubah) =====
const ATTACK_TIME := 0.45     # durasi efek serang (detik)
const SHIELD_TIME := 0.7      # durasi efek perisai (detik)
const SLASH_LENGTH := 170.0   # panjang goresan tebasan (px)
const SHIELD_SIZE := 48.0     # ukuran perisai (px)
const FX_Z := 25              # di atas buku (20), di bawah tombol restart (30)

enum Kind { SLASH, SHIELD }

var kind := Kind.SLASH
var center := Vector2.ZERO
var t := 0.0:
	set(value):
		t = value
		queue_redraw()

var _slashes: Array = []   # tiap isi: {"angle", "offset", "length"}
var _dots: Array = []      # tiap isi: Vector3(sudut, jarak, ukuran)


# ============================================================
# Dipanggil dari battle.gd
# ============================================================
# parent = node battle, global_center = titik tengah target di layar
static func attack(parent: Control, global_center: Vector2) -> void:
	_spawn(parent, global_center, Kind.SLASH, ATTACK_TIME)


static func shield(parent: Control, global_center: Vector2) -> void:
	_spawn(parent, global_center, Kind.SHIELD, SHIELD_TIME)


# Angka melayang naik lalu memudar (misal damage "-6" atau block "+10")
static func number(parent: Control, global_center: Vector2, text: String, font_size: int = 40) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.z_index = FX_Z + 1
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", PAPER)
	lbl.add_theme_color_override("font_outline_color", INK)
	lbl.add_theme_constant_override("outline_size", 10)
	parent.add_child(lbl)
	lbl.reset_size()
	lbl.pivot_offset = lbl.size / 2.0
	var start := global_center - parent.global_position - lbl.size / 2.0 + Vector2(randf_range(-14.0, 14.0), -40.0)
	lbl.position = start
	lbl.scale = Vector2.ONE * 0.5
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "position:y", start.y - 50.0, 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.3).set_delay(0.55)
	tw.chain().tween_callback(lbl.queue_free)


# Target (karakter/musuh) berkedip putih lalu bergetar sedikit
static func hit_shake(target: Control) -> void:
	if target == null or not target.is_inside_tree():
		return
	target.pivot_offset = target.size / 2.0
	target.modulate = Color(3, 3, 3, 1)
	var flash := target.create_tween()
	flash.tween_property(target, "modulate", Color.WHITE, 0.2)
	var shake := target.create_tween()
	shake.tween_property(target, "rotation", 0.06, 0.04)
	shake.tween_property(target, "rotation", -0.06, 0.06)
	shake.tween_property(target, "rotation", 0.03, 0.05)
	shake.tween_property(target, "rotation", 0.0, 0.05)


# ============================================================
# Internal
# ============================================================
static func _spawn(parent: Control, global_center: Vector2, k: Kind, duration: float) -> void:
	var fx := BattleVFX.new()
	fx.kind = k
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.z_index = FX_Z
	parent.add_child(fx)
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.center = global_center - fx.global_position
	fx._randomize_shapes()
	var tw := fx.create_tween()
	tw.tween_property(fx, "t", 1.0, duration)
	tw.tween_callback(fx.queue_free)


func _randomize_shapes() -> void:
	# 3 goresan sejajar miring, arah sedikit acak tiap kali
	var base := randf_range(0.5, 0.9)
	if randf() < 0.5:
		base = PI - base   # kadang miring ke arah sebaliknya
	var offsets := [-20.0, 0.0, 20.0]
	var lengths := [0.8, 1.0, 0.8]
	for i in 3:
		_slashes.append({
			"angle": base + randf_range(-0.06, 0.06),
			"offset": offsets[i],
			"length": SLASH_LENGTH * lengths[i],
		})
	# Percikan tinta
	for i in 7:
		_dots.append(Vector3(randf() * TAU, randf_range(35.0, 80.0), randf_range(2.5, 5.0)))


static func _back(x: float) -> float:
	# ease out back: muncul sedikit "membal"
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var v := clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + c3 * v * v * v + c1 * v * v


func _draw() -> void:
	match kind:
		Kind.SLASH:
			_draw_slash()
		Kind.SHIELD:
			_draw_shield()


# ============================================================
# Efek serang
# ============================================================
func _draw_slash() -> void:
	var fade := 1.0 - smoothstep(0.55, 1.0, t)

	# Kilatan putih di awal
	var flash := 1.0 - smoothstep(0.0, 0.25, t)
	draw_circle(center, 55.0 * (0.6 + t), Color(PAPER, 0.7 * flash))

	# Goresan tebasan: ujung depan melesat, ekor menyusul
	var head := smoothstep(0.0, 0.35, t)
	var tail := smoothstep(0.15, 0.6, t)
	for s in _slashes:
		var angle: float = s["angle"]
		var off: float = s["offset"]
		var length: float = s["length"]
		var dir := Vector2.from_angle(angle)
		var start := center + dir.orthogonal() * off - dir * length * 0.5
		var a := start + dir * length * tail
		var b := start + dir * length * head
		draw_line(a, b, Color(INK, fade), 12.0, true)
		draw_line(a, b, Color(PAPER, fade), 6.0, true)

	# Garis memancar + percikan tinta
	var burst := smoothstep(0.1, 0.7, t)
	for i in 8:
		var d := Vector2.from_angle(TAU * i / 8.0 + 0.3)
		var r0 := 20.0 + 50.0 * burst
		var r1 := r0 + 18.0 * (1.0 - burst)
		draw_line(center + d * r0, center + d * r1, Color(INK, fade), 8.0, true)
		draw_line(center + d * r0, center + d * r1, Color(PAPER, fade), 3.5, true)
	for dot in _dots:
		var v: Vector3 = dot
		var p := center + Vector2.from_angle(v.x) * (v.y * burst)
		var sz := v.z * (1.0 - burst * 0.5)
		draw_circle(p, sz, Color(INK, fade))
		draw_circle(p, sz * 0.5, Color(PAPER, fade))


# ============================================================
# Efek pelindung
# ============================================================
func _draw_shield() -> void:
	var fade := 1.0 - smoothstep(0.65, 1.0, t)
	var sc := 0.4 + 0.6 * _back(t / 0.3)

	# Cincin menyebar keluar
	var ring_r := lerpf(30.0, 95.0, smoothstep(0.0, 0.8, t))
	var ring_a := 1.0 - smoothstep(0.1, 0.8, t)
	draw_arc(center, ring_r, 0.0, TAU, 48, Color(INK, ring_a), 9.0, true)
	draw_arc(center, ring_r, 0.0, TAU, 48, Color(PAPER, ring_a), 4.0, true)

	# Perisai
	var base := PackedVector2Array([
		Vector2(-1.0, -0.9), Vector2(0.0, -1.1), Vector2(1.0, -0.9), Vector2(0.95, 0.1),
		Vector2(0.55, 0.65), Vector2(0.0, 1.05), Vector2(-0.55, 0.65), Vector2(-0.95, 0.1)])
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for p in base:
		outer.append(center + p * SHIELD_SIZE * sc)
		inner.append(center + p * SHIELD_SIZE * sc * 0.68)
	draw_colored_polygon(outer, Color(PAPER, 0.92 * fade))
	outer.append(outer[0])
	inner.append(inner[0])
	draw_polyline(outer, Color(INK, fade), 7.0, true)
	draw_polyline(inner, Color(INK, 0.7 * fade), 3.0, true)
