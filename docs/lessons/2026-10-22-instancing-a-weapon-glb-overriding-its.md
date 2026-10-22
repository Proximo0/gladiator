What happened: Instancing a weapon glb, overriding its materials on the nodes, then freeing the nodes printed `Parameter "material" is null`
Rule: For copies (racks, MultiMesh), read the scene's meshes and bake opaque materials into duplicated meshes; leave the instanced nodes untouched
