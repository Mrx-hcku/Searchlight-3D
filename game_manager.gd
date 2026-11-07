extends Node

var ambient_player: AudioStreamPlayer
var mysterious_sounds = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_audio_system()

func setup_audio_system() -> void:
	ambient_player = AudioStreamPlayer.new()
	add_child(ambient_player)
	print("Atmospheric Audio Manager Initialized for Searchlight 3D.")
	play_creepy_ambience()

func play_creepy_ambience() -> void:
	var timer = Timer.new()
	timer.wait_time = 12.0
	timer.autostart = true
	timer.timeout.connect(func():
		print("Playing procedural low-frequency cave drone / forest whisper...")
	)
	add_child(timer)
