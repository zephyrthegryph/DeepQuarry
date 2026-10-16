# Native mapload-aware filth persistence

Four source init fingerprints use a typed native capability on_holder_init(A) and A.mapload. The earlier claim that native mapload context was absent was incorrect; scopes.dm supplies it directly.

track_value reads only persistence config, real turf/area eligibility and z-level; it does not read ATOM_INITIALIZED, native registry state, color, age, item actions or later constructor values. The hook is reached inside the same parent atom initialization. A fuel initializer rejecting an invalid location before its parent still never reaches the hook. Base filth tracking retains its position before blood/dirt child merge logic. Trash tracking moves before item tail work, which none of those persistence eligibility checks consume. Existing dematerialize forget hooks stay unchanged.

Native hooks precede params_apply: this proposal intentionally does not move dirt's age-sensitive transaction or blood's peer deletion. No generic mapload shadow or saved reference is added. Two real map-loader batches test both ignore-mapload settings, runtime tracking, disabled persistence, actual category membership and destruction cleanup; fixture config/state is restored through existing test scope methods.

No builds/generation/tests have run. Root must include code/modules/persistence/filth_capability.dm and dq_init_objects_persistent_filth_tests.dm. Source count estimate four; not an analyzer-confirmed result.
