extends "res://tests/sim/sim_net_loopback.gd"
## The loopback sim with both matches presented (arena, sand, blood, sound, HUD, camera, the client's cursor) and
## a 5 s limit, over a clean localhost link (no fake lag or loss, so the latency line is the floor): the client's puppet path with everything hooked to it. Extra checks: the client's kinematic bodies
## report the speed they are moved at (sand and sound read it) and the predicted cursor is drawn.


func run() -> Array:
	present = true
	prefix = "net_presented"
	time_limit_s = 5.0
	port = PORT + 1
	lag_ticks = 0
	jitter_ticks = 0
	loss = 0.0
	var rows: Array = await super()
	rows.append(row(prefix + "_kinematic_speed", client_speed_max > 0.8, "client-side pelvis speed while walking up to %.2f m/s" % client_speed_max))
	rows.append(row(prefix + "_cursor", cursor_seen, "predicted hand cursor drawn on the client"))
	return rows
