// Abilities (doc/rewrite/rules.md §5). Code: code/datums/abilities/.
//
// An ability is an interaction the actor performs on themselves: a
// /datum/interaction/ability with target == actor. It is declared, listed and
// bound to keys exactly like any other interaction (doc/rewrite/interactions.md
// §5-8); the only new machinery is the resource-cost requirement clause below
// and the per-ability keybinding row generated in keybinding_defaults.dm.

/// The shared singleton of an ability type, e.g. ABILITY(/datum/interaction/ability/shadekin_phase_shift).
#define ABILITY(path) (GLOB.interactions_by_type[path])
/// The shared singleton with this id, or null.
#define ABILITY_BY_ID(id) (interaction_by_id(id))

// Ability categories. Distinct from INTERACTION_CAT_* (those are category keys
// for interactions on a hovered/faced target; abilities act on self and are
// grouped for the ability list and the Menu instead).
#define ABILITY_CAT_MOVEMENT "movement"
#define ABILITY_CAT_OFFENSE "offense"
#define ABILITY_CAT_DEFENSE "defense"
#define ABILITY_CAT_UTILITY "utility"
#define ABILITY_CATEGORIES list(ABILITY_CAT_MOVEMENT, ABILITY_CAT_OFFENSE, ABILITY_CAT_DEFENSE, ABILITY_CAT_UTILITY)

/// Offered only as a self-ability: never a click/tool interaction, never shown to observers.
#define INTERACTION_TAG_ABILITY "ability"

/// The keybinding id for an ability's dedicated key (keybinding_defaults.dm).
#define ABILITY_KEYBIND(id) "ability_[id]"

// ---- Resource cost requirement (rules.md worked example) ----
// `cost_proc` is a proc on the actor: proc(mob/living/actor, atom/target, obj/item/held).
// It returns TRUE when the actor can afford the ability (and should record the
// exact amount to spend, so pay_cost() spends precisely what was checked -
// never a value recomputed after time has passed), or a text reason why not.
#define REQ_RESOURCE(cost_proc) REQ_ON(PRED_ACTOR, cost_proc, "not enough energy for that")

/// A requirement that the actor is conscious (not unconscious/dead/etc).
#define REQ_CONSCIOUS REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_conscious, "you can't do that in your state")
/// A requirement that the actor is standing on a real turf.
#define REQ_ON_TURF REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_on_turf, "you can't use that here")

// ---- Ability ids referenced from outside their own file (grants, effects) ----
#define ABILITY_ID_SHADEKIN_PHASE_SHIFT "shadekin_phase_shift"
#define ABILITY_ID_SHADEKIN_DARK_RESPITE "shadekin_dark_respite"
#define ABILITY_ID_SHADEKIN_REGENERATE_OTHER "shadekin_regenerate_other"
#define ABILITY_ID_SHADEKIN_CREATE_SHADE "shadekin_create_shade"
#define ABILITY_ID_SHADEKIN_DARK_MAW "shadekin_dark_maw"
#define ABILITY_ID_SHADEKIN_DARK_TUNNELING "shadekin_dark_tunneling"

// ---- Dark tunneling's numbers (powers/dark_tunnel/dark_tunneling.dm) ----
#define DARK_TUNNEL_CHANNEL_TIME (60 SECONDS)
#define DARK_TUNNEL_COST 100

#define ABILITY_ID_ROBOT_TOGGLE_LIGHTS "robot_toggle_lights"
#define ABILITY_ID_ROBOT_PICK_NAME "robot_pick_name"
#define ABILITY_ID_ROBOT_CUSTOMIZE_APPEARANCE "robot_customize_appearance"
#define ABILITY_ID_ROBOT_TOGGLE_GLOWY_STOMACH "robot_toggle_glowy_stomach"
#define ABILITY_ID_ROBOT_SPARK_PLUG "robot_spark_plug"
#define ABILITY_ID_ROBOT_TOGGLE_GRABBABILITY "robot_toggle_grabbability"
#define ABILITY_ID_ROBOT_SENSOR_MODE "robot_sensor_mode"
#define ABILITY_ID_ROBOT_PURGE_NUTRITION "robot_purge_nutrition"
#define ABILITY_ID_ROBOT_TOGGLE_DECALS "robot_toggle_decals"
#define ABILITY_ID_ROBOT_RECOLOUR "robot_recolour"
#define ABILITY_ID_ROBOT_TOGGLE_VTEC "robot_toggle_vtec"
#define ABILITY_ID_ROBOT_PICK_SHELL "robot_pick_shell"
#define ABILITY_ID_ROBOT_SET_MAIL_TAG "robot_set_mail_tag"
#define ABILITY_ID_ROBOT_EJECT_CARGO "robot_eject_cargo"
#define ABILITY_ID_ROBOT_NOM "robot_nom"
#define ABILITY_ID_ROBOT_MOUNT "robot_mount"
#define ABILITY_ID_ROBOT_TOGGLE_MODULE_1 "robot_toggle_module_1"
#define ABILITY_ID_ROBOT_TOGGLE_MODULE_2 "robot_toggle_module_2"
#define ABILITY_ID_ROBOT_TOGGLE_MODULE_3 "robot_toggle_module_3"
