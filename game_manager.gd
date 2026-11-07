extends Node

# गेम का मिस्ट्री और क्लू सिस्टम
signal clue_found(clue_name: String)

var current_clue_index: int = 0
var clues: Array = [
    "Anjaan gufa ka pehla raaz: Purana pathar khol raha hai rasta.",
    "Ghane jungle ka raaz: Ped ke peechhe chhipa hai sanket.",
    "Purane khandhar ka raaz: Roshni padte hi khula gupt dwar."
]

func _ready():
    print("Searchlight 3D Mystery System Initialized.")

func check_puzzle(clue_id: int):
    if clue_id == current_clue_index:
        emit_signal("clue_found", clues[current_clue_index])
        current_clue_index += 1
        print("Agla raaz khul gaya!")
    else:
        print("Sahi jagah torch ki roshni daalo!")
