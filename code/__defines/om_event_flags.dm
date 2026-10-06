// Result bits and helper constants for OM events (moved from the DCS signal
// defines when the signals became /datum/om/event types). A handler returns
// these; om_emit() ORs them into event.result and returns it.

// ---- from signals_action.dm
#define COMPONENT_ACTION_BLOCK_TRIGGER (1<<0)

// ---- from signals_ai_controller.dm
#define AI_CONTROLLER_BEHAVIOR_QUEUED(type) "ai_controller_behavior_queued_[type]"

// ---- from signals_atom_attack.dm
#define COMPONENT_NO_AFTERATTACK (1<<0)
#define COMPONENT_NO_TAKE_DAMAGE (1<<0)
#define COMPONENT_CANCEL_ATTACK_CHAIN (1<<0)
#define COMPONENT_SKIP_ATTACK (1<<1)
#define ATTACKER_STAMINA_ATTACK (1<<0)
#define ATTACKER_SHOVING (1<<1)
#define ATTACKER_DAMAGING_ATTACK (1<<2)

// ---- from signals_atom_main.dm
#define EXAMINE_POSITION_ARTICLE 1
#define EXAMINE_POSITION_BEFORE 2
#define EXAMINE_POSITION_NAME 3

// ---- from signals_atom_movable.dm
#define COMPONENT_BLOCK_CROSS (1<<0)
#define COMPONENT_INTERCEPT_BUMPED (1<<0)
#define MOVABLE_SAY_QUOTE_MESSAGE 1
#define MOVABLE_SAY_QUOTE_MESSAGE_SPANS 2
#define MOVABLE_SAY_QUOTE_MESSAGE_MODS 3

// ---- from signals_atom_movement.dm
#define COMPONENT_MOVE_TURF MOVE_TURF
#define COMPONENT_MOVE_AREA MOVE_AREA
#define COMPONENT_MOVE_CONTENTS MOVE_CONTENTS

// ---- from signals_atom_x_act.dm
#define COMPONENT_IGNORE_EXPLOSION (1<<0)

// ---- from signals_food.dm
#define DESTROY_FOOD (1<<0)

// ---- from signals_janitor.dm
#define COMPONENT_CLEANED (1<<0)
#define COMPONENT_CLEANED_GAIN_XP (1<<1)

// ---- from signals_medical.dm
#define COMPONENT_DEFIB_STOP (1<<0)
#define COMPONENT_CANCEL_SURGERY (1<<0)
#define COMPONENT_FORCE_SURGERY (1<<1)

// ---- from signals_mob_carbon.dm
#define VISIBLE_NAME_FACE 1
#define VISIBLE_NAME_ID 2
#define VISIBLE_NAME_FORCED 3

// ---- from signals_mob_living.dm
#define COMPONENT_BLOCK_LIVING_RADIATION (1<<0)
#define COMPONENT_BLOCK_IRRADIATION (1<<0)
#define COMPONENT_LIVING_BLOCK_TURF_COLLISION (1<<0)

// ---- from signals_mob_main.dm
#define POST_BASIC_MOB_UPDATE_VARSPEED "post_basic_mob_update_varspeed"

// ---- from signals_mob_silicon.dm
#define COMPONENT_BLOCK_EMP (1<<0) //If this is set, the EMP will not go through. Used by other EMP acts as well.

// ---- from signals_object.dm
#define COMPONENT_STOP_EXPORT_REPORT (1<<0)
#define COMPONENT_DELETE_NEW_IMPLANT (1<<1)
#define COMPONENT_DELETE_OLD_IMPLANT (1<<2)

// ---- from signals_radiation.dm
#define CANCEL_IRRADIATION (1 << 0)
#define SKIP_MINIMUM_EXPOSURE_TIME_CHECK (1 << 1)

// ---- from signals_screentips.dm
#define CONTEXTUAL_SCREENTIP_SET (1 << 0)
#define SCREENTIP_NAME_SET (1 << 0)

// ---- from signals_spatial_grid.dm
#define SPATIAL_GRID_CELL_ENTERED(contents_type) "spatial_grid_cell_entered_[contents_type]"
#define SPATIAL_GRID_CELL_EXITED(contents_type) "spatial_grid_cell_exited_[contents_type]"

// ---- from signals_spell.dm
#define SPELL_CANCEL_CAST (1 << 0)
#define SPELL_NO_FEEDBACK (1 << 1)
#define SPELL_NO_IMMEDIATE_COOLDOWN (1 << 2)

// ---- from signals_tools.dm
#define COMPONENT_TOOL_DO_NOT_ALLOW_FORCE_OPEN (1<<0)
#define COMPONENT_TOOL_ALLOW_FORCE_OPEN (1<<1)

// ---- from signals_turf.dm
#define FOOTSTEP_OVERRIDEN (1<<0)

// ---- from signals_vore.dm
#define CANCEL_STUMBLED_INTO	(1<<0)

// ---- from signals_mob_main.dm
/// draw_hud: a hook drew the HUD; skip the default.
#define HUD_EVENT_HANDLED (1<<0)
/// draw_health_icon: a hook set the health icon; skip the default.
#define HEALTH_ICON_EVENT_HANDLED (1<<0)

// ---- from dcs/declarations.dm (conflict_checking behaviour ids)

#define CONFLICT_ELEMENT_CRUSHER "crusher"


#define CONFLICT_ELEMENT_KA "kinetic_accelerator"

