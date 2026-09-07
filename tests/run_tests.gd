extends SceneTree
## Headless test runner:  godot --headless --path . -s tests/run_tests.gd
## Each test script under tests/ named test_*.gd must extend RefCounted and define methods named test_*.

static var failures := 0
var passed := 0


func _init() -> void:
	var dir := DirAccess.open("res://tests")
	var files: Array[String] = []
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.begins_with("test_") and f.ends_with(".gd"):
				files.append(f)
			f = dir.get_next()
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var inst = script.new()
		for m in inst.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			inst.set("_current_test", name)
			var before := failures
			inst.call(name)
			if failures == before:
				passed += 1
				print("  ok   %s.%s" % [f, name])
			else:
				print("  FAIL %s.%s" % [f, name])
	print("tests: %d passed, %d failures" % [passed, failures])
	quit(1 if failures > 0 else 0)


static func check(cond: bool, msg: String) -> void:
	if not cond:
		printerr("    check failed: " + msg)
		failures += 1
