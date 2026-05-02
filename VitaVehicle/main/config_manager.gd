extends Node



signal config_loaded()



const SAVE_PATH := "user://settings/user_config_1.tres"
const SAVE_DIR := "user://settings"

var data: UserConfig
var is_config_loaded := false



func load_config() -> void:
	# Default first; we overwrite if a valid file is found. Guarantees `data`
	# is never null, even if the disk file is missing or corrupt.
	data = UserConfig.new()
	
	if ResourceLoader.exists(SAVE_PATH, "UserConfig"):
		var loaded := ResourceLoader.load(SAVE_PATH) as UserConfig
		if loaded != null:
			data = loaded
		else:
			push_warning("ConfigManager: %s exists but failed to load as UserConfig. Using defaults." % SAVE_PATH)
	
	# Sub-resources may have been omitted by older save files. Heal them.
	if data.graphics == null:
		data.graphics = GraphicsConfig.new()
	if data.controls == null:
		data.controls = ControlsConfig.new()
	
	is_config_loaded = true
	config_loaded.emit()


func save_config() -> void:
	# Make sure the settings directory exists. DirAccess.open("user://")
	# returns null in some sandbox configurations on first run, so we guard.
	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		# As a fallback, try to create the directory at the absolute path.
		var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		if err != OK and err != ERR_ALREADY_EXISTS:
			push_error("ConfigManager: could not access user:// (err %d). Settings not saved." % err)
			return
	else:
		if not user_dir.dir_exists("settings"):
			var mkerr := user_dir.make_dir("settings")
			if mkerr != OK and mkerr != ERR_ALREADY_EXISTS:
				push_error("ConfigManager: could not create settings dir (err %d)." % mkerr)
				return
	
	var result := ResourceSaver.save(data, SAVE_PATH)
	if result != OK:
		# Don't assert in release — log instead so the game keeps running.
		push_error("ConfigManager: failed saving user config to %s (err %d)." % [SAVE_PATH, result])


func _ready() -> void:
	load_config()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_config()
