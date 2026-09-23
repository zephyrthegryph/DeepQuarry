/// From /datum/surgery/New(): (datum/surgery/surgery, surgery_location (body zone), obj/item/bodypart/targeted_limb)
#define COMSIG_MOB_SURGERY_STARTED "mob_surgery_started"

/// From /datum/surgery/Destroy(): (surgery_type, surgery_location, obj/item/bodypart/targeted_limb)
#define COMSIG_MOB_SURGERY_FINISHED "mob_surgery_finished"

/// From /datum/surgery_step/success(): (datum/surgery_step/step, mob/living/target, target_zone, obj/item/tool, datum/surgery/surgery, default_display_results)
#define COMSIG_MOB_SURGERY_STEP_SUCCESS "mob_surgery_step_success"

/// A condition was attached, removed, or crossed a clinically meaningful threshold.
#define COMSIG_MOB_MEDICAL_ISSUES_CHANGED "mob_medical_issues_changed"

/// From /obj/item/shockpaddles/do_help, after the defib do_after is complete, but before any effects are applied: (mob/living/defibber, obj/item/shockpaddles/source)
#define COMSIG_DEFIBRILLATOR_PRE_HELP_ZAP "carbon_being_defibbed"
	/// Return to stop default defib handling
	#define COMPONENT_DEFIB_STOP (1<<0)

/// From /obj/item/shockpaddles/proc/do_success(): (obj/item/shockpaddles/source)
#define COMSIG_DEFIBRILLATOR_SUCCESS "defib_success"
	// #define COMPONENT_DEFIB_STOP (1<<0) // Same return, to stop default defib handling

/// From /obj/item/shockpaddles/proc/do_disarm(), sent to the shock-ee in non-revival scenarios: (obj/item/shockpaddles/source)
#define COMSIG_HEARTATTACK_DEFIB "heartattack_defib"

/// From /datum/surgery/can_start(): (mob/source, datum/surgery/surgery, mob/living/patient)
#define COMSIG_SURGERY_STARTING "surgery_starting"
	#define COMPONENT_CANCEL_SURGERY (1<<0)
	#define COMPONENT_FORCE_SURGERY (1<<1)

/// From /datum/body/add_affliction() and remove_affliction(): (datum/affliction/affliction, added)
#define COMSIG_BODY_AFFLICTIONS_CHANGED "body_afflictions_changed"
/// From /datum/affliction/proc/set_severity(), sent to the owning mob: (datum/affliction/affliction, old_severity)
#define COMSIG_AFFLICTION_SEVERITY_CHANGED "affliction_severity_changed"
/// From base of /mob/living/proc/injure(), before mitigation: (kind, list/amount_ref, zone, atom/source, flags). amount_ref[1] may be modified.
#define COMSIG_LIVING_INJURE "living_injure"
	#define COMPONENT_CANCEL_INJURY (1<<0)
/// From /mob/living/proc/injure(), mitigation stage 2 (energy shields), after armour: (kind, list/amount_ref, zone, atom/source, flags). Shields scale amount_ref[1].
#define COMSIG_LIVING_SHIELD_INJURY "living_shield_injury"
/// From /mob/living/proc/injure() once mitigation is done, when something listens or the injury trace is on:
/// (incoming_kind, landed_kind, list/stages, zone, atom/source, flags). Each stage is list(INJURY_STAGE_*, amount_in, amount_out, detail).
#define COMSIG_LIVING_INJURY_EXPLAINED "living_injury_explained"
/// From base of /mob/living/proc/injure(), after the injury applied: (kind, applied, zone, atom/source, flags)
#define COMSIG_LIVING_INJURED "living_injured"
/// From /datum/body/proc/recompute_factors() when a body factor value changed: ()
#define COMSIG_LIVING_FACTORS_CHANGED "living_factors_changed"
