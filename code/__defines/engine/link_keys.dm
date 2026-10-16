// The keys of the sparse declared links (code/engine/declare/link_state.dm). A sparse end is not a var: it is written and read by its key through
// link_make() / link_get() / link_list(), and the typed accessors of its type (buckled_to(), pulling_target(), grab_target(), ...) wrap the reads.

/// A mob and the thing it is buckled to: LK_BUCKLED_TO on the mob (a /mob/living), LK_BUCKLED_MOBS on the seat (any /atom/movable, many).
#define LK_BUCKLED_TO "buckled_to"
#define LK_BUCKLED_MOBS "buckled_mobs"
/// A puller and what it pulls (any two /atom/movable: a mob, a wheelchair): LK_PULLING on the puller, LK_PULLED_BY on the pulled.
#define LK_PULLING "pulling"
#define LK_PULLED_BY "pulled_by"
/// A grab item and the mob it holds: LK_GRABBING on the grab, LK_GRABBED_BY on the mob (many: a mob can be held by several).
#define LK_GRABBING "grabbing"
#define LK_GRABBED_BY "grabbed_by"
/// An orbiter and what it orbits (the centre is any /atom, a turf included): LK_ORBITING on the orbiter (a movable), LK_ORBITERS on the centre (many). The
/// orbiter's saved transform rides on the link (link_data_set(orbiter, LK_ORBITING, "transform", ...)).
#define LK_ORBITING "orbiting"
#define LK_ORBITERS "orbiters"
/// An item attached to another (an assembly's valve, a chair's kit, a gun's attachment): LK_ITEM_MASTER on the attached item, LK_ITEM_ATTACHED on
/// its master (many). Read item_master(I).
#define LK_ITEM_MASTER "item_master"
#define LK_ITEM_ATTACHED "item_attached"
/// A mob's selected belly (where its vore goes): LK_VORE_SELECTED on the mob, LK_VORE_SELECTED_BY on the belly (many). Read vore_selected_of(M).
#define LK_VORE_SELECTED "vore_selected"
#define LK_VORE_SELECTED_BY "vore_selected_by"
/// A shapeshifter and the form it took: LK_TF_FORM on the original, LK_TF_ORIGIN on the form (many). Read tf_form_of(L).
#define LK_TF_FORM "tf_form"
#define LK_TF_ORIGIN "tf_origin"
/// The mind a shapeshifted form carries back: LK_TF_FORM_MIND on the mob, LK_TF_FORM_MIND_OF on the mind (many). Read tf_form_mind_of(L).
#define LK_TF_FORM_MIND "tf_form_mind"
#define LK_TF_FORM_MIND_OF "tf_form_mind_of"
/// The nest or spawner a mob came from: LK_NEST on the mob, LK_NEST_SPAWNS on the nest (any atom, many). Read nest_of(L).
#define LK_NEST "nest"
#define LK_NEST_SPAWNS "nest_spawns"

/// The pseudo segments of the turf and area hops (code/engine/refs/hops.dm): not vars. A reactive read of `get_turf(src).x` crosses HOP_TURF, of
/// `get_area(src).x` crosses HOP_AREA; hop_step() resolves them and the movement choke point publishes them (hop_moved()).
#define HOP_TURF "turf"
#define HOP_AREA "area"

#define LK_SWARM_MEMBERS "swarm_members"

#define LK_BURNING_STATE "burning_state"
#define LK_BURNING_HOLDER "burning_holder"

/// The live actor responsible for an atom's last recorded attack (non-owning).
#define LK_LAST_ATTACKER "last_attacker"
#define LK_LAST_ATTACKED "last_attacked"
