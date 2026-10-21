class_name NetRemoteBrain
extends FighterBrain
## On the host, stands in for the remote player's brain: Match asks it for side 1's input each tick like any CPU
## brain, and it hands back the next input from the client's jitter buffer. NetSession puts it in Match.brains[1].

var buffer: NetInputBuffer


func _init(p_buffer: NetInputBuffer) -> void:
	super(1, {})
	buffer = p_buffer


func think(_me: Dictionary, _foe: Dictionary, _delta: float) -> FighterInput:
	return FighterInput.from_array(buffer.pop().to_array())
