// Cyborg, drone and AI machine-body defines: part slots, the power ledger, the
// machine physiology, and the signals the silicon splits use.
// See doc/mob_life_architecture.md §5.

// --- Part slots ---------------------------------------------------------------------------
// /mob/living/silicon/robot/var/list/components is a flat list indexed by these.
// Each slot is a synthetic part and an affliction location.
#define ROBOT_SLOT_ACTUATOR   1
#define ROBOT_SLOT_RADIO      2
/// The cell mount and power bus. `power_fault` sits here.
#define ROBOT_SLOT_POWER      3
#define ROBOT_SLOT_DIAGNOSIS  4
#define ROBOT_SLOT_CAMERA     5
#define ROBOT_SLOT_COMMS      6
#define ROBOT_SLOT_ARMOUR     7
/// Coolant loop. `coolant_leak` and `thermal_runaway` sit here.
#define ROBOT_SLOT_COOLING    8
/// Processor housing. `processor_corruption` sits here; destroying it destroys the unit.
#define ROBOT_SLOT_CORE       9
#define ROBOT_SLOT_COUNT      9

// --- Component install state (/datum/robot_component/var/installed) -----------------------
#define ROBOT_PART_MISSING    0
#define ROBOT_PART_INSTALLED  1
#define ROBOT_PART_DESTROYED  -1

// --- Power ledger --------------------------------------------------------------------------
/// Every robot power figure is in joules per use (or per Life cycle for demand).
/// The multiplier makes cyborgs hungrier than their parts' nominal draw.
#define CYBORG_POWER_USAGE_MULTIPLIER 2
/// Cell charge units -> joules, for callers that think in cell charge.
#define ROBOT_CELL_JOULES(units) ((units) / CELLRATE)
/// Draw for each equipped module, per Life cycle.
#define ROBOT_MODULE_DRAW 50
/// Draw of the integrated light, per Life cycle.
#define ROBOT_LIGHT_DRAW 30
/// Nutrition burnt per cycle to top up a cell, and the joules it yields.
#define ROBOT_NUTRITION_BURN 2
#define ROBOT_NUTRITION_JOULES 10000

/// Movement delay added by a fully worn (function 0) actuator.
#define ROBOT_ACTUATOR_WEAR_SLOWDOWN 3

// --- Machine physiology -------------------------------------------------------------------
/// Heat debt at which the cooling loop falls into thermal runaway.
#define ROBOT_HEAT_DEBT_RUNAWAY 100
/// Heat debt shed per cycle by a healthy cooling loop.
#define ROBOT_HEAT_DEBT_SHED 5
/// Circulation below this lets heat debt build.
#define ROBOT_CIRCULATION_OK 0.75

// --- Sleeper belly (/datum/component/robot_belly/var/sleeper_state) -----------------------------
#define SLEEPER_STATE_EMPTY   0
/// Cleaning, processing or holding a patient who is dead: red light.
#define SLEEPER_STATE_BUSY    1
/// Holding a living patient: green light.
#define SLEEPER_STATE_PATIENT 2

// --- Countdowns ----------------------------------------------------------------------------
#define ROBOT_KILLSWITCH_DELAY (2 MINUTES)
#define ROBOT_WEAPON_LOCK_DELAY (4 MINUTES)

// --- AI power-loss state machine (/mob/living/silicon/ai/var/aiRestorePowerRoutine) --------
/// Powered; nothing running.
#define AI_POWER_NORMAL      0
/// Power lost; the restore routine is running.
#define AI_POWER_RESTORING   1
/// The routine gave up; waiting for power to come back on its own.
#define AI_POWER_FAILED      2
/// The routine forced an APC on.
#define AI_POWER_RESTORED    3
/// Step delay of the restore routine.
#define AI_POWER_STEP        (5 SECONDS)

// --- Signals -------------------------------------------------------------------------------
/// From /mob/living/silicon/robot/proc/after_equip(): (obj/item/equipped_or_null)
#define COMSIG_ROBOT_EQUIPMENT_CHANGED "robot_equipment_changed"
/// From the robot belly overlay provider: (belly_class, list/fullness_ref)
/// Handlers may adjust fullness_ref[1].
#define COMSIG_ROBOT_BELLY_FULLNESS "robot_belly_fullness"
/// From /mob/living/silicon/robot/update_icon() while conscious: ()
#define COMSIG_ROBOT_UPDATE_OVERLAYS "robot_update_overlays"
/// From /mob/living/silicon/proc/laws_changed(): ()
#define COMSIG_SILICON_LAWS_CHANGED "silicon_laws_changed"
/// From /mob/living/silicon/robot/proc/set_master_ai(): (mob/living/silicon/ai/old_ai, mob/living/silicon/ai/new_ai)
#define COMSIG_ROBOT_MASTER_AI_CHANGED "robot_master_ai_changed"
