@tool
class_name CardDatabase
extends RefCounted

# Setiap kartu dibuat sebagai instance BARU supaya tiap kartu di deck berdiri sendiri.
# Icon kartu otomatis: res://assets/cards/<id>.png  (id = parameter pertama di bawah)

static func _make(id: String, card_name: String, cost: int, type: CardData.Type, value: int, desc: String) -> CardData:
	var c := CardData.new()
	c.id = id
	c.display_name = card_name
	c.ink_cost = cost
	c.type = type
	c.value = value
	c.description = desc
	c.icon_path = GameAssets.CARD_FOLDER + id + ".png"
	return c


static func tebas() -> CardData:
	return _make("tebas", "Tebas", 1, CardData.Type.OFFENSIVE, 6, "Beri 6 damage")

static func tusukan() -> CardData:
	return _make("tusukan", "Tusukan", 2, CardData.Type.OFFENSIVE, 11, "Beri 11 damage")

static func perisai_tinta() -> CardData:
	return _make("perisai_tinta", "Perisai Tinta", 1, CardData.Type.DEFENSIVE, 5, "Dapat 5 block")

static func dinding_tinta() -> CardData:
	return _make("dinding_tinta", "Dinding Tinta", 2, CardData.Type.DEFENSIVE, 10, "Dapat 10 block")

static func semangat() -> CardData:
	return _make("semangat", "Semangat", 1, CardData.Type.BUFF, 2, "Serangan +2 permanen")

static func kutukan() -> CardData:
	return _make("kutukan", "Kutukan", 1, CardData.Type.DEBUFF, 2, "Musuh lemah 2 turn")


static func build_starter_deck() -> Array[CardData]:
	var cards: Array[CardData] = []
	for i in 6:
		cards.append(tebas())
	for i in 3:
		cards.append(tusukan())
	for i in 4:
		cards.append(perisai_tinta())
	for i in 2:
		cards.append(dinding_tinta())
	for i in 3:
		cards.append(semangat())
	for i in 2:
		cards.append(kutukan())
	return cards
