// Forms: one character mob, several bodies' worth of appearance and capability.
// See doc/mob_life_architecture.md §6 and code/modules/mob/living/carbon/human/species/station/protean/forms.dm.

/// From /datum/component/forms/proc/set_form(): (datum/form/old_form, datum/form/new_form)
#define COMSIG_FORM_CHANGED "form_changed"

/// The current form draws its own appearance; the human body layers are not applied.
#define TRAIT_FORM_HIDES_BODY "form_hides_body"
/// Trait source for everything the forms component grants.
#define FORM_TRAIT "form"

// Form flags. A power lists the forms it can be used from.
#define FORM_FLAG_HUMAN            (1<<0)
#define FORM_FLAG_PROTEAN_BLOB     (1<<1)
#define FORM_FLAG_PROMETHEAN_BLOB  (1<<2)
#define FORM_FLAG_ANY              (FORM_FLAG_HUMAN | FORM_FLAG_PROTEAN_BLOB | FORM_FLAG_PROMETHEAN_BLOB)

/// Steel (material units) a refactory spends per point of repair it funds.
#define NANOFORM_STEEL_PER_POINT 20

// core_dormancy revival steps, in order.
/// The control module is sealed; a screwdriver opens the maintenance panel.
#define DORMANCY_SEALED     1
/// Panel open; a reboot programmer recalibrates the swarm (TREAT_CALIBRATION).
#define DORMANCY_OPEN       2
/// Programmed; nanopaste rebuilds the substrate (TREAT_PLATING_REPAIR).
#define DORMANCY_PROGRAMMED 3
/// Substrate rebuilt; a defibrillator jump-starts reassembly (TREAT_DEFIBRILLATION).
#define DORMANCY_PASTED     4
/// Reassembly running; revival completes after DORMANCY_REBOOT_TIME.
#define DORMANCY_REBOOTING  5
#define DORMANCY_REBOOT_TIME (90 SECONDS)

// --- Protean rig and nanite afflictions ------------------------------------------------
/// Movement delay of a dormant (inert) control cluster: a leaden lump of nanites.
#define PROTEAN_RIG_INERT_SLOWDOWN 6
/// Cell units the rig recovers per upkeep tick from the protean's nutrition.
#define PROTEAN_RIG_RECHARGE_UNITS 100
/// Nutrition the swarm keeps back before it feeds its cluster's cell.
#define PROTEAN_RIG_RECHARGE_NUTRITION_FLOOR 100
/// Nutrition spent per cell unit stored in the cluster's cell.
#define PROTEAN_RIG_NUTRITION_PER_UNIT (1 / 200)

/// Physical or thermal injury points a hit must land before it shakes cohesion.
#define NANITE_COHESION_MIN_HIT 5
/// Cohesion loss severity per point of physical or thermal injury.
#define NANITE_COHESION_PER_POINT 0.5
/// Orchestrator damage severity per point of injury aimed at the orchestrator.
#define NANITE_ORCHESTRATOR_PER_POINT 2
/// Orchestrator damage severity per point of electrical injury anywhere.
#define NANITE_ORCHESTRATOR_PER_SHOCK 1
/// Refactory depletion severity per tick the swarm needs repair and has no steel.
#define NANITE_DEPLETION_PER_STARVED_TICK 2
/// Steel stock at which a depleted refactory recovers on its own.
#define NANITE_DEPLETION_RELIEF_STEEL 2000
/// Contamination severity per unit of foreign reagent in the swarm, per tick.
#define NANITE_CONTAMINATION_PER_UNIT 0.2
/// Most contamination severity foreign reagents add in one tick.
#define NANITE_CONTAMINATION_MAX_PER_TICK 5
/// Contamination severity per repair point's worth of foreign material stored.
#define NANITE_CONTAMINATION_PER_MATERIAL_POINT 0.5
/// Switching form again within this long of the last switch strains the swarm.
#define NANITE_FORM_SWITCH_GRACE (10 SECONDS)
/// Form strain severity per switch made inside the grace window.
#define NANITE_STRAIN_PER_FAST_SWITCH 15
/// Holding a shapeless form (blob or folded) longer than this strains the swarm.
#define NANITE_FORM_HOLD_LIMIT (20 MINUTES)
/// Form strain severity per tick past the hold limit.
#define NANITE_STRAIN_PER_HELD_TICK 0.5
