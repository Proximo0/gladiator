What happened: A `git add -A` after a headless Godot run committed 130 generated `.import` files and extracted glb textures; the lead had to drop them in a merge
Rule: Stage paths explicitly after any Godot run (`git add data/ tools/ ...`), never `-A` in a tree Godot has imported
