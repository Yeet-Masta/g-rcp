extends Node


func get_all_script_lines():
	var lines := 0
	var scripts := 0
	for path: String in Helper.get_dir_children("res://", true).files:
		if path.contains("res://addons/") and !path.contains("res://addons/vitavehicle_ui/"): continue
		if path.get_extension() != "gd": continue
		lines += Helper.get_lines_in_file(path)
		scripts += 1
		print(path + " has " + str(Helper.get_lines_in_file(path)) + " lines")
	print(scripts, " scripts")
	return lines


func _ready():
	print(get_all_script_lines(), " lines")
