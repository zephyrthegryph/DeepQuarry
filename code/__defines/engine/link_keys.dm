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
/// The belly a mob is previewing the vore FX of: LK_VORE_PREVIEW on the mob, LK_VORE_PREVIEWED_BY on the belly (many). Read vore_previewing_of(M).
#define LK_VORE_PREVIEW "vore_preview"
#define LK_VORE_PREVIEWED_BY "vore_previewed_by"
/// The object an admin mob possesses: LK_POSSESSING on the mob, LK_POSSESSED_BY on the object (many). Read possessed_obj_of(M).
#define LK_POSSESSING "possessing"
#define LK_POSSESSED_BY "possessed_by"
/// An integrated tool and the augment organ that hosts it: LK_AUGMENT_HOST on the item, LK_AUGMENT_TOOLS on the organ (many). Read item_my_augment(I).
#define LK_AUGMENT_HOST "augment_host"
#define LK_AUGMENT_TOOLS "augment_tools"
/// The gun a mob fires while its trigger is held: LK_AUTOFIRE_GUN on the mob, LK_AUTOFIRE_USERS on the gun (many). Read autofire_gun().
#define LK_AUTOFIRE_GUN "autofire_gun"
#define LK_AUTOFIRE_USERS "autofire_users"
/// A VR avatar and the body its player came from: LK_VR_HOLDER on the avatar, LK_VR_LINK on the body (the avatar it entered or left). Read vr_holder() / vr_link().
#define LK_VR_HOLDER "vr_holder"
#define LK_VR_LINK "vr_link"
/// A shapeshifter and the form it took: LK_TF_FORM on the original, LK_TF_ORIGIN on the form (many). Read tf_form_of(L).
#define LK_TF_FORM "tf_form"
#define LK_TF_ORIGIN "tf_origin"
/// The mind a shapeshifted form carries back: LK_TF_FORM_MIND on the mob, LK_TF_FORM_MIND_OF on the mind (many). Read tf_form_mind_of(L).
#define LK_TF_FORM_MIND "tf_form_mind"
#define LK_TF_FORM_MIND_OF "tf_form_mind_of"
/// The nest or spawner a mob came from: LK_NEST on the mob, LK_NEST_SPAWNS on the nest (any atom, many). Read nest_of(L).
#define LK_NEST "nest"
#define LK_NEST_SPAWNS "nest_spawns"

/// The rings a lleill has placed: LK_GLAMOUR_RINGS on the human (many), LK_GLAMOUR_OWNER on the ring. A ring goes with its owner. Read glamour_rings().
#define LK_GLAMOUR_RINGS "glamour_rings"
#define LK_GLAMOUR_OWNER "glamour_owner"
/// The medication side effects a human suffers: LK_SIDE_EFFECTS on the human (many), LK_SIDE_EFFECT_OF on the effect. An effect goes with its human.
#define LK_SIDE_EFFECTS "side_effects"
#define LK_SIDE_EFFECT_OF "side_effect_of"
/// The genetic side effects a human suffers: LK_GENETIC_EFFECTS on the human (many), LK_GENETIC_HOST on the effect. An effect goes with its human. Read genetic_side_effects().
#define LK_GENETIC_EFFECTS "genetic_effects"
#define LK_GENETIC_HOST "genetic_host"
/// A rig and the human wearing it: LK_WEARING_RIG on the human, LK_RIG_WEARER on the rig. Read wearing_rig() / wearer().
#define LK_WEARING_RIG "wearing_rig"
#define LK_RIG_WEARER "rig_wearer"
/// The camera-overview map screens a mob is shown: LK_MAPOBJS on the mob (many), LK_MAPOBJ_OF on the screen. A screen goes with its mob. Read mapobjs().
#define LK_MAPOBJS "mapobjs"
#define LK_MAPOBJ_OF "mapobj_of"
/// The cozy sleep music a carbon plays for itself: LK_COZY_LOOP on the carbon, LK_COZY_LOOP_OF on the loop. The loop goes with its carbon. Read cozy_loop().
#define LK_COZY_LOOP "cozy_loop"
#define LK_COZY_LOOP_OF "cozy_loop_of"

/// The pseudo segments of the turf and area hops (code/engine/refs/hops.dm): not vars. A reactive read of `get_turf(src).x` crosses HOP_TURF, of
/// `get_area(src).x` crosses HOP_AREA; hop_step() resolves them and the movement choke point publishes them (hop_moved()).
#define HOP_TURF "turf"
#define HOP_AREA "area"
