What happened: A skipped instant replay left a severed head 3.4 m off: bodies placed with `global_transform` from an input event were synced back to the physics server's older pose by the next step, before the transform flush reached the server
Rule: Place a body that must stay put with both `global_transform` and `PhysicsServer3D.body_set_state(TRANSFORM)`, and unfreeze it before placing it
