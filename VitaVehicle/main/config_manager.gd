extends Node



signal config_loaded()



var save_path := "user://settings/user_config_1.tres"

var data: UserConfig



func load_config() -> void:
	if ResourceLoader.exists(save_path, "UserConfig"):
		data = ResourceLoader.load(save_path)
	else:
		data = UserConfig.new()
	
	config_loaded.emit()


func save_config() -> void:
	var dir := DirAccess.open("user://")
	if !dir.dir_exists("settings"):
		dir.make_dir("settings")
	
	var result := ResourceSaver.save(data, save_path)
	assert(result == OK, "Failed saving user config.")


func _ready() -> void:
	load_config()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_config()
