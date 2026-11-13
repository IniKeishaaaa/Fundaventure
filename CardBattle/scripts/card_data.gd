@tool
class_name CardData
extends Resource

# 4 tipe dasar kartu
enum Type { OFFENSIVE, DEFENSIVE, BUFF, DEBUFF }

@export var id: String = ""
@export var display_name: String = ""
@export var ink_cost: int = 1
@export var type: Type = Type.OFFENSIVE
@export var value: int = 0
@export var description: String = ""
@export var icon_path: String = ""


static func type_label(t: Type) -> String:
	match t:
		Type.OFFENSIVE:
			return "Ofensif"
		Type.DEFENSIVE:
			return "Defensif"
		Type.BUFF:
			return "Buff"
		Type.DEBUFF:
			return "Debuff"
	return ""


static func type_color(t: Type) -> Color:
	match t:
		Type.OFFENSIVE:
			return Color(1.0, 0.55, 0.55)
		Type.DEFENSIVE:
			return Color(0.55, 0.75, 1.0)
		Type.BUFF:
			return Color(0.6, 1.0, 0.6)
		Type.DEBUFF:
			return Color(0.8, 0.6, 1.0)
	return Color.WHITE
