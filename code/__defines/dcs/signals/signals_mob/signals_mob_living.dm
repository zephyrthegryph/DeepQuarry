
// Organ signals


///from base of mob/living/revive() (full_heal, admin_revive)
#define COMSIG_LIVING_REVIVE "living_revive"


/// from /datum/body/evaluate_status(), before death/unconsciousness is applied: ()
#define COMSIG_LIVING_BODY_STATUS "living_body_status"
	/// The mob neither dies nor falls unconscious from its injuries.
	#define COMPONENT_BODY_KEEP_ALIVE (1<<0)


// Sent before a status increase (a status row's "signal", code/datums/om/status.dm) (amount). Only for
// increases, and only when the mob isn't immune.

///before a stun increase (amount)
#define COMSIG_LIVING_STATUS_STUN "living_stun"
///before a paralysis increase (amount)
#define COMSIG_LIVING_STATUS_PARALYZE "living_paralyze"
///before a sleep increase (amount)
#define COMSIG_LIVING_STATUS_SLEEP "living_sleeping"
	#define COMPONENT_NO_STUN (1<<0) //For all of them: cancels the increase


	// Return COMPONENT_CANCEL_ATTACK_CHAIN / COMPONENT_SKIP_ATTACK_CHAIN to stop the grab


// Non TG signals:
///From the disabilities life system.
#define COMSIG_HANDLE_DISABILITIES "handle_disabilities"
///From /living/handle_allergens().
#define COMSIG_HANDLE_ALLERGENS "handle_allergens"

///before a weakness increase (amount)
#define COMSIG_LIVING_STATUS_WEAKEN "living_weaken"
///before a blindness increase (amount)
#define COMSIG_LIVING_STATUS_BLIND "living_blind"
///from /mob/living/proc/stun_effect_act(var/stun_amount, var/agony_amount, var/def_zone, var/used_weapon=null, var/electric = FALSE)
#define COMSIG_STUN_EFFECT_ACT "stun_effect_act"

///from the radiation life system
#define COMSIG_HANDLE_RADIATION "handle_radiation"
	#define COMPONENT_BLOCK_LIVING_RADIATION (1<<0)
///from base of /mob/living/proc/apply_effect(var/effect = 0,var/effecttype = STUN, var/blocked = 0, var/check_protection = 1, rad_protection)
#define COMSIG_LIVING_IRRADIATE_EFFECT "living_irradiate_effect"
	#define COMPONENT_BLOCK_IRRADIATION (1<<0)

///from /mob/living/proc/apply_effect(effect, effecttype, blocked, check_protection)
#define COMSIG_TAKING_APPLY_EFFECT "applying_effect"
///Return this in response if you don't want the effect to be applied
	#define COMSIG_CANCEL_EFFECT (1<<0)
///from the mutations life system
#define COMSIG_HANDLE_MUTATIONS "handle_mutations"
	#define COMPONENT_BLOCK_LIVING_MUTATIONS (1<<0)
///from base of /mob/living/regenerate_limbs(): (noheal, excluded_limbs)
#define COMSIG_LIVING_REGENERATE_LIMBS "living_regen_limbs"


//Ventcrawling


///called when a living mob collides with a dense turf : /mob/living/proc/turf_collision(var/turf/T, var/speed)
#define COMSIG_LIVING_TURF_COLLISION "living_turf_collision"
	#define COMPONENT_LIVING_BLOCK_TURF_COLLISION (1<<0)
