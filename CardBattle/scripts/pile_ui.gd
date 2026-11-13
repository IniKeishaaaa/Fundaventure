@tool
class_name PileUI
extends Control

# Ukuran & bingkai sama persis dengan kartu biasa
const PILE_SIZE := CardUI.CARD_SIZE
const FRAME := CardUI.CARD_FRAME

# Warna teks (gelap, tanpa outline). Judul = title_color yang digelapkan
const TEXT_COLOR := Color(0.1, 0.1, 0.18)
const TITLE_DARKEN := 0.5

# Titik tengah lingkaran jumlah kartu (kiri atas). Geser angka ini kalau belum pas.
const COUNT_CENTER := Vector2(12, 29)
# Ukuran kotak label angka (angka dirata-tengahkan di dalam kotak ini)
const COUNT_BOX := Vector2(32, 32)

var _count_label: Label
var _desc_label: Label


func setup(title: String, count: int, title_color: Color = Color.WHITE) -> void:
	custom_minimum_size = PILE_SIZE
	size = PILE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame_tex := GameAssets.get_texture(FRAME)

	# Efek tumpukan: 2 bingkai redup di belakang, sedikit bergeser
	if frame_tex != null:
		for i in 2:
			var back := _make_frame(frame_tex)
			back.position = Vector2(-3 * (2 - i), -3 * (2 - i))
			back.modulate = Color(0.55, 0.55, 0.55, 1)
			add_child(back)

		# Bingkai utama di paling depan
		add_child(_make_frame(frame_tex))

	# Jumlah kartu ditaruh di lingkaran kiri atas (sama seperti cost), rata tengah
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 15)
	_count_label.add_theme_color_override("font_color", TEXT_COLOR)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.size = COUNT_BOX
	_count_label.position = COUNT_CENTER - COUNT_BOX / 2.0
	add_child(_count_label)

	# Teks di bawah (tanpa strip hitam)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(4, PILE_SIZE.y - 62)
	box.size = Vector2(PILE_SIZE.x - 8, 62)
	add_child(box)

	var name_label := Label.new()
	name_label.text = title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", title_color.darkened(TITLE_DARKEN))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	_desc_label = Label.new()
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_font_size_override("font_size", 10)
	_desc_label.add_theme_color_override("font_color", TEXT_COLOR)
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_desc_label)

	set_count(count)


func set_count(count: int) -> void:
	_count_label.text = str(count)
	_desc_label.text = "%d kartu" % count


func _make_frame(tex: Texture2D) -> TextureRect:
	var f := TextureRect.new()
	f.texture = tex
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_SCALE
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.size = PILE_SIZE
	return f
