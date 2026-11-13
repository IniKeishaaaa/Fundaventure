@tool
class_name CardUI
extends Button

# Ukuran kartu. Gambar bingkai akan memenuhi seluruh ukuran ini.
const CARD_SIZE := Vector2(90, 180)

# Gambar bingkai yang dipakai SEMUA kartu. Ganti path ini kalau nama filenya beda.
const CARD_FRAME := "res://assets/cards/tebas.png"

# ============================================================
# PENGATURAN PER KARTU (SEMUANYA DI SINI, SATU TEMPAT)
# ============================================================
# Tiap kartu bisa punya ikon, ukuran ikon, dan ukuran teks sendiri-sendiri.
# Kunci = nama kartu persis seperti di game (huruf besar-kecil harus sama).
# Isi yang tidak ditulis akan memakai DEFAULT_STYLE.
#
#   icon        : path gambar ikon. "" = pakai ikon bawaan tipe kartu (lihat TYPE_ICONS)
#   icon_area   : Rect2(x, y, lebar, tinggi) tempat ikon di kartu. Mau ikon lebih besar? besarkan lebar & tinggi,
#                 lalu kurangi x & y setengah selisihnya supaya tetap di tengah
#   name_size   : ukuran huruf nama kartu
#   desc_size   : ukuran huruf deskripsi kartu
#   text_height : tinggi kotak teks dari dasar kartu. Naikkan kalau teks besar mulai terpotong
const DEFAULT_STYLE := {
	"icon": "",
	"icon_area": Rect2(27, 44, 46, 46),
	"name_size": 13,
	"desc_size": 10,
	"text_height": 62,
}

const CARD_STYLE := {
	"Tebas": {
		"icon": "res://assets/iconcard/tebas.png",
		"icon_area": Rect2(27, 44, 46, 46),
		"name_size": 13,
		"desc_size": 10,
		"text_height": 62,
	},
	"Tusukan": {
		"icon": "",
		"icon_area": Rect2(27, 44, 46, 46),
		"name_size": 13,
		"desc_size": 10,
		"text_height": 62,
	},
	"Semangat": {
		"icon": "",
		"icon_area": Rect2(27, 44, 46, 46),
		"name_size": 13,
		"desc_size": 10,
		"text_height": 62,
	},
	"Kutukan": {
		"icon": "",
		"icon_area": Rect2(27, 44, 46, 46),
		"name_size": 13,
		"desc_size": 10,
		"text_height": 62,
	},
	"Perisai Tinta": {
		"icon": "",
		"icon_area": Rect2(27, 44, 46, 46),
		"name_size": 13,
		"desc_size": 10,
		"text_height": 62,
	},
	"Dinding Tinta": {
		"icon": "",
		"icon_area": Rect2(27, 44, 46, 46),
		"name_size": 13,
		"desc_size": 10,
		"text_height": 62,
	},
}

# Ikon bawaan per tipe kartu (dipakai kalau "icon" di kartu itu kosong)
const TYPE_ICONS := {
	CardData.Type.OFFENSIVE: "res://assets/iconcard/note.png",
	CardData.Type.DEFENSIVE: "res://assets/iconcard/shield.png",
	CardData.Type.BUFF: "res://assets/iconcard/note.png",
	CardData.Type.DEBUFF: "res://assets/iconcard/dis.png",
}

# Warna teks kartu (gelap, karena bingkai kartu terang dan teks tanpa outline)
const TEXT_COLOR := Color(0.1, 0.1, 0.18)
const NAME_DARKEN := 0.35   # nama kartu = warna tipe kartu yang digelapkan (0 = warna asli, 1 = hitam)

# ===== PENGATURAN ANIMASI (bebas kamu ubah) =====
const HOVER_LIFT := 35.0     # seberapa tinggi kartu naik saat disorot (px)
const HOVER_SCALE := 1.15    # pembesaran saat disorot
const PRESS_SCALE := 0.95    # ukuran saat tombol mouse ditekan
const ANIM_TIME := 0.12      # durasi animasi (detik)
const SELECT_LIFT := 30.0    # seberapa tinggi kartu naik saat DIPILIH (px)
const SELECT_TINT := Color(1.0, 1.0, 0.7)   # warna kartu yang dipilih

var data: CardData
var visual: Control          # semua tampilan kartu ada di sini (yang dianimasikan)
var selected := false        # kartu sedang ditandai (dipilih)
var _tween: Tween
var _hovering := false


# Gabungan DEFAULT_STYLE + pengaturan khusus kartu ini
func _style_of(card: CardData) -> Dictionary:
	var s: Dictionary = DEFAULT_STYLE.duplicate()
	s.merge(CARD_STYLE.get(card.display_name, {}), true)
	return s


func setup(card: CardData, affordable: bool) -> void:
	data = card
	text = ""
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = CARD_SIZE

	# Tombol sendiri dibuat transparan, hanya jadi area klik
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)

	# Node "visual": inilah yang naik/membesar saat animasi
	visual = Control.new()
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.size = CARD_SIZE
	visual.pivot_offset = CARD_SIZE / 2.0
	add_child(visual)

	# Lapisan 1: gambar bingkai (sama untuk semua kartu)
	var frame_tex := GameAssets.get_texture(CARD_FRAME)
	if frame_tex != null:
		var frame := TextureRect.new()
		frame.texture = frame_tex
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE   # penuhi seluruh kartu
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.size = CARD_SIZE
		visual.add_child(frame)

	var style := _style_of(card)

	# Lapisan 2: ikon di dalam bingkai
	_add_icon(card, style)

	# Lapisan 3: teks (cost, nama, deskripsi)
	_add_texts(card, style)

	# Kartu redup kalau ink tidak cukup
	modulate = Color(1, 1, 1, 1) if affordable else Color(0.5, 0.5, 0.5, 1)

	# Sinyal untuk animasi
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


# Tandai / lepas tanda kartu terpilih (kartu naik sedikit dan berwarna kekuningan)
func set_selected(value: bool) -> void:
	selected = value
	if visual == null:
		return
	visual.position.y = -_base_lift()
	visual.modulate = SELECT_TINT if selected else Color.WHITE


func _base_lift() -> float:
	return SELECT_LIFT if selected else 0.0


func _add_icon(card: CardData, style: Dictionary) -> void:
	var path: String = style["icon"]
	if path == "":
		path = TYPE_ICONS.get(card.type, "")
	if path == "":
		return
	var tex := GameAssets.get_texture(path)
	if tex == null:
		return
	var area: Rect2 = style["icon_area"]
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED   # proporsi gambar tetap, muat di area
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = area.position
	icon.size = area.size
	visual.add_child(icon)


func _add_texts(card: CardData, style: Dictionary) -> void:
	# Cost ink di pojok kiri atas
	var cost := Label.new()
	cost.text = str(card.ink_cost)
	cost.add_theme_font_size_override("font_size", 20)
	cost.add_theme_color_override("font_color", TEXT_COLOR)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.position = Vector2(8, 12)
	visual.add_child(cost)

	# Teks nama & deskripsi langsung di atas kartu (tanpa strip hitam dan tanpa outline)
	var text_h: float = style["text_height"]
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(4, CARD_SIZE.y - text_h)
	box.size = Vector2(CARD_SIZE.x - 8, text_h)
	visual.add_child(box)

	var name_label := Label.new()
	name_label.text = card.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", style["name_size"])
	name_label.add_theme_color_override("font_color", CardData.type_color(card.type).darkened(NAME_DARKEN))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = card.description
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", style["desc_size"])
	desc_label.add_theme_color_override("font_color", TEXT_COLOR)
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc_label)


# ============================================================
# ANIMASI
# ============================================================
func _animate(lift: float, target_scale: float) -> void:
	if visual == null:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(visual, "position:y", -lift, ANIM_TIME)
	_tween.tween_property(visual, "scale", Vector2.ONE * target_scale, ANIM_TIME)


func _on_mouse_entered() -> void:
	_hovering = true
	z_index = 10   # tampil di atas kartu lain yang bertumpuk
	_animate(maxf(HOVER_LIFT, _base_lift()), HOVER_SCALE)


func _on_mouse_exited() -> void:
	_hovering = false
	z_index = 0
	_animate(_base_lift(), 1.0)


func _on_button_down() -> void:
	_animate(maxf(HOVER_LIFT, _base_lift()), PRESS_SCALE)


func _on_button_up() -> void:
	if _hovering:
		_animate(maxf(HOVER_LIFT, _base_lift()), HOVER_SCALE)
