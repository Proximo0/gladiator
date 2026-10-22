class_name FeelOptions
extends RefCounted
## Player switches for the combat-feel effects. The options screen writes these (and the settings file saves them);
## the effects only read. Presentation only: nothing here touches fight state.

## Gamepad rumble and phone vibration.
static var rumble_enabled: bool = true
## Aim aid: tip marker, trail and hand reticle on the player's own weapon, plus the weapon-lost pointer. Local only.
static var aim_aid: bool = true
## Reduced motion: no camera kick, shake or zoom punch (the hit flash and sparks stay: they are not motion).
static var reduced_motion: bool = false


## Multiplier for the camera effects: the Tuning master scale, zero under reduced motion.
static func motion_scale(tun: Tuning) -> float:
	if reduced_motion:
		return 0.0
	return maxf(tun.feel_shake_scale, 0.0)


static func rumble_scale(tun: Tuning) -> float:
	if not rumble_enabled:
		return 0.0
	return clampf(tun.feel_rumble_scale, 0.0, 1.0)
