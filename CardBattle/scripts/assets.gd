@tool
class_name GameAssets
extends RefCounted

# ============================================================
# TEMPAT SEMUA PATH ASSET UI + DATA MUSUH + PROGRES MAP.
# Kalau nama/lokasi file kamu beda, cukup ganti path di sini.
# Kalau file belum ada, game tetap jalan dan menampilkan kotak warna.
# ============================================================

# Background 3 lapisan
const BG_TOP := "res://assets/ui/background_1.png"      # lapisan dasar
const BG_BOTTOM := "res://assets/ui/background_3.png"   # menempel di dasar layar
const BG_OVERLAY := "res://assets/ui/background_2.png"  # menimpa semua background

const PLAYER := "res://assets/ui/Nira.png"
const PLAYER_PORTRAIT := "res://assets/ui/player_hud.png"
const PLAYER_HUD := "res://assets/ui/player_hud.png"   # <- pastikan sama persis dengan nama file
const ENEMY := "res://assets/ui/Square.png"
const ICON_INK := "res://assets/ui/icon_ink.png"
const ICON_DECK := "res://assets/ui/icon_deck.png"
const ICON_DISCARD := "res://assets/ui/icon_discard.png"

# Icon kartu otomatis diambil dari: CARD_FOLDER + id_kartu + ".png"
# contoh: res://assets/cards/tebas.png
# PENTING: isi hanya FOLDER-nya (berakhir dengan "/"), bukan nama file.
const CARD_FOLDER := "res://assets/cards/"

# ============================================================
# BAR HEALTH & SHIELD (gambar berganti sesuai persentase)
# File yang dicari: FOLDER + PREFIX + nomor + ".PNG"
# contoh: res://assets/healt/Healt1.PNG
# ============================================================
const HEALTH_FOLDER := "res://assets/healt/"
const HEALTH_PREFIX := "Healt"
const HEALTH_COUNT := 7
# true  = Healt1 adalah bar PENUH, nomor terakhir adalah bar KOSONG
# false = kebalikannya (Healt1 kosong, nomor terakhir penuh)
const HEALTH_FULL_IS_FIRST := true
const HEALTH_TINT := Color(1.0, 0.15, 0.15)   # warna darah (merah). Ganti Color.WHITE kalau gambar sudah berwarna

const SHIELD_FOLDER := "res://assets/shield/"
const SHIELD_PREFIX := "Shield"
const SHIELD_COUNT := 6
const SHIELD_FULL_IS_FIRST := true            # sama seperti HEALTH_FULL_IS_FIRST
const SHIELD_MAX_DISPLAY := 20                # block sebanyak ini dianggap bar shield penuh
const SHIELD_TINT := Color(1, 1, 1)

# Lokasi file simpanan progres (otomatis dibuat di folder data game)
const SAVE_PATH := "user://progress.cfg"

# Daftar musuh. Akses lewat: GameAssets.enemy_list
# Kalau mau ganti gambar musuh, ubah nilai "image" di bawah.
static var enemy_list := [
	{
		"name": "Circle",
		"hp": 60,
		"attack": 8,
		"image": "res://assets/ui/Circle.png",
		"color": Color(1.0, 0.3, 0.3),
	},
	{
		"name": "Square",
		"hp": 80,
		"attack": 10,
		"image": "res://assets/ui/Square.png",
		"color": Color(0.9, 0.6, 0.2),
	},
	{
		"name": "Triangle",
		"hp": 100,
		"attack": 12,
		"image": "res://assets/ui/Triangle.png",
		"color": Color(0.7, 0.3, 0.9),
	},
]

# Map/musuh untuk battle berikutnya (0 = map 1).
# Nanti scene Map juga bisa mengisi ini sebelum masuk battle.
static var selected_enemy_index := 0

# Penanda supaya file simpanan hanya dibaca sekali per sesi game
static var progress_loaded := false


# ============================================================
# PROGRES MAP
# ============================================================
# Baca progres dari file (hanya sekali per sesi).
static func load_progress() -> void:
	if progress_loaded:
		return
	progress_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var saved := int(cfg.get_value("progress", "stage", 0))
		selected_enemy_index = clampi(saved, 0, enemy_list.size() - 1)


# Simpan progres ke file.
static func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "stage", selected_enemy_index)
	cfg.save(SAVE_PATH)


# Apakah map yang sedang dimainkan adalah map terakhir?
static func is_last_stage() -> bool:
	return selected_enemy_index >= enemy_list.size() - 1


# Naik ke map selanjutnya lalu simpan.
static func advance_stage() -> void:
	selected_enemy_index = mini(selected_enemy_index + 1, enemy_list.size() - 1)
	save_progress()


# Kembali ke map 1 lalu simpan.
static func reset_progress() -> void:
	selected_enemy_index = 0
	save_progress()


# ============================================================
# GAMBAR
# ============================================================
static func get_texture(path: String) -> Texture2D:
	if path == "":
		return null
	# Cara normal: file sudah ter-import oleh Godot
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# Cadangan 1: ekstensi huruf besar (mis. tebas.PNG)
	var upper_path := path.get_basename() + ".PNG"
	if ResourceLoader.exists(upper_path):
		return load(upper_path) as Texture2D
	# Cadangan 2: file ada tapi belum ter-import, muat langsung dari disk
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			return ImageTexture.create_from_image(img)
	push_warning("GameAssets: gambar tidak ditemukan -> " + path)
	return null


# Pilih gambar bar berdasarkan persentase (0.0 - 1.0).
static func _get_stage_texture(folder: String, prefix: String, count: int, percent: float, full_is_first: bool) -> Texture2D:
	var p := clampf(percent, 0.0, 1.0)
	var step := 0
	if full_is_first:
		step = roundi((1.0 - p) * (count - 1))
	else:
		step = roundi(p * (count - 1))
	return get_texture("%s%s%d.PNG" % [folder, prefix, step + 1])


static func get_health_texture(percent: float) -> Texture2D:
	return _get_stage_texture(HEALTH_FOLDER, HEALTH_PREFIX, HEALTH_COUNT, percent, HEALTH_FULL_IS_FIRST)


static func get_shield_texture(percent: float) -> Texture2D:
	return _get_stage_texture(SHIELD_FOLDER, SHIELD_PREFIX, SHIELD_COUNT, percent, SHIELD_FULL_IS_FIRST)


# Mengembalikan TextureRect kalau gambar ada, kalau tidak ada: kotak warna placeholder.
static func make_visual(path: String, fallback_color: Color, size: Vector2) -> Control:
	var tex := get_texture(path)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.custom_minimum_size = size
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var box := ColorRect.new()
	box.color = fallback_color
	box.custom_minimum_size = size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box
