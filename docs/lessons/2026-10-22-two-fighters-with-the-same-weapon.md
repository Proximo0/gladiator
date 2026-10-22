What happened: Two fighters with the same weapon shared one cached glb `Mesh`; per-instance override materials on a shared mesh gave `Parameter "material" is null` at teardown
Rule: Duplicate an instanced glb's mesh before setting surface override materials
