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
