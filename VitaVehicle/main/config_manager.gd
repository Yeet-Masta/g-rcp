extends Node



signal config_loaded()



const SAVE_PATH := "user://settings/user_config_1.tres"

var data: UserConfig
var is_config_loaded := false



func load_config() -> void:
	if ResourceLoader.exists(SAVE_PATH, "UserConfig"):
		data = ResourceLoader.load(SAVE_PATH)
	else:
		data = UserConfig.new()
	
	is_config_loaded = true
	config_loaded.emit()


func save_config() -> void:
	var dir := DirAccess.open("user://")
	if !dir.dir_exists("settings"):
		dir.make_dir("settings")
	
	var result := ResourceSaver.save(data, SAVE_PATH)
	assert(result == OK, "Failed saving user config.")


func _ready() -> void:
	load_config()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_config()
