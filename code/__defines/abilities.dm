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
