extends ColorRect
func _ready():
	$Timer.timeout.connect(_on_timer_time_out)
func _on_timer_time_out():
	self.queue_free()
func _process(delta):
	pass
