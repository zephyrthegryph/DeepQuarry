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

// base_vars wave 12: owned and borrowed datums a base type held in a var of its own.
/// The helper datum a mob's set_machine() made (the shim that releases the machine when the mob leaves it): LK_MACHINE_SHIM on the mob, LK_MACHINE_SHIM_OF on the shim. Gone with the mob. Read machine_shim().
#define LK_MACHINE_SHIM "machine_shim"
#define LK_MACHINE_SHIM_OF "machine_shim_of"
/// A mob's vore panel (the tgui window datum): LK_VORE_PANEL on the mob, LK_VORE_PANEL_OF on the panel. Gone with the mob. Read vore_panel().
#define LK_VORE_PANEL "vore_panel"
#define LK_VORE_PANEL_OF "vore_panel_of"
/// A mob's belly overlay window datum: LK_BELLY_OVERLAY on the mob, LK_BELLY_OVERLAY_OF on the window. Gone with the mob. Read belly_overlay_window().
#define LK_BELLY_OVERLAY "belly_overlay"
#define LK_BELLY_OVERLAY_OF "belly_overlay_of"
/// The slide a living mob is on across a slippery floor: LK_TURFSLIP on the mob, LK_TURFSLIP_OF on the slide. Gone with the mob. Read turfslip().
#define LK_TURFSLIP "turfslip"
#define LK_TURFSLIP_OF "turfslip_of"
/// A living mob's character setup HUD button datum: LK_SETUP_BUTTON on the mob, LK_SETUP_BUTTON_OF on the button. Gone with the mob. Read character_setup_button().
#define LK_SETUP_BUTTON "setup_button"
#define LK_SETUP_BUTTON_OF "setup_button_of"
/// A living mob's vore panel HUD button datum: LK_VORE_BUTTON on the mob, LK_VORE_BUTTON_OF on the button. Gone with the mob. Read vore_panel_button().
#define LK_VORE_BUTTON "vore_button"
#define LK_VORE_BUTTON_OF "vore_button_of"
/// A living mob's inventory panel window datum: LK_INVENTORY_PANEL on the mob, LK_INVENTORY_PANEL_OF on the panel. Gone with the mob. Read inventory_panel().
#define LK_INVENTORY_PANEL "inventory_panel"
#define LK_INVENTORY_PANEL_OF "inventory_panel_of"
/// The heat watch that puts out a burning object when it cools: LK_BURN_COOL_WATCH on the object, LK_BURN_COOL_WATCH_OF on the watch. Gone with the object.
#define LK_BURN_COOL_WATCH "burn_cool_watch"
#define LK_BURN_COOL_WATCH_OF "burn_cool_watch_of"
/// The disposal network connection of an object: LK_DISPOSAL_CONNECTION on the object, LK_DISPOSAL_CONNECTION_OF on the connection. Gone with the object. Read disposal_connection().
#define LK_DISPOSAL_CONNECTION "disposal_connection"
#define LK_DISPOSAL_CONNECTION_OF "disposal_connection_of"
/// The rules-engine node of an atom (its temperature as a rules value): LK_RX_NODE on the atom, LK_RX_NODE_OF on the node. Gone with the atom. Read rx_node_of().
#define LK_RX_NODE "rx_node"
#define LK_RX_NODE_OF "rx_node_of"
/// A mob's faction reputation ledger (its own, or the stable personal one of its account): LK_FACTION_LEDGER on the mob, LK_FACTION_LEDGER_OF on the ledger (many). Read faction_reputation().
#define LK_FACTION_LEDGER "faction_ledger"
#define LK_FACTION_LEDGER_OF "faction_ledger_of"
/// The unarmed attack a human uses by default: LK_DEFAULT_ATTACK on the human, LK_DEFAULT_ATTACK_OF on the attack (many). Read default_attack().
#define LK_DEFAULT_ATTACK "default_attack"
#define LK_DEFAULT_ATTACK_OF "default_attack_of"

// base_vars wave 13: owned datums an object held in a var of its own.
/// The speech state of a talking xenoarch find: LK_TALKING_ATOM on the object, LK_TALKING_ATOM_OF on the state. Gone with the object. Read talking_atom().
#define LK_TALKING_ATOM "talking_atom"
#define LK_TALKING_ATOM_OF "talking_atom_of"
/// The datum that swaps an object's icon state when a mob nears it: LK_REACTIVE_ICON on the object, LK_REACTIVE_ICON_OF on the datum. Gone with the object. Read reactive_icon().
#define LK_REACTIVE_ICON "reactive_icon"
#define LK_REACTIVE_ICON_OF "reactive_icon_of"

/// The pseudo segments of the turf and area hops (code/engine/refs/hops.dm): not vars. A reactive read of `get_turf(src).x` crosses HOP_TURF, of
/// `get_area(src).x` crosses HOP_AREA; hop_step() resolves them and the movement choke point publishes them (hop_moved()).
#define HOP_TURF "turf"
#define HOP_AREA "area"
