// Result bits and constants that notice handlers, guards and accumulators still return or read. They came from the DCS
// signal defines by way of the om events (both gone); the callers own them now.

// ---- from signals_atom_attack.dm
#define COMPONENT_CANCEL_ATTACK_CHAIN (1<<0)

// ---- from signals_atom_x_act.dm
#define COMPONENT_IGNORE_EXPLOSION (1<<0)

// ---- from signals_mob_living.dm
#define COMPONENT_BLOCK_LIVING_RADIATION (1<<0)
#define COMPONENT_BLOCK_IRRADIATION (1<<0)

// ---- from signals_radiation.dm
#define CANCEL_IRRADIATION (1 << 0)
#define SKIP_MINIMUM_EXPOSURE_TIME_CHECK (1 << 1)

// ---- from signals_mob_main.dm
/// draw_hud: a hook drew the HUD; skip the default.
#define HUD_EVENT_HANDLED (1<<0)
/// draw_health_icon: a hook set the health icon; skip the default.
#define HEALTH_ICON_EVENT_HANDLED (1<<0)

// ---- from dcs/declarations.dm (conflict_checking behaviour ids)
#define CONFLICT_ELEMENT_CRUSHER "crusher"
#define CONFLICT_ELEMENT_KA "kinetic_accelerator"
