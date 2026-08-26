extends Node3D

var emitters: Array[CPUParticles3D] = []

func _ready():
	for i in range(8):
		var marker = get_node("exhaust_marker_%d" % i)
		emitters.append(marker.get_node("CPUParticles3D"))

func _process(_delta):
	if Input.is_action_just_pressed("ui_accept"):  # spacebar, temp test trigger
		fire_backfire()

func fire_backfire():
	for i in range(emitters.size()):
		var delay = i * 0.03
		get_tree().create_timer(delay).timeout.connect(func():
			emitters[i].restart()
			emitters[i].emitting = true
		)
