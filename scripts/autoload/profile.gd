extends Node
## Player profile: coins, unlockables, equipped cosmetics, scores and achievements (user://profile.json).

signal coins_changed(coins: int)
signal item_unlocked(id: String)
signal item_equipped(category: String, id: String)

const PATH := "user://profile.json"

## category: led (controller light colors), drum (drum skin), notes (note skin), theme (stage look), title (player title)
const CATALOG := [
	{"id": "led_red", "category": "led", "name": "Fire Red", "price": 0, "color": Color(1, 0.05, 0.05), "desc": "Classic Don red."},
	{"id": "led_blue", "category": "led", "name": "Deep Blue", "price": 0, "color": Color(0.05, 0.2, 1), "desc": "Classic Ka blue."},
	{"id": "led_green", "category": "led", "name": "Matcha Green", "price": 300, "color": Color(0.05, 1, 0.1), "desc": "Easy for the camera to see."},
	{"id": "led_magenta", "category": "led", "name": "Sakura Magenta", "price": 400, "color": Color(1, 0.05, 0.8), "desc": "Bright and distinct."},
	{"id": "led_cyan", "category": "led", "name": "Ice Cyan", "price": 400, "color": Color(0.05, 0.9, 1), "desc": "Cool and calm."},
	{"id": "led_yellow", "category": "led", "name": "Festival Yellow", "price": 500, "color": Color(1, 0.85, 0.05), "desc": "Warm lantern glow."},
	{"id": "led_orange", "category": "led", "name": "Sunset Orange", "price": 500, "color": Color(1, 0.4, 0.02), "desc": "Fiery."},
	{"id": "led_purple", "category": "led", "name": "Royal Purple", "price": 600, "color": Color(0.55, 0.05, 1), "desc": "Regal."},
	{"id": "led_white", "category": "led", "name": "Pure White", "price": 800, "color": Color(1, 1, 1), "desc": "Not trackable by the camera (IMU-only mode)."},
	{"id": "led_rainbow", "category": "led", "name": "Rainbow Cycle", "price": 1500, "color": Color(1, 0.5, 0.5), "desc": "Cycles colors in menus; uses your hand color during play.", "achievement": "fc_hard"},
	{"id": "drum_classic", "category": "drum", "name": "Classic Taiko", "price": 0, "desc": "Wood and rope."},
	{"id": "drum_sakura", "category": "drum", "name": "Sakura", "price": 400, "desc": "Pink blossom finish."},
	{"id": "drum_neon", "category": "drum", "name": "Neon", "price": 600, "desc": "Glowing edges."},
	{"id": "drum_gold", "category": "drum", "name": "Golden", "price": 1200, "desc": "For champions.", "achievement": "clear_all"},
	{"id": "notes_classic", "category": "notes", "name": "Classic Notes", "price": 0, "desc": "Red don, blue ka."},
	{"id": "notes_pastel", "category": "notes", "name": "Pastel Notes", "price": 300, "desc": "Soft colors."},
	{"id": "notes_high_contrast", "category": "notes", "name": "High Contrast", "price": 300, "desc": "Maximum readability."},
	{"id": "theme_festival", "category": "theme", "name": "Festival", "price": 0, "desc": "Warm evening festival."},
	{"id": "theme_night", "category": "theme", "name": "Midnight", "price": 500, "desc": "Dark stage, bright notes."},
	{"id": "theme_ocean", "category": "theme", "name": "Ocean", "price": 500, "desc": "Cool blue waves."},
	{"id": "theme_dojo", "category": "theme", "name": "Dojo", "price": 900, "desc": "Minimal training hall.", "achievement": "plays_25"},
	{"id": "title_newcomer", "category": "title", "name": "Newcomer", "price": 0, "desc": "Everyone starts here."},
	{"id": "title_drummer", "category": "title", "name": "Drummer", "price": 200, "desc": "You have rhythm."},
	{"id": "title_fc", "category": "title", "name": "Full Combo Master", "price": 0, "desc": "Earned by a full combo.", "achievement": "fc_any"},
	{"id": "title_ss", "category": "title", "name": "Perfectionist", "price": 0, "desc": "Earned by an SS rank.", "achievement": "ss_any"},
	{"id": "title_taiko_god", "category": "title", "name": "Taiko God", "price": 5000, "desc": "Nothing left to prove."},
]

const ACHIEVEMENTS := {
	"fc_any": "Full combo on any song",
	"ss_any": "SS rank on any song",
	"fc_hard": "Full combo on a Hard chart",
	"clear_all": "Clear every bundled song",
	"plays_25": "Play 25 songs",
	"combo_100": "Reach a 100 combo",
	"balloon_10": "Pop 10 balloons",
}

var coins: int = 0
var unlocked: Dictionary = {}
var equipped: Dictionary = {"led_left": "led_red", "led_right": "led_blue", "drum": "drum_classic", "notes": "notes_classic", "theme": "theme_festival", "title": "title_newcomer"}
var scores: Dictionary = {}
var achievements: Dictionary = {}
var stats: Dictionary = {"plays": 0, "greats": 0, "oks": 0, "misses": 0, "balloons": 0, "best_combo": 0, "coins_earned": 0}


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	for item in CATALOG:
		if int(item.price) == 0 and not item.has("achievement"):
			unlocked[item.id] = true
	if FileAccess.file_exists(PATH):
		var txt := FileAccess.get_file_as_string(PATH)
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary:
			coins = int(parsed.get("coins", 0))
			for k in parsed.get("unlocked", {}):
				unlocked[k] = true
			var eq: Dictionary = parsed.get("equipped", {})
			for k in eq:
				equipped[k] = str(eq[k])
			scores = parsed.get("scores", {})
			achievements = parsed.get("achievements", {})
			var st: Dictionary = parsed.get("stats", {})
			for k in st:
				stats[k] = st[k]
	# make sure equipped items are valid
	for slot in equipped:
		if not unlocked.has(equipped[slot]):
			equipped[slot] = _default_for_slot(slot)


func _default_for_slot(slot: String) -> String:
	match slot:
		"led_left": return "led_red"
		"led_right": return "led_blue"
		"drum": return "drum_classic"
		"notes": return "notes_classic"
		"theme": return "theme_festival"
		_: return "title_newcomer"


func save() -> void:
	var data := {"coins": coins, "unlocked": unlocked, "equipped": equipped, "scores": scores, "achievements": achievements, "stats": stats}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func item(id: String) -> Dictionary:
	for it in CATALOG:
		if it.id == id:
			return it
	return {}


func items_in(category: String) -> Array:
	var out := []
	for it in CATALOG:
		if it.category == category:
			out.append(it)
	return out


func has(id: String) -> bool:
	return unlocked.has(id)


func can_buy(id: String) -> bool:
	var it := item(id)
	if it.is_empty() or has(id):
		return false
	if it.has("achievement"):
		return false
	return coins >= int(it.price)


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	coins -= int(item(id).price)
	unlocked[id] = true
	save()
	coins_changed.emit(coins)
	item_unlocked.emit(id)
	return true


func equip(id: String) -> bool:
	var it := item(id)
	if it.is_empty() or not has(id):
		return false
	var slot: String = it.category
	if slot == "led":
		return false # use equip_led(hand, id)
	equipped[slot] = id
	save()
	item_equipped.emit(slot, id)
	return true


func equip_led(hand: int, id: String) -> bool:
	var it := item(id)
	if it.is_empty() or it.category != "led" or not has(id):
		return false
	var slot := "led_left" if hand == 0 else "led_right"
	equipped[slot] = id
	save()
	item_equipped.emit(slot, id)
	return true


func led_color(hand: int) -> Color:
	var id: String = equipped["led_left" if hand == 0 else "led_right"]
	var it := item(id)
	if it.is_empty():
		return Color.RED if hand == 0 else Color.BLUE
	return it.color


func led_item(hand: int) -> Dictionary:
	return item(equipped["led_left" if hand == 0 else "led_right"])


func title_name() -> String:
	var it := item(equipped.get("title", "title_newcomer"))
	return it.get("name", "Newcomer")


func add_coins(amount: int) -> void:
	coins += maxi(0, amount)
	stats["coins_earned"] = int(stats.get("coins_earned", 0)) + maxi(0, amount)
	coins_changed.emit(coins)


func _unlock_achievement(id: String, new_unlocks: Array) -> void:
	if achievements.has(id):
		return
	achievements[id] = Time.get_datetime_string_from_system()
	for it in CATALOG:
		if it.get("achievement", "") == id and not unlocked.has(it.id):
			unlocked[it.id] = true
			new_unlocks.append(it.id)
			item_unlocked.emit(it.id)


## Records a finished play. Returns {coins_earned, new_best, new_unlocks, achievements}.
func record_result(chart_key: String, chart_version: String, bundled: bool, r: Dictionary) -> Dictionary:
	var earned := int(round(100.0 * float(r.accuracy))) + (50 if bool(r.cleared) else 0) + mini(100, int(r.max_combo) / 5)
	match str(r.rank):
		"SS": earned += 150
		"S": earned += 100
		"A": earned += 50
	if bool(r.full_combo):
		earned += 75
	add_coins(earned)
	stats["plays"] = int(stats.get("plays", 0)) + 1
	stats["greats"] = int(stats.get("greats", 0)) + int(r.greats)
	stats["oks"] = int(stats.get("oks", 0)) + int(r.oks)
	stats["misses"] = int(stats.get("misses", 0)) + int(r.misses)
	stats["balloons"] = int(stats.get("balloons", 0)) + int(r.balloon_pops)
	stats["best_combo"] = maxi(int(stats.get("best_combo", 0)), int(r.max_combo))
	var prev: Dictionary = scores.get(chart_key, {})
	var new_best := prev.is_empty() or int(r.score) > int(prev.get("score", 0))
	var entry := {
		"score": maxi(int(r.score), int(prev.get("score", 0))),
		"accuracy": maxf(float(r.accuracy), float(prev.get("accuracy", 0.0))),
		"rank": str(r.rank) if new_best else str(prev.get("rank", r.rank)),
		"max_combo": maxi(int(r.max_combo), int(prev.get("max_combo", 0))),
		"plays": int(prev.get("plays", 0)) + 1,
		"cleared": bool(prev.get("cleared", false)) or bool(r.cleared),
		"full_combo": bool(prev.get("full_combo", false)) or bool(r.full_combo),
		"bundled": bundled,
	}
	scores[chart_key] = entry
	var new_unlocks := []
	var got := []
	if bool(r.full_combo) and int(r.greats) + int(r.oks) > 0:
		_unlock_achievement("fc_any", new_unlocks); got.append("fc_any")
		if chart_version.to_lower().contains("hard") or chart_version.to_lower().contains("oni"):
			_unlock_achievement("fc_hard", new_unlocks); got.append("fc_hard")
	if str(r.rank) == "SS":
		_unlock_achievement("ss_any", new_unlocks); got.append("ss_any")
	if int(r.max_combo) >= 100:
		_unlock_achievement("combo_100", new_unlocks); got.append("combo_100")
	if int(stats["balloons"]) >= 10:
		_unlock_achievement("balloon_10", new_unlocks); got.append("balloon_10")
	if int(stats["plays"]) >= 25:
		_unlock_achievement("plays_25", new_unlocks); got.append("plays_25")
	if bundled:
		var cleared_bundled := 0
		var seen := {}
		for k in scores:
			if bool(scores[k].get("bundled", false)) and bool(scores[k].get("cleared", false)):
				seen[k.get_slice("|", 0)] = true
		cleared_bundled = seen.size()
		if cleared_bundled >= 3:
			_unlock_achievement("clear_all", new_unlocks); got.append("clear_all")
	save()
	return {"coins_earned": earned, "new_best": new_best, "new_unlocks": new_unlocks, "achievements": got}


func best_for(chart_key: String) -> Dictionary:
	return scores.get(chart_key, {})
