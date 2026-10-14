/obj/k1/Initialize(mapload) // ALLOW(init/INSTANCE_STATE): the fixture keeps this override with a code
// ALLOW(init/CTOR_ARGS): the fixture keeps the next override from the comment line above
/obj/k2/Initialize(mapload, extra)
/obj/k3/Initialize(mapload) // ALLOW(init/FRAMEWORK): a base of the init chain
/obj/k4/Initialize(mapload) // ALLOW(init/NOT_A_CODE): an unknown code keeps nothing
/obj/k5/Initialize(mapload) // ALLOW(init/INSTANCE_STATE)
/obj/k6/LateInitialize() // ALLOW(init/INSTANCE_STATE): LateInitialize is banned, a code does not keep it
