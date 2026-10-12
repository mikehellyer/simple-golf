class_name CoursePicker
extends RefCounted
## The course list shown in the menus: a new random course, today's course,
## the bundled real courses, then the player's saved courses.


static func fill(o: OptionButton, select_label := "") -> void:
	var previous := select_label
	if previous == "" and o.item_count > 0 and o.selected >= 0:
		previous = o.get_item_text(o.selected)
	o.clear()
	_add(o, "Random course", "random")
	_add(o, Course.daily().name, "daily")
	for id in CourseMaps.ids():
		_add(o, "%s (real course)" % CourseMaps.name_of(id), "map:" + id)
	for n in Course.list_saved():
		_add(o, n, "saved:" + n)
	o.select(0)
	for i in o.item_count:
		if o.get_item_text(i) == previous or o.get_item_text(i) == "%s (real course)" % previous:
			o.select(i)


## The course for the selected entry; a random one gets a fresh seed.
static func chosen(o: OptionButton) -> Course:
	var meta := str(o.get_item_metadata(o.selected)) if o.selected >= 0 else "random"
	if meta == "daily":
		return Course.daily()
	if meta.begins_with("map:"):
		return Course.real(meta.substr(4), randi())
	if meta.begins_with("saved:"):
		return Course.load_saved(meta.substr(6))
	return Course.new("Random course", randi())


static func _add(o: OptionButton, label: String, meta: String) -> void:
	o.add_item(label)
	o.set_item_metadata(o.item_count - 1, meta)
