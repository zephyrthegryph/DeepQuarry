# B2 lighting and planet boundary handoff

The system_boundary baseline shrank146→120 (26 rows,67 private accesses converted;none remain for these owners). Owner APIs preserve append-versus-unique queue semantics, readiness, planet identity and space solar fallback. Added lighting_api.dm in the lighting owner folder and extended planet_api.dm. No tracked setters or ownership declarations changed.

New focused tests: dq_lighting_boundary and dq_planet_boundary; existing system solar/planet and solar assembly tests will run in the serialized lane gate. Verification pending. No push or merge.
