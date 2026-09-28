
// Organ signals


///from /mob/living/proc/return_from_death(), after the mob is alive again: (datum/source, reason)
#define COMSIG_LIVING_REVIVED "living_revived"
///from /mob/proc/death(), once per death, after EVERY death side effect (on_death(), HUD refresh,
///antag win check): (gibbed). Never sent on a repeated or replaced death. Hang end-of-death work
///(delete_on_death) here; death() itself never deletes the mob.
#define COMSIG_LIVING_DEATH_FINAL "living_death_final"


/// from /datum/body/evaluate_status(), before death/unconsciousness is applied: ()
#define COMSIG_LIVING_BODY_STATUS "living_body_status"
	/// The mob neither dies nor falls unconscious from its injuries.


// Sent before a status increase (a status row's "signal", code/datums/om/status.dm) (amount). Only for
// increases, and only when the mob isn't immune.

///before a stun increase (amount)
#define COMSIG_LIVING_STATUS_STUN "living_stun"
///before a paralysis increase (amount)
#define COMSIG_LIVING_STATUS_PARALYZE "living_paralyze"
///before a sleep increase (amount)
#define COMSIG_LIVING_STATUS_SLEEP "living_sleeping"


	// Return COMPONENT_CANCEL_ATTACK_CHAIN / COMPONENT_SKIP_ATTACK_CHAIN to stop the grab


// Non TG signals:
///From the disabilities life system.
#define COMSIG_HANDLE_DISABILITIES "handle_disabilities"

///before a weakness increase (amount)
#define COMSIG_LIVING_STATUS_WEAKEN "living_weaken"
///before a blindness increase (amount)
#define COMSIG_LIVING_STATUS_BLIND "living_blind"

///from the radiation life system
#define COMSIG_HANDLE_RADIATION "handle_radiation"
///from base of /mob/living/proc/apply_effect(var/effect = 0,var/effecttype = STUN, var/blocked = 0, var/check_protection = 1, rad_protection)
#define COMSIG_LIVING_IRRADIATE_EFFECT "living_irradiate_effect"

///from the mutations life system
#define COMSIG_HANDLE_MUTATIONS "handle_mutations"
///from base of /mob/living/regenerate_limbs(): (noheal, excluded_limbs)
#define COMSIG_LIVING_REGENERATE_LIMBS "living_regen_limbs"


//Ventcrawling


///called when a living mob collides with a dense turf : /mob/living/proc/turf_collision(var/turf/T, var/speed)
#define COMSIG_LIVING_TURF_COLLISION "living_turf_collision"
