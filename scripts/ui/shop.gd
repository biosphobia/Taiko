extends Control

var _coins: Label
var _content: VBoxContainer
var _category := "led"
var _first_item: Control


func _ready() -> void:
	UiTheme.fit_scene(self)
	Hardware.gameplay_mode = false
	Hardware.menu_navigation = true
	var t := UiTheme.theme()
	UiTheme.make_background(self)
	var title := UiTheme.make_title("Unlockables")
	title.position = Vector2(60, 30)
	add_child(title)
	_coins = UiTheme.make_label("", 30, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_RIGHT)
	_coins.position = Vector2(1100, 40)
	_coins.size = Vector2(440, 40)
	add_child(_coins)

	var tabs := HBoxContainer.new()
	tabs.position = Vector2(60, 110)
	tabs.add_theme_constant_override("separation", 10)
	add_child(tabs)
	for c in [["led", "Controller colors"], ["drum", "Drum skins"], ["notes", "Note skins"], ["theme", "Stage themes"], ["title", "Titles"], ["ach", "Achievements"]]:
		var b := UiTheme.make_button(c[1], 22)
		b.custom_minimum_size = Vector2(230, 48)
		b.pressed.connect(func():
			_category = c[0]
			_fill())
		tabs.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 180)
	scroll.size = Vector2(1480, 600)
	add_child(scroll)
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(1440, 0)
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)

	var b_back := UiTheme.make_button("Back")
	b_back.position = Vector2(60, 810)
	b_back.pressed.connect(func(): Game.goto("menu"))
	add_child(b_back)
	var hint := UiTheme.make_label("Earn coins by playing songs. Some items unlock through achievements.", 18, Color(1, 1, 1, 0.6))
	hint.position = Vector2(420, 826)
	add_child(hint)
	_fill()
	if _first_item:
		_first_item.grab_focus()


func _fill() -> void:
	_coins.text = "%d coins" % Profile.coins
	for c in _content.get_children():
		c.queue_free()
	_first_item = null
	if _category == "ach":
		for id in Profile.ACHIEVEMENTS:
			var done := Profile.achievements.has(id)
			var l := UiTheme.make_label("%s  %s" % ["[x]" if done else "[ ]", Profile.ACHIEVEMENTS[id]], 24, Color(1, 0.9, 0.5) if done else Color(1, 1, 1, 0.7))
			_content.add_child(l)
		var st := Profile.stats
		_content.add_child(UiTheme.make_label("Plays %d   GREAT %d   OK %d   MISS %d   Best combo %d   Coins earned %d" % [int(st.plays), int(st.greats), int(st.oks), int(st.misses), int(st.best_combo), int(st.coins_earned)], 20, Color(1, 1, 1, 0.6)))
		return
	for it in Profile.items_in(_category):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		if _category == "led":
			var sw := ColorRect.new()
			sw.color = it.color
			sw.custom_minimum_size = Vector2(40, 40)
			hb.add_child(sw)
		var owned := Profile.has(it.id)
		var name_l := UiTheme.make_label(it.name, 26)
		name_l.custom_minimum_size = Vector2(300, 0)
		hb.add_child(name_l)
		var desc := UiTheme.make_label(it.desc, 18, Color(1, 1, 1, 0.65))
		desc.custom_minimum_size = Vector2(480, 0)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hb.add_child(desc)
		var price_txt: String = "%d coins" % int(it.price)
		if owned:
			price_txt = "Owned"
		elif it.has("achievement"):
			price_txt = "Achievement: " + str(Profile.ACHIEVEMENTS.get(it.get("achievement", ""), ""))
		var price := UiTheme.make_label(price_txt, 20, Color(1, 0.9, 0.5))
		price.custom_minimum_size = Vector2(260, 0)
		hb.add_child(price)
		if not owned:
			var b := UiTheme.make_button("Buy", 20)
			b.custom_minimum_size = Vector2(120, 40)
			b.disabled = not Profile.can_buy(it.id)
			b.pressed.connect(func():
				if Profile.buy(it.id):
					Game.play_sfx("unlock")
				_fill())
			hb.add_child(b)
			if _first_item == null and not b.disabled:
				_first_item = b
		elif _category == "led":
			for hand in range(2):
				var slot := "led_left" if hand == 0 else "led_right"
				var b := UiTheme.make_button(("Left" if hand == 0 else "Right") + (" *" if Profile.equipped[slot] == it.id else ""), 20)
				b.custom_minimum_size = Vector2(120, 40)
				b.pressed.connect(func():
					Profile.equip_led(hand, it.id)
					Game.play_sfx("ui_select")
					_fill())
				hb.add_child(b)
				if _first_item == null:
					_first_item = b
		else:
			var equipped: bool = Profile.equipped.get(_category, "") == it.id
			var b := UiTheme.make_button("Equipped" if equipped else "Equip", 20)
			b.custom_minimum_size = Vector2(140, 40)
			b.disabled = equipped
			b.pressed.connect(func():
				Profile.equip(it.id)
				Game.play_sfx("ui_select")
				_fill())
			hb.add_child(b)
			if _first_item == null and not equipped:
				_first_item = b
		_content.add_child(hb)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") or event.is_action_pressed("ui_cancel"):
		Game.goto("menu")
