class_name RematchHandshake
extends RefCounted
## After an online fight, a rematch needs both players: either side asks, the other accepts by asking too. Tracks
## who asked, the answer window, and the words for the result panel. The host starts the fight once AGREED; the
## notes travel as NetSession notes {t: "rematch"} / {t: "decline"}. Pure: no clock, no nodes.

enum State { NONE, ASKED, INVITED, AGREED, DECLINED, EXPIRED, GONE }

const NOTE_ASK: String = "rematch"
const NOTE_DECLINE: String = "decline"
const ANSWER_S: float = 30.0  ## an open question (ours or theirs) expires after this long

var state: State = State.NONE
var open_s: float = 0.0  ## how long the current question has been open
var count: int = 0  ## rematches agreed with this opponent so far (the n of OnlineService.rematch_info)


func reset() -> void:
	state = State.NONE
	open_s = 0.0
	count = 0


## A new fight began (the rematch, or the first one): ready for the next question; `count` stays.
func fight_started() -> void:
	state = State.NONE
	open_s = 0.0


## This player pressed Rematch. Returns true when a note should be sent (always, so the other side learns it).
func ask() -> bool:
	match state:
		State.NONE, State.EXPIRED:
			state = State.ASKED
			open_s = 0.0
			return true
		State.INVITED:
			_agree()
			return true
	return false


## This player said no (or went back to the queue) while a question was open. Returns true when a note should go.
func decline() -> bool:
	if state == State.ASKED or state == State.INVITED:
		state = State.DECLINED
		return true
	return false


## A note from the other player.
func on_note(kind: String) -> void:
	match kind:
		NOTE_ASK:
			if state == State.ASKED:
				_agree()
			elif state == State.NONE or state == State.EXPIRED:
				state = State.INVITED
				open_s = 0.0
		NOTE_DECLINE:
			if state != State.AGREED:
				state = State.DECLINED


## The connection is gone: no rematch.
func on_gone() -> void:
	if state != State.AGREED:
		state = State.GONE


func tick(delta: float) -> void:
	if state == State.ASKED or state == State.INVITED:
		open_s += delta
		if open_s >= ANSWER_S:
			state = State.EXPIRED


func _agree() -> void:
	state = State.AGREED
	count += 1


## Can the Rematch button do anything now?
func can_ask() -> bool:
	return state == State.NONE or state == State.INVITED or state == State.EXPIRED


## The label of the Rematch button.
func button_text(opponent: String) -> String:
	match state:
		State.INVITED:
			return "Accept rematch"
		State.ASKED:
			return "Rematch asked..."
	return "Rematch %s" % opponent if opponent != "" else "Rematch"


## The panel line for the state, "" when there is nothing to say.
func text(opponent: String) -> String:
	var who: String = opponent if opponent != "" else "Your opponent"
	match state:
		State.ASKED:
			return "Waiting for %s to accept..." % who
		State.INVITED:
			return "%s wants a rematch!" % who
		State.AGREED:
			return "Rematch on! Back to the sand..."
		State.DECLINED:
			return "%s doesn't want a rematch" % who
		State.EXPIRED:
			return "No answer from %s" % who
		State.GONE:
			return "%s left. No rematch." % who
	return ""
