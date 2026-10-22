What happened: A shader-hidden crowd twin (`VERTEX *= 0`) still cost its vertices, and Godot's primitive counter ignores MultiMesh instances, so the crowd looked cheap
Rule: Cut instances with `visible_instance_count`; count MultiMesh triangles yourself and time script cost separately
