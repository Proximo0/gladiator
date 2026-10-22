class_name RealClock
extends RefCounted
## Real (unscaled) seconds for a `_process` delta. Godot scales a frame's delta by the Engine.time_scale in force when
## the frame began, but the end-of-match slow motion changes the scale during that frame's physics, so dividing by the
## current scale (FightCamera.real_delta) makes the first slow frame five times too long and the first fast frame
## five times too short. This divides by the scale seen at the end of the previous frame. Pure. Unit-tested in
## test_real_clock.gd.

var prev_scale: float = 1.0


## Real seconds for `delta`; `scale_now` is Engine.time_scale now (it becomes the next frame's divisor).
func step(delta: float, scale_now: float) -> float:
	var r: float = FightCamera.real_delta(delta, prev_scale)
	if is_finite(scale_now) and scale_now > 0.0:
		prev_scale = scale_now
	return r
