What happened: Pad focus on the loadout and online screens skipped rows or dead-ended: Godot's neighbour search sees controls scrolled out of a ScrollContainer, so "down" from a row jumped to a footer button drawn over them
Rule: Route focus by hand on scrolling screens (`MenuNav.link_screen`) and prove it with `sim_menu_nav` (every control reachable, at landscape and portrait sizes)
