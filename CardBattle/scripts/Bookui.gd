@tool
class_name BookUI
extends Control

# Buku yang selalu ada di layar battle:
# - Idle            : buku TERTUTUP (Bukuclose.png), di BELAKANG kartu di tangan
# - Kartu dipilih   : buku TERBUKA (Bukuopen.png). Kiri = kartu yang dipilih, kanan = gambar bentuk
# - Gambar cukup akurat : kartu otomatis dipakai dan buku menutup lagi

signal confirmed(bonus: float)   # gambar sudah cukup akurat. bonus = tambahan damage/block (0.0 - MAX_BONUS)
signal cancelled                 # (tidak dipakai lagi, dibiarkan supaya battle.gd tidak error)

signal skip_pressed              # pemain menekan pita 1 (skip turn)

const BOOK_CLOSED := "res://assets/book/Bukuclose.png"
const BOOK_OPEN := "res://assets/book/Bukuopen.png"

# ----- Pita di sisi buku -----
# 1 = skip turn (kanan atas)   2 = kartu discard (kanan bawah)
# 3 = ink poin (kiri atas, tidak bisa diklik)   4 = kartu di deck (kiri bawah)
# Bentuk pita berganti dari btndefault ke btnholder saat disorot / diklik.
const TAB_DEFAULT := "res://assets/book/btndefault/%d.png"
const TAB_HOLD := "res://assets/book/btnholder/%d.png"
const TAB_WIDTH_FRAC := 0.11   # lebar pita = persen dari lebar buku tertutup (besar/kecilkan pita di sini)
const TAB_Z := 6               # di atas kartu di tangan (kartu = z 5)

# Titik tengah tiap pita, dalam PERSEN ukuran buku (x, y). Kunci = nomor pita.
# Angka di luar 0..1 berarti pita menonjol keluar dari tepi buku.
# Buku idle (Bukuclose.png, bentuk miring):
const TABS_ON_CLOSED := {
	1: Vector2(0.945, 0.200),
	2: Vector2(0.955, 0.560),
	3: Vector2(0.055, 0.210),
	4: Vector2(0.070, 0.525),
}
# Buku terbuka (Bukuopen.png, bentuk datar):
const TABS_ON_OPEN := {
	1: Vector2(1.0030, 0.200),
	2: Vector2(1.01, 0.800),
	3: Vector2(-0.001100, 0.210),
	4: Vector2(-0.010100, 0.800),
}

# ----- Buku tertutup (kondisi idle) -----
const CLOSED_WIDTH := 620.0   # lebar buku idle. Besarkan kalau kartu masih menabrak pita
const CLOSED_Y := 300.0       # posisi atas buku idle. Lebih besar = buku turun, lebih kecil = buku naik
const CLOSED_Z := 0           # di bawah kartu (kartu = z 5, diatur di battle.gd)

# ----- Buku terbuka -----
const BOOK_WIDTH := 640.0     # lebar buku terbuka
const BOOK_TOP := 305.0       # puncak buku = garis pijakan karakter (lebih kecil = lebih ke atas)
const OPEN_Z := 20            # di atas kartu

# Posisi halaman sebagai PERSEN dari ukuran gambar buku: Rect2(x, y, lebar, tinggi)
const LEFT_PAGE := Rect2(0.09, 0.16, 0.38, 0.62)
const RIGHT_PAGE := Rect2(0.53, 0.16, 0.38, 0.62)

const CARD_FIT := 0.95        # seberapa penuh kartu mengisi halaman kiri (1.0 = pas)
const INK_COLOR := Color(0.1, 0.1, 0.18)
const GUIDE_COLOR := Color(0.35, 0.35, 0.45, 0.5)
const LINE_WIDTH := 3.0

# Posisi vertikal label akurasi (persen tinggi buku).
# Lebih kecil = naik, lebih besar = turun.
const BUTTON_ROW_Y := 0.78

# ----- Bonus akurasi -----
# Akurasi tepat di batas minimum = bonus 0%. Akurasi 100% = bonus MAX_BONUS.
# Bonus menambah damage kartu ofensif dan block kartu defensif.
const MAX_BONUS := 0.5        # 0.5 = maksimal +50%

# Jeda (detik) setelah goresan terakhir sebelum gambar yang kurang akurat dihapus otomatis.
# Selama jeda ini kamu masih bisa menambah goresan (untuk bentuk yang butuh beberapa goresan).
const AUTO_CLEAR_DELAY := 0.8

# ----- Level kesulitan gambar (mengikuti map: GameAssets.selected_enemy_index) -----
# shapes : bentuk yang mungkin muncul (dipilih acak)
# tol    : toleransi jarak goresan dari garis panduan (persen dari ukuran bentuk, makin kecil = makin sulit)
# need   : akurasi minimum supaya kartu terpakai (0.0 - 1.0)
const LEVELS := [
	{"shapes": ["circle", "square", "triangle"], "tol": 0.24, "need": 0.50},
	{"shapes": ["diamond", "hexagon", "cross"], "tol": 0.18, "need": 0.60},
	{"shapes": ["star", "heart", "bolt"], "tol": 0.14, "need": 0.70},
]
# false = bentuk hanya jadi panduan, kartu terpakai asal sudah menggambar sesuatu
const REQUIRE_ACCURACY := true

var cards: Array[CardData] = []
var pad: DrawPad
var is_open := false

var _closed_book: Control
var _open_book: Control
var _score_label: Label
var _tol_px := 10.0
var _need := 0.5
var _clear_token := 0          # penanda timer hapus otomatis (supaya timer lama diabaikan)

var _tabs: Dictionary = {}     # nomor pita -> BookTab
var _tabs_root: Control
var _tabs_tween: Tween
var _closed_w := 420.0


# ============================================================
# Area menggambar
# ============================================================
class DrawPad extends Control:
	signal changed
	signal stroke_started    # pemain mulai menggores (klik ditekan)
	signal stroke_finished   # pemain selesai menggores (klik dilepas)

	var strokes: Array[PackedVector2Array] = []
	var guide := PackedVector2Array()     # bentuk tertutup (garis panduan)
	var samples := PackedVector2Array()   # titik-titik rapat di sepanjang garis panduan
	var _drawing := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		mouse_exited.connect(_on_mouse_exited)

	# Kalau kursor keluar saat menggores, goresan dianggap selesai
	func _on_mouse_exited() -> void:
		if _drawing:
			_drawing = false
			stroke_finished.emit()

	# points = sudut-sudut bentuk (dalam piksel pad), otomatis ditutup
	func set_shape(points: PackedVector2Array) -> void:
		guide = points.duplicate()
		if points.size() > 0:
			guide.append(points[0])
		samples = PackedVector2Array()
		for i in range(guide.size() - 1):
			var a := guide[i]
			var b := guide[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 4.0))
			for j in n:
				samples.append(a.lerp(b, float(j) / n))
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drawing = true
				strokes.append(PackedVector2Array([_clamp(event.position)]))
				stroke_started.emit()
			else:
				if _drawing:
					_drawing = false
					queue_redraw()
					changed.emit()
					stroke_finished.emit()
				return
			queue_redraw()
			changed.emit()
		elif event is InputEventMouseMotion and _drawing and not strokes.is_empty():
			var s := strokes[strokes.size() - 1]
			s.append(_clamp(event.position))
			strokes[strokes.size() - 1] = s
			queue_redraw()

	func _clamp(p: Vector2) -> Vector2:
		return p.clamp(Vector2.ZERO, size)

	func clear_all() -> void:
		strokes.clear()
		queue_redraw()
		changed.emit()

	# Akurasi 0.0 - 1.0 = (seberapa banyak garis panduan tertutup goresan)
	#                     x (seberapa banyak goresan yang dekat garis panduan)
	func score(tol: float) -> float:
		if strokes.is_empty() or samples.is_empty():
			return 0.0
		# Coverage: titik panduan yang dilewati goresan
		var hit := 0
		for p in samples:
			if _near_stroke(p, tol):
				hit += 1
		var coverage := float(hit) / samples.size()
		# Precision: titik goresan yang dekat garis panduan (supaya coret-coret tidak dapat nilai penuh)
		var total := 0
		var good := 0
		for s in strokes:
			for v in s:
				total += 1
				if _dist_to_guide(v) <= tol * 2.0:
					good += 1
		var precision := float(good) / maxi(1, total)
		return coverage * precision

	func _near_stroke(p: Vector2, tol: float) -> bool:
		for s in strokes:
			if s.size() == 1:
				if s[0].distance_to(p) <= tol:
					return true
				continue
			for i in range(s.size() - 1):
				var c := Geometry2D.get_closest_point_to_segment(p, s[i], s[i + 1])
				if c.distance_to(p) <= tol:
					return true
		return false

	func _dist_to_guide(v: Vector2) -> float:
		var best := INF
		for i in range(guide.size() - 1):
			var c := Geometry2D.get_closest_point_to_segment(v, guide[i], guide[i + 1])
			best = minf(best, c.distance_to(v))
		return best

	func _draw() -> void:
		# bingkai tipis penanda area gambar
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.2), false, 1.0)
		# garis panduan yang harus diikuti
		if guide.size() > 1:
			draw_polyline(guide, BookUI.GUIDE_COLOR, 2.5, true)
		for s in strokes:
			if s.size() == 1:
				draw_circle(s[0], BookUI.LINE_WIDTH * 0.5, BookUI.INK_COLOR)
			elif s.size() > 1:
				draw_polyline(s, BookUI.INK_COLOR, BookUI.LINE_WIDTH, true)


# ============================================================
# Pita di sisi buku (tombol / penanda)
# ============================================================
class BookTab extends Control:
	signal pressed

	var side := 1                 # -1 = pita di kiri buku, 1 = di kanan buku
	var clickable := true
	var enabled := true
	var base_size := Vector2.ZERO
	var tex_default: Texture2D
	var tex_hold: Texture2D
	var rect: TextureRect
	var label: Label
	var _k := 1.0
	var _hover := false
	var _down := false

	func setup(id: int, width: float, tab_side: int, is_clickable: bool, tip: String) -> void:
		side = tab_side
		clickable = is_clickable
		tex_default = GameAssets.get_texture(BookUI.TAB_DEFAULT % id)
		tex_hold = GameAssets.get_texture(BookUI.TAB_HOLD % id)
		var h := width * 0.5
		if tex_default != null:
			_k = width / tex_default.get_width()
			h = tex_default.get_height() * _k
		base_size = Vector2(width, h)
		size = base_size
		custom_minimum_size = base_size
		pivot_offset = base_size / 2.0

		if clickable:
			mouse_filter = Control.MOUSE_FILTER_STOP
			tooltip_text = tip
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			mouse_entered.connect(func(): _set_hover(true))
			mouse_exited.connect(func(): _set_hover(false))
		else:
			mouse_filter = Control.MOUSE_FILTER_IGNORE   # tidak menghalangi klik ke kartu di bawahnya

		if tex_default == null:
			# Placeholder kalau gambar pita belum ada
			var box := ColorRect.new()
			box.color = Color(0.9, 0.9, 0.9)
			box.size = base_size
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(box)

		rect = TextureRect.new()
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)

		label = Label.new()
		label.size = base_size
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", BookUI.INK_COLOR)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)

		_show_texture(false)

	# Tampilkan bentuk default atau bentuk "ditarik" (holder).
	# Sisi yang menempel ke buku tetap di tempat, bagian luar yang memanjang.
	func _show_texture(hold: bool) -> void:
		var tex := tex_default
		if hold and tex_hold != null:
			tex = tex_hold
		if tex == null:
			return
		var s := tex.get_size() * _k
		rect.texture = tex
		rect.size = s
		var y := (base_size.y - s.y) / 2.0
		if side < 0:
			rect.position = Vector2(base_size.x - s.x, y)
		else:
			rect.position = Vector2(0.0, y)

	func _set_hover(value: bool) -> void:
		_hover = value and enabled
		if not _down:
			_show_texture(_hover)

	func set_enabled(value: bool) -> void:
		enabled = value
		modulate = Color.WHITE if value else Color(1, 1, 1, 0.45)
		if not value:
			_hover = false
			_down = false
			_show_texture(false)

	func _gui_input(event: InputEvent) -> void:
		if not clickable or not enabled:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_down = true
				_show_texture(true)
			else:
				var was_down := _down
				_down = false
				if was_down and Rect2(Vector2.ZERO, base_size).has_point(event.position):
					pressed.emit()
				_show_texture(_hover)


# ============================================================
# Bentuk panduan (koordinat -1..1, pusat di 0,0)
# ============================================================
static func _shape_points(kind: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match kind:
		"circle":
			for i in 40:
				var a := TAU * i / 40.0
				pts.append(Vector2(cos(a), sin(a)) * 0.95)
		"square":
			pts = PackedVector2Array([Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.8), Vector2(-0.8, 0.8)])
		"triangle":
			pts = PackedVector2Array([Vector2(0, -0.9), Vector2(0.95, 0.75), Vector2(-0.95, 0.75)])
		"diamond":
			pts = PackedVector2Array([Vector2(0, -0.95), Vector2(0.7, 0), Vector2(0, 0.95), Vector2(-0.7, 0)])
		"hexagon":
			for i in 6:
				var a := TAU * i / 6.0 - PI / 2.0
				pts.append(Vector2(cos(a), sin(a)) * 0.95)
		"cross":
			pts = PackedVector2Array([
				Vector2(-0.3, -0.9), Vector2(0.3, -0.9), Vector2(0.3, -0.3), Vector2(0.9, -0.3),
				Vector2(0.9, 0.3), Vector2(0.3, 0.3), Vector2(0.3, 0.9), Vector2(-0.3, 0.9),
				Vector2(-0.3, 0.3), Vector2(-0.9, 0.3), Vector2(-0.9, -0.3), Vector2(-0.3, -0.3)])
		"star":
			for i in 10:
				var r := 0.95 if i % 2 == 0 else 0.4
				var a := -PI / 2.0 + i * PI / 5.0
				pts.append(Vector2(cos(a), sin(a)) * r)
		"heart":
			for i in 40:
				var t := TAU * i / 40.0
				var x := 16.0 * pow(sin(t), 3)
				var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
				pts.append(Vector2(x, y + 2.0) / 17.0)
		"bolt":
			pts = PackedVector2Array([
				Vector2(0.2, -0.95), Vector2(-0.6, 0.1), Vector2(-0.05, 0.1),
				Vector2(-0.25, 0.95), Vector2(0.6, -0.15), Vector2(0.05, -0.15)])
	return pts


# Bonus (0.0 - MAX_BONUS) dari akurasi
static func bonus_for(score: float, need: float) -> float:
	if score < need:
		return 0.0
	return clampf((score - need) / maxf(0.01, 1.0 - need), 0.0, 1.0) * MAX_BONUS


# ============================================================
# Buku tertutup (dipanggil sekali saat UI dibangun)
# ============================================================
func _ready() -> void:
	setup()


func setup() -> void:
	if _closed_book != null:
		return   # sudah dibuat
	z_index = CLOSED_Z
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vp := get_viewport_rect().size
	var tex := GameAssets.get_texture(BOOK_CLOSED)
	var closed_size := Vector2(CLOSED_WIDTH, CLOSED_WIDTH * 0.75)
	if tex != null:
		closed_size.y = CLOSED_WIDTH * tex.get_height() / tex.get_width()

	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		_closed_book = rect
	else:
		# Placeholder kalau gambar buku tertutup belum ada
		var box := ColorRect.new()
		box.color = Color(0.45, 0.3, 0.2)
		_closed_book = box
	_closed_book.mouse_filter = Control.MOUSE_FILTER_IGNORE   # tidak boleh menghalangi klik ke kartu
	_closed_book.size = closed_size
	_closed_book.pivot_offset = closed_size / 2.0
	# Posisi atas buku idle langsung dari CLOSED_Y (tidak dinaikkan otomatis lagi)
	_closed_book.position = Vector2((vp.x - closed_size.x) / 2.0, CLOSED_Y)
	add_child(_closed_book)
	_closed_w = closed_size.x
	_make_tabs()
	_layout_tabs(false, false)


# ============================================================
# Buka buku
# ============================================================
# card_list = kartu yang dipilih pemain (tampil di halaman kiri)
func open(card_list: Array[CardData]) -> void:
	if is_open:
		return
	setup()   # jaga-jaga kalau belum dibuat
	is_open = true
	_clear_token += 1
	cards = card_list.duplicate()
	z_index = OPEN_Z   # buku terbuka tampil di atas kartu

	var open_tex := GameAssets.get_texture(BOOK_OPEN)
	var book_size := Vector2(BOOK_WIDTH, BOOK_WIDTH * 0.55)
	if open_tex != null:
		book_size.y = BOOK_WIDTH * open_tex.get_height() / open_tex.get_width()

	var vw := get_viewport_rect().size.x
	_open_book = Control.new()
	_open_book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open_book.size = book_size
	_open_book.position = Vector2((vw - book_size.x) / 2.0, BOOK_TOP)
	_open_book.pivot_offset = book_size / 2.0
	add_child(_open_book)

	if open_tex != null:
		var page := TextureRect.new()
		page.texture = open_tex
		page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		page.stretch_mode = TextureRect.STRETCH_SCALE
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.size = book_size
		_open_book.add_child(page)
	else:
		var paper := ColorRect.new()
		paper.color = Color(0.95, 0.92, 0.85)
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.size = book_size
		_open_book.add_child(paper)

	_build_content(book_size)

	# Buku tertutup diganti buku terbuka
	_closed_book.visible = false
	_open_book.scale = Vector2.ONE * 0.7
	_open_book.modulate.a = 0.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_open_book, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_open_book, "modulate:a", 1.0, 0.2)
	_layout_tabs(true, true)


func _build_content(bs: Vector2) -> void:
	# --- Halaman kiri: kartu yang dipilih (berjajar, sedikit bertumpuk kalau banyak) ---
	var lp := Rect2(LEFT_PAGE.position * bs, LEFT_PAGE.size * bs)
	var n := cards.size()
	var csz := CardUI.CARD_SIZE
	var fit := minf(lp.size.y / csz.y, lp.size.x / (csz.x * (1.0 + 0.7 * maxi(0, n - 1)))) * CARD_FIT
	var cw := csz.x * fit
	var step := 0.0
	if n > 1:
		step = minf(cw, (lp.size.x - cw) / (n - 1))
	var total := cw + step * maxi(0, n - 1)
	var x0 := lp.position.x + (lp.size.x - total) / 2.0
	var y0 := lp.position.y + (lp.size.y - csz.y * fit) / 2.0
	for i in n:
		var card_ui := CardUI.new()
		card_ui.setup(cards[i], true)
		card_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_ui.size = csz
		card_ui.pivot_offset = Vector2.ZERO
		card_ui.scale = Vector2.ONE * fit
		card_ui.position = Vector2(x0 + step * i, y0)
		_open_book.add_child(card_ui)

	# --- Halaman kanan: area menggambar + garis panduan ---
	var rp := Rect2(RIGHT_PAGE.position * bs, RIGHT_PAGE.size * bs)
	pad = DrawPad.new()
	pad.position = rp.position
	pad.size = rp.size
	pad.changed.connect(_on_pad_changed)
	pad.stroke_started.connect(_on_stroke_started)
	pad.stroke_finished.connect(_on_stroke_finished)
	_open_book.add_child(pad)

	# Pilih bentuk sesuai level (map)
	var level := clampi(GameAssets.selected_enemy_index, 0, LEVELS.size() - 1)
	var cfg: Dictionary = LEVELS[level]
	var kind: String = cfg["shapes"][randi() % cfg["shapes"].size()]
	var radius := minf(rp.size.x, rp.size.y) / 2.0 * 0.88
	var center := rp.size / 2.0
	var pts := PackedVector2Array()
	for p in _shape_points(kind):
		pts.append(center + p * radius)
	pad.set_shape(pts)
	_tol_px = radius * float(cfg["tol"])
	_need = float(cfg["need"])

	# --- Info akurasi di bawah halaman kanan (tidak ada tombol lagi) ---
	_score_label = Label.new()
	_score_label.position = Vector2(rp.position.x, bs.y * BUTTON_ROW_Y)
	_score_label.size = Vector2(rp.size.x, 36)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 11)
	_score_label.add_theme_color_override("font_color", INK_COLOR)
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open_book.add_child(_score_label)

	_update_score()


# ============================================================
# Tutup buku
# ============================================================
func _close_book(accepted: bool) -> void:
	if not is_open:
		return
	_clear_token += 1   # batalkan timer hapus otomatis yang masih menunggu
	var bonus := 0.0
	if accepted and pad != null:
		bonus = bonus_for(pad.score(_tol_px), _need)

	is_open = false
	z_index = CLOSED_Z   # buku tertutup kembali di belakang kartu
	if _open_book != null:
		_open_book.queue_free()
		_open_book = null
	pad = null
	_score_label = null

	# Kembali ke buku tertutup
	_closed_book.visible = true
	_closed_book.scale = Vector2.ONE * 0.85
	var t := create_tween()
	t.tween_property(_closed_book, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_layout_tabs(false, true)

	if accepted:
		confirmed.emit(bonus)
	else:
		cancelled.emit()


# ============================================================
# Pita: dibuat, diposisikan, dan diisi teks
# ============================================================
func _make_tabs() -> void:
	_tabs_root = Control.new()
	_tabs_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tabs_root.z_index = TAB_Z
	add_child(_tabs_root)

	# [nomor, sisi (-1 kiri / 1 kanan), bisa diklik, tooltip, teks awal]
	var defs := [
		[1, 1, true, "Skip turn", "Skip"],
		[2, 1, true, "Kartu discard", "0"],
		[3, -1, false, "", "0/0"],
		[4, -1, true, "Kartu di deck", "0"],
	]
	var width := _closed_w * TAB_WIDTH_FRAC
	for d in defs:
		var tab := BookTab.new()
		tab.setup(d[0], width, d[1], d[2], d[3])
		tab.label.text = d[4]
		_tabs_root.add_child(tab)
		_tabs[d[0]] = tab
	(_tabs[1] as BookTab).pressed.connect(func(): skip_pressed.emit())


func _book_rect(book_open: bool) -> Rect2:
	if book_open and _open_book != null:
		return Rect2(_open_book.position, _open_book.size)
	return Rect2(_closed_book.position, _closed_book.size)


# Tempelkan pita ke tepi buku (tertutup atau terbuka). Saat buku berganti, pita ikut bergeser.
func _layout_tabs(book_open: bool, animate: bool) -> void:
	if _tabs.is_empty():
		return
	var r := _book_rect(book_open)
	var anchors: Dictionary = TABS_ON_OPEN if book_open else TABS_ON_CLOSED
	var s := r.size.x / _closed_w
	if _tabs_tween != null:
		_tabs_tween.kill()
	if animate:
		_tabs_tween = create_tween()
		_tabs_tween.set_parallel(true)
		_tabs_tween.set_trans(Tween.TRANS_BACK)
		_tabs_tween.set_ease(Tween.EASE_OUT)
	for id in _tabs:
		var tab: BookTab = _tabs[id]
		var a: Vector2 = anchors[id]
		var pos := r.position + r.size * a - tab.base_size / 2.0
		if animate:
			_tabs_tween.tween_property(tab, "position", pos, 0.25)
			_tabs_tween.tween_property(tab, "scale", Vector2.ONE * s, 0.25)
		else:
			tab.position = pos
			tab.scale = Vector2.ONE * s


func _set_tab_text(id: int, text: String) -> void:
	if _tabs.has(id):
		var tab: BookTab = _tabs[id]
		tab.label.text = text


# --- Dipanggil battle.gd untuk memperbarui isi pita ---
func set_ink(current: int, base: int) -> void:
	_set_tab_text(3, "%d/%d" % [current, base])


func set_deck(count: int) -> void:
	_set_tab_text(4, str(count))


func set_discard(count: int) -> void:
	_set_tab_text(2, str(count))


func set_skip_enabled(value: bool) -> void:
	if _tabs.has(1):
		var tab: BookTab = _tabs[1]
		tab.set_enabled(value)


func _on_pad_changed() -> void:
	_update_score()


# Mulai goresan baru: batalkan timer hapus otomatis yang sedang menunggu
func _on_stroke_started() -> void:
	_clear_token += 1


# Goresan selesai: kalau sudah cukup akurat kartu langsung dipakai,
# kalau belum, gambar dihapus otomatis setelah jeda (kecuali ada goresan baru).
func _on_stroke_finished() -> void:
	if not is_open or pad == null:
		return
	var sc := pad.score(_tol_px)
	var ok := not pad.strokes.is_empty()
	if REQUIRE_ACCURACY:
		ok = ok and sc >= _need
	if ok:
		_close_book(true)
		return
	_clear_token += 1
	var token := _clear_token
	await get_tree().create_timer(AUTO_CLEAR_DELAY).timeout
	if token != _clear_token or not is_open or pad == null:
		return
	pad.clear_all()


func _update_score() -> void:
	if pad == null or _score_label == null:
		return
	var sc := pad.score(_tol_px)
	var bonus := bonus_for(sc, _need)
	if REQUIRE_ACCURACY:
		_score_label.text = "Akurasi %d%% (min %d%%)\nBonus +%d%%" % [roundi(sc * 100.0), roundi(_need * 100.0), roundi(bonus * 100.0)]
	else:
		_score_label.text = "Akurasi %d%%\nBonus +%d%%" % [roundi(sc * 100.0), roundi(bonus * 100.0)]
