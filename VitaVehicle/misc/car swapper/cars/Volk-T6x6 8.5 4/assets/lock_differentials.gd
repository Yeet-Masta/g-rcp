extends Control

var locked = false

func _pressed():
	$toggle.release_focus()
	if locked:
		locked = false
		$toggle.text = "unlocked"
		
		get_parent().Preload = 0.0
		
	else:
		locked = true
		$toggle.text = "locked"
	
		get_parent().Preload = 1.0
