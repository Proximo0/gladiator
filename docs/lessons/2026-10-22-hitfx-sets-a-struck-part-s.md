What happened: HitFx sets a struck part's `material_overlay` for its flash and then clears it to null, so any other overlay on fighter meshes is wiped on the next hit
Rule: Draw extra per-mesh layers (wound marks, weapon blood) as shell MeshInstance3Ds outside Look/ArmorSlot that follow their source's visibility; never share `material_overlay`
