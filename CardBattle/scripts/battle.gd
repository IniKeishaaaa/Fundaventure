@tool
extends Control

# ===== PENGATURAN (sesuai dokumen desain) =====
const BASE_INK := 3              # Ink poin dasar, di-reset tiap turn
const MAX_HAND := 15             # Maksimal kartu di tangan
const DRAW_PER_TURN := 5        # Jumlah kartu ditarik tiap turn (bebas kamu ubah)
const RESHUFFLE_THRESHOLD := 5   # Sisa kartu di deck <= ini -> discard pile balik ke deck

# Lebar area kartu di tangan. Dibuat sebatas lebar buku supaya tidak menabrak pita di kiri dan kanan.
# Kartu yang lebih banyak akan saling menumpuk. Besarkan angka ini kalau ingin kartu lebih renggang.
const HAND_WIDTH := 499.0

# ===== FONT =====
# Font dipasang ke semua teks (kartu, label player/musuh, tombol, pita buku).
# Ganti path ini kalau mau memakai font lain.
const GAME_FONT := "res://assets/fonts/PatrickHand-Regular.ttf"

# ===== BAR HP MUSUH =====
# Bingkai bar = gambar di folder barenemy. Isi bar = gambar Healt1-7 (folder healt, sama seperti player).
const ENEMY_BAR_FRAME := "res://assets/barbawah/Healt.PNG"   # dipakai bar musuh DAN bar player
const ENEMY_BAR_WIDTH := 200.0              # lebar bar musuh di layar
const ENEMY_FILL_POS := Vector2(0.05, 0.25) # posisi isi bar di dalam bingkai (persen: x, y)
const ENEMY_FILL_WIDTH := 0.9               # lebar isi bar (persen dari lebar bingkai)

# Area di dalam bingkai tempat isi bar (bagian merah yang terlihat) ditempatkan.
# Rect2(x, y, lebar, tinggi) dalam PERSEN ukuran bingkai. Tinggi hanya dipakai untuk menentukan titik tengah vertikal.
# Ingin bar lebih panjang? Besarkan lebar. Ingin geser? Ubah x / y.
const ENEMY_FILL_AREA := Rect2(0.03, 0.2, 0.94, 0.6)

# Ukuran gambar musuh, dan posisi bar HP musuh di atas kepalanya.
# ENEMY_BAR_OFFSET = geser tambahan dari posisi dasar (tepat di atas gambar, rata tengah).
# y lebih kecil = bar lebih naik, y lebih besar = bar lebih turun. x untuk geser kiri/kanan.
const ENEMY_VISUAL_SIZE := Vector2(160, 200)
const ENEMY_BAR_OFFSET := Vector2(0, -6)

# ===== MUSUH / MAP =====
# Daftar musuh ada di GameAssets.enemy_list.
# Map yang dimainkan = GameAssets.selected_enemy_index (0 = map 1).
var enemy_index := 0

# ===== STATE KARTU =====
var deck: Array[CardData] = []      # Card in deck
var hand: Array[CardData] = []      # Card in hand
var discard: Array[CardData] = []   # Discard pile
var ink := BASE_INK

# ===== STATE BATTLE (sederhana, bisa kamu ganti nanti) =====
var player_hp := 50
var player_max_hp := 50
var player_block := 0
var player_strength := 0
var enemy_name := ""
var enemy_hp := 60
var enemy_max_hp := 60
var enemy_attack := 8
var enemy_weak := 0
var game_over := false

# ===== STATE PEMILIHAN KARTU / BUKU =====
var pending_cards: Array[CardData] = []  # kartu yang sedang ada di buku
var hand_backup: Array[CardData] = []    # isi tangan sebelum buku dibuka (untuk Batal)

# ===== NODE UI =====
var hp_bar: ProgressBar          # bar cadangan (dipakai kalau gambar health tidak ada)
var health_rect: TextureRect     # bar health dari gambar
var shield_rect: TextureRect     # bar shield dari gambar
var health_width := 0.0
var shield_width := 0.0
var player_label: Label
var enemy_label: Label
var message_label: Label
var hand_box: HBoxContainer
var restart_button: Button
# (tidak ada tombol Buka Buku: buku terbuka otomatis)     # tombol "Buka Buku" (muncul setelah ada kartu dipilih)
var enemy_box: VBoxContainer
var enemy_visual: Control
var player_visual: Control       # gambar karakter player (target VFX)
var enemy_bar: Control           # bar HP musuh (bingkai + isi)
var enemy_bar_fill: TextureRect  # isi bar HP musuh (gambar berganti sesuai persentase)
var book: BookUI                 # buku (tertutup saat idle, terbuka saat menggambar)


func _ready() -> void:
	if not Engine.is_editor_hint():
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		GameAssets.load_progress()   # Baca progres map yang tersimpan
	_apply_font()
	_load_enemy_stats(GameAssets.selected_enemy_index)
	_build_ui()
	deck = CardDatabase.build_starter_deck()
	deck.shuffle()
	_start_turn()


# Pasang font ke semua teks (kartu, label player, tombol, pita buku).
# Semua UI dibuat sebagai anak node ini, jadi otomatis ikut tema ini.
func _apply_font() -> void:
	var font: Font = load(GAME_FONT)
	if font == null:
		return
	var t := Theme.new()
	t.default_font = font
	theme = t


# ============================================================
# MUSUH
# ============================================================
func _load_enemy_stats(index: int) -> void:
	enemy_index = clampi(index, 0, GameAssets.enemy_list.size() - 1)
	var e: Dictionary = GameAssets.enemy_list[enemy_index]
	enemy_name = e["name"]
	enemy_max_hp = e["hp"]
	enemy_hp = enemy_max_hp
	enemy_attack = e["attack"]
	enemy_weak = 0


func _make_enemy_visual() -> Control:
	var e: Dictionary = GameAssets.enemy_list[enemy_index]
	return GameAssets.make_visual(e["image"], e["color"], ENEMY_VISUAL_SIZE)


# ============================================================
# ALUR TURN
# ============================================================
func _start_turn() -> void:
	ink = BASE_INK  # Ink kembali ke 3 tiap turn
	_draw_cards(DRAW_PER_TURN)
	_show_message("Map %d - Giliran kamu" % (enemy_index + 1))
	_refresh_all()


func _on_end_turn_pressed() -> void:
	if game_over:
		return
	if book != null and book.is_open:
		return
	# Semua kartu yang masih di tangan masuk discard pile
	discard.append_array(hand)
	hand.clear()
	_enemy_turn()
	if game_over:
		_refresh_all()
		return
	_start_turn()


func _enemy_turn() -> void:
	var dmg := enemy_attack
	if enemy_weak > 0:
		dmg = int(enemy_attack * 0.5)
		enemy_weak -= 1
	var absorbed := mini(player_block, dmg)
	var taken := dmg - absorbed
	player_hp = maxi(0, player_hp - taken)
	player_block = 0
	if taken > 0:
		_fx_attack(player_visual, taken)   # VFX + angka damage di player
	if absorbed > 0:
		_fx_shield(player_visual)          # VFX: block menahan serangan
		if taken == 0:
			_fx_number(player_visual, "0") # semua serangan tertahan
	_check_end()


# ============================================================
# DECK / HAND / DISCARD
# ============================================================
func _draw_cards(count: int) -> void:
	# Aturan: kalau sisa deck <= 5, discard pile balik ke deck lalu dikocok,
	# sehingga kartu yang ditarik ke tangan acak dari hasil discard pile.
	if deck.size() <= RESHUFFLE_THRESHOLD:
		_recycle_discard()
	for i in count:
		if deck.is_empty():
			_recycle_discard()
			if deck.is_empty():
				break
		var card: CardData = deck.pop_back()
		if hand.size() < MAX_HAND:
			hand.append(card)
		else:
			discard.append(card)  # Tangan penuh (15): kartu langsung terbuang


func _recycle_discard() -> void:
	if discard.is_empty():
		return
	deck.append_array(discard)
	discard.clear()
	deck.shuffle()


# ============================================================
# PILIH KARTU -> BUKU TERBUKA -> GAMBAR -> SELESAI
# Satu kartu = satu gambar. Klik kartu, buku langsung terbuka untuk kartu itu saja.
# ============================================================
func _on_card_pressed(card_ui: CardUI) -> void:
	if game_over or book == null or book.is_open:
		return
	var card := card_ui.data
	if card.ink_cost > ink:
		_show_message("Ink poin tidak cukup!")
		return
	# Kartu keluar dari tangan sementara, buku dibuka untuk kartu ini saja
	hand_backup = hand.duplicate()
	pending_cards.assign([card])
	hand.erase(card)
	book.set_skip_enabled(false)
	book.open(pending_cards)
	_show_message("Gambar bentuknya di halaman kanan, lalu tekan Selesai")
	_refresh_all()


# bonus = tambahan damage/block dari akurasi gambar (0.0 - 0.5)
func _on_book_confirmed(bonus: float) -> void:
	var cards := pending_cards.duplicate()
	pending_cards.clear()
	for card in cards:
		ink -= card.ink_cost
		discard.append(card)  # Kartu yang dipakai masuk discard pile
		_apply_effect(card, bonus)
	_check_end()
	if not game_over:
		_show_message("Map %d - Giliran kamu" % (enemy_index + 1))
		book.set_skip_enabled(true)
	_refresh_all()


func _on_book_cancelled() -> void:
	hand = hand_backup.duplicate()   # kartu kembali ke tangan seperti semula
	pending_cards.clear()
	book.set_skip_enabled(true)
	_show_message("Map %d - Giliran kamu" % (enemy_index + 1))
	_refresh_all()


# Bonus akurasi hanya menambah damage (ofensif) dan block (defensif).
func _apply_effect(card: CardData, bonus: float) -> String:
	var bonus_text := ""
	if bonus > 0.0:
		bonus_text = " (+%d%%)" % roundi(bonus * 100.0)
	match card.type:
		CardData.Type.OFFENSIVE:
			var dmg := roundi(card.value * (1.0 + bonus)) + player_strength  # Buff menguatkan kartu ofensif
			enemy_hp = maxi(0, enemy_hp - dmg)
			_fx_attack(enemy_visual, dmg)   # VFX: tebasan + angka damage di musuh
			return "%s: musuh kena %d damage%s" % [card.display_name, dmg, bonus_text]
		CardData.Type.DEFENSIVE:
			var blk := roundi(card.value * (1.0 + bonus))
			player_block += blk
			_fx_shield(player_visual, blk)   # VFX: perisai + angka block di player
			return "%s: +%d block%s" % [card.display_name, blk, bonus_text]
		CardData.Type.BUFF:
			player_strength += card.value
			return "%s: serangan +%d" % [card.display_name, card.value]
		CardData.Type.DEBUFF:
			enemy_weak += card.value
			return "%s: musuh lemah %d turn" % [card.display_name, card.value]
	return ""


# ============================================================
# VFX (hitam putih, lihat BattleVFX.gd)
# ============================================================
func _center_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


# amount >= 0: angka damage ("-6") ikut muncul di target
func _fx_attack(target: Control, amount: int = -1) -> void:
	if target == null:
		return
	BattleVFX.attack(self, _center_of(target))
	BattleVFX.hit_shake(target)
	if amount >= 0:
		BattleVFX.number(self, _center_of(target), "-%d" % amount)


# amount > 0: angka block ("+10") ikut muncul di target
func _fx_shield(target: Control, amount: int = -1) -> void:
	if target == null:
		return
	BattleVFX.shield(self, _center_of(target))
	if amount > 0:
		BattleVFX.number(self, _center_of(target), "+%d" % amount)


func _fx_number(target: Control, text: String) -> void:
	if target == null:
		return
	BattleVFX.number(self, _center_of(target), text)


func _check_end() -> void:
	if game_over:
		return
	if enemy_hp <= 0:
		_finish("MENANG!", true)
	elif player_hp <= 0:
		_finish("KALAH...", false)


func _finish(text: String, won: bool) -> void:
	game_over = true
	book.set_skip_enabled(false)
	if won:
		if GameAssets.is_last_stage():
			# Semua map sudah selesai: progres balik ke map 1
			GameAssets.reset_progress()
			text += " Semua map selesai!"
			restart_button.text = "Mulai dari Map 1"
		else:
			# Naik ke map selanjutnya dan simpan progres
			GameAssets.advance_stage()
			restart_button.text = "Map Selanjutnya"
	else:
		# Kalah: balik ke map 1 dan simpan
		GameAssets.reset_progress()
		restart_button.text = "Main Lagi (Map 1)"
	message_label.text = text
	restart_button.visible = true


# ============================================================
# UI: PEMBARUAN TAMPILAN
# ============================================================
func _show_message(text: String) -> void:
	if message_label:
		message_label.text = text


func _refresh_all() -> void:
	# Ink yang ditampilkan = sisa ink setelah dikurangi kartu yang ditandai
	# Pita di sisi buku: 3 = ink, 4 = deck, 2 = discard
	book.set_ink(ink, BASE_INK)
	book.set_deck(deck.size())
	book.set_discard(discard.size())
	_update_hud_bars()
	_update_enemy_bar()
	player_label.text = "Player\nBlock %d  ATK +%d" % [player_block, player_strength]
	enemy_label.text = enemy_name
	if enemy_weak > 0:
		enemy_label.text += "  (Lemah %d)" % enemy_weak
	_refresh_hand()


# Bar HP musuh: bingkai di belakang, isi bar (gambar folder healt) di depan.
func _make_enemy_bar() -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var bar_h := 24.0
	var frame_tex := GameAssets.get_texture(ENEMY_BAR_FRAME)
	if frame_tex != null:
		bar_h = ENEMY_BAR_WIDTH * frame_tex.get_height() / frame_tex.get_width()
	holder.custom_minimum_size = Vector2(ENEMY_BAR_WIDTH, bar_h)
	holder.size = holder.custom_minimum_size

	if frame_tex != null:
		var frame := TextureRect.new()
		frame.texture = frame_tex
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.size = Vector2(ENEMY_BAR_WIDTH, bar_h)
		holder.add_child(frame)

	var fill := TextureRect.new()
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.modulate = GameAssets.HEALTH_TINT   # warna darah merah
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)
	holder.set_meta("fill", fill)   # supaya isi bar bisa diambil lagi oleh pemanggil
	return holder


func _update_enemy_bar() -> void:
	var percent := float(enemy_hp) / float(maxi(1, enemy_max_hp))
	_update_hp_bar(enemy_bar, enemy_bar_fill, percent)


# Ganti gambar isi bar sesuai persentase (0.0 - 1.0) dan tempatkan di dalam bingkai.
func _update_hp_bar(bar: Control, fill: TextureRect, percent: float) -> void:
	if bar == null or fill == null:
		return
	var tex := GameAssets.get_health_texture(percent)
	if tex == null:
		return
	var holder_size := bar.custom_minimum_size
	var area := Rect2(holder_size * ENEMY_FILL_AREA.position, holder_size * ENEMY_FILL_AREA.size)
	# Bagian gambar yang benar-benar berwarna (tanpa ruang transparan di tepinya)
	var used := _health_used_rect()
	var k := area.size.x / used.size.x
	fill.texture = tex
	fill.size = tex.get_size() * k
	fill.position = Vector2(
		area.position.x - used.position.x * k,
		area.get_center().y - (used.position.y + used.size.y * 0.5) * k)


# Area berwarna pada gambar bar penuh (Healt1), dihitung sekali lalu disimpan.
var _health_used := Rect2()

func _health_used_rect() -> Rect2:
	if _health_used.size.x > 0.0:
		return _health_used
	var full := GameAssets.get_health_texture(1.0)
	var rect := Rect2(Vector2.ZERO, full.get_size())
	var img := full.get_image()
	if img != null:
		var r := img.get_used_rect()
		if r.size.x > 0:
			rect = Rect2(r)
	_health_used = rect
	return rect


# Ganti gambar bar health & shield sesuai persentase.
func _update_hud_bars() -> void:
	var hp_percent := float(player_hp) / float(maxi(1, player_max_hp))
	if health_rect != null:
		_set_bar_image(health_rect, GameAssets.get_health_texture(hp_percent), health_width)
	else:
		hp_bar.max_value = player_max_hp
		hp_bar.value = player_hp
	if shield_rect != null:
		var shield_percent := float(player_block) / float(GameAssets.SHIELD_MAX_DISPLAY)
		_set_bar_image(shield_rect, GameAssets.get_shield_texture(shield_percent), shield_width)


func _set_bar_image(rect: TextureRect, tex: Texture2D, width: float) -> void:
	if tex == null:
		return
	rect.texture = tex
	rect.custom_minimum_size = Vector2(width, width * tex.get_height() / tex.get_width())


func _refresh_hand() -> void:
	for child in hand_box.get_children():
		hand_box.remove_child(child)
		child.queue_free()
	var n := hand.size()
	var step := 110.0
	if n > 1:
		step = minf(110.0, (HAND_WIDTH - CardUI.CARD_SIZE.x) / (n - 1))
	# Separation negatif = kartu bertumpuk (supaya 15 kartu muat di layar)
	hand_box.add_theme_constant_override("separation", int(step - 100.0))
	for card in hand:
		var ui := CardUI.new()
		ui.setup(card, card.ink_cost <= ink)
		ui.pressed.connect(_on_card_pressed.bind(ui))
		hand_box.add_child(ui)


# ============================================================
# UI: MEMBANGUN TAMPILAN
# ============================================================
func _build_ui() -> void:
	# --- Background (3 lapisan: 1 -> 3 -> 2) ---
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.13)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Lapisan 1: background_1
	var top_tex := GameAssets.get_texture(GameAssets.BG_TOP)
	if top_tex != null:
		var bg_top := TextureRect.new()
		bg_top.texture = top_tex
		bg_top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_top.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_top)
		bg_top.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Lapisan 2: background_3, menempel di bawah layar
	var bottom_tex := GameAssets.get_texture(GameAssets.BG_BOTTOM)
	if bottom_tex != null:
		var bg_bottom := TextureRect.new()
		bg_bottom.texture = bottom_tex
		bg_bottom.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		bg_bottom.stretch_mode = TextureRect.STRETCH_SCALE
		bg_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_bottom)
		bg_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		bg_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Lapisan 3: background_2, menimpa semua background
	var overlay_tex := GameAssets.get_texture(GameAssets.BG_OVERLAY)
	if overlay_tex != null:
		var bg_overlay := TextureRect.new()
		bg_overlay.texture = overlay_tex
		bg_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_overlay.stretch_mode = TextureRect.STRETCH_SCALE
		bg_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_overlay)
		bg_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# --- Pesan di atas ---
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 20)
	add_child(message_label)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	message_label.offset_top = 15
	message_label.offset_bottom = 55

	# --- Area karakter (player kiri, musuh kanan) ---
	# Turunkan/naikkan kedua angka ini (selisih tetap) untuk menyesuaikan garis pijakan
	var stage := HBoxContainer.new()
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", 320)
	add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stage.offset_top = 120
	stage.offset_bottom = 430

	var player_box := VBoxContainer.new()
	var player_gap := Control.new()
	player_gap.custom_minimum_size = Vector2(0, 5)   # sama seperti musuh supaya kedua bar sejajar
	player_box.add_child(player_gap)
	player_visual = GameAssets.make_visual(GameAssets.PLAYER, Color(0.3, 0.6, 1.0), Vector2(160, 200))
	player_box.add_child(player_visual)
	player_label = Label.new()
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_box.add_child(player_label)
	stage.add_child(player_box)

	enemy_box = VBoxContainer.new()
	var enemy_gap := Control.new()
	enemy_gap.custom_minimum_size = Vector2(0, 5)   # turunkan musuh sedikit, ubah sesuai selera
	enemy_box.add_child(enemy_gap)
	enemy_visual = _make_enemy_visual()
	enemy_box.add_child(enemy_visual)
	# Bar HP musuh ditaruh di atas kepala: jadi anak dari gambar musuh, rata tengah, tepat di atasnya
	enemy_bar = _make_enemy_bar()
	enemy_bar_fill = enemy_bar.get_meta("fill")
	enemy_visual.add_child(enemy_bar)
	enemy_bar.position = Vector2(
		(ENEMY_VISUAL_SIZE.x - enemy_bar.custom_minimum_size.x) / 2.0,
		-enemy_bar.custom_minimum_size.y) + ENEMY_BAR_OFFSET
	enemy_label = Label.new()
	enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_box.add_child(enemy_label)
	stage.add_child(enemy_box)

	# --- Tengah bawah: kartu di tangan ---
	hand_box = HBoxContainer.new()
	hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(hand_box)
	hand_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hand_box.offset_left = 150
	hand_box.offset_right = -160
	hand_box.offset_top = -190
	hand_box.offset_bottom = -10
	hand_box.z_index = 5   # kartu di tangan tampil di atas buku tertutup

	# --- HUD player di pojok kiri atas ---
	_build_player_hud()

	# --- Buku (tertutup saat idle, terbuka saat menggambar) ---
	book = BookUI.new()
	add_child(book)
	book.setup()
	book.confirmed.connect(_on_book_confirmed)
	book.cancelled.connect(_on_book_cancelled)
	book.skip_pressed.connect(_on_end_turn_pressed)   # pita 1 = skip turn
	# --- Tombol lanjut/ulang (muncul saat game selesai) ---
	# Teks tombol diatur di _finish(): Map Selanjutnya / Main Lagi (Map 1)
	restart_button = Button.new()
	restart_button.text = "Main Lagi"
	restart_button.visible = false
	restart_button.custom_minimum_size = Vector2(200, 50)
	restart_button.pressed.connect(func(): get_tree().reload_current_scene())
	add_child(restart_button)
	restart_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	restart_button.z_index = 30   # selalu di atas buku


func _build_player_hud() -> void:
	# ===== UKURAN & POSISI HUD =====
	var hud_width := 300.0                 # ubah angka ini untuk memperbesar/memperkecil HUD (dulu 420)
	var hud_pos := Vector2(-40, 2)         # geser HUD. y lebih kecil = lebih ke atas, x negatif = lebih ke kiri
	var s := hud_width / 420.0             # skala otomatis untuk bar & slot di bawah

	var hud := Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.position = hud_pos
	add_child(hud)

	# Gambar HUD kamu (potret + bingkai bar), paling belakang
	var frame_tex := GameAssets.get_texture(GameAssets.PLAYER_HUD)
	if frame_tex != null:
		var frame := TextureRect.new()
		frame.texture = frame_tex
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		frame.custom_minimum_size = Vector2(hud_width, hud_width * frame_tex.get_height() / frame_tex.get_width())
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(frame)
	else:
		# Placeholder kalau gambar belum ada
		hud.add_child(GameAssets.make_visual("", Color(0.3, 0.6, 1.0), Vector2(110, 110) * s))

	# ===== BAR: health (atas), shield (bawah health), lalu 5 slot status =====
	var bar_pos := Vector2(150, 68) * s    # posisi bar health (x = kiri/kanan, y = atas/bawah)
	health_width = 237.0 * s               # lebar bar health
	shield_width = health_width * 0.7      # lebar bar shield (0.5 = setengah health, 1.0 = sama lebar)

	var bars := VBoxContainer.new()
	bars.position = bar_pos
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_theme_constant_override("separation", int(4 * s))
	hud.add_child(bars)

	# --- Health ---
	var health_tex := GameAssets.get_health_texture(1.0)
	if health_tex != null:
		health_rect = TextureRect.new()
		health_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		health_rect.stretch_mode = TextureRect.STRETCH_SCALE
		health_rect.modulate = GameAssets.HEALTH_TINT   # warna darah merah
		health_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		health_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bars.add_child(health_rect)
		_set_bar_image(health_rect, health_tex, health_width)
	else:
		# Cadangan: bar biasa berwarna merah kalau gambar health tidak ditemukan
		hp_bar = ProgressBar.new()
		hp_bar.show_percentage = false
		hp_bar.custom_minimum_size = Vector2(health_width, 27.0 * s)
		hp_bar.max_value = player_max_hp
		hp_bar.value = player_hp
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.85, 0.1, 0.1)
		hp_bar.add_theme_stylebox_override("fill", fill)
		bars.add_child(hp_bar)

	# hp_bar tetap dibuat (tersembunyi) supaya tidak error kalau health_rect dipakai
	if hp_bar == null:
		hp_bar = ProgressBar.new()
		hp_bar.visible = false

	# --- Shield (kecil, di bawah health) ---
	var shield_tex := GameAssets.get_shield_texture(0.0)
	if shield_tex != null:
		shield_rect = TextureRect.new()
		shield_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shield_rect.stretch_mode = TextureRect.STRETCH_SCALE
		shield_rect.modulate = GameAssets.SHIELD_TINT
		shield_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		shield_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bars.add_child(shield_rect)
		_set_bar_image(shield_rect, shield_tex, shield_width)

	# --- 5 slot status (di bawah shield) ---
	var slot_size := Vector2(26, 20) * s   # ukuran tiap slot
	var slot_gap := int(7 * s)             # jarak antar slot

	var slots := HBoxContainer.new()
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.add_theme_constant_override("separation", slot_gap)
	bars.add_child(slots)
	for i in 5:
		slots.add_child(GameAssets.make_visual("", Color(1, 1, 1, 0.15), slot_size))
