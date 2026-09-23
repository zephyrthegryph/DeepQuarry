
// Organ signals


///from base of mob/living/ignite_mob() (/mob/living)
#define COMSIG_LIVING_IGNITED "living_ignite"
///from base of mob/living/extinguish_mob() (/mob/living)
#define COMSIG_LIVING_EXTINGUISHED "living_extinguished"
///from base of mob/living/revive() (full_heal, admin_revive)
#define COMSIG_LIVING_REVIVE "living_revive"
///From living/Life(). (deltatime, times_fired)
#define COMSIG_LIVING_LIFE "living_life"
	/// Block the Life() proc from proceeding... this should really only be done in some really wacky situations.
	#define COMPONENT_LIVING_CANCEL_LIFE_PROCESSING (1<<0)


/// from /datum/body/evaluate_status(), before death/unconsciousness is applied: ()
#define COMSIG_LIVING_BODY_STATUS "living_body_status"
	/// The mob neither dies nor falls unconscious from its injuries.
	#define COMPONENT_BODY_KEEP_ALIVE (1<<0)


//ALL OF THESE DO NOT TAKE INTO ACCOUNT WHETHER AMOUNT IS 0 OR LOWER AND ARE SENT REGARDLESS!

///from base of mob/living/Stun() (amount, ignore_canstun)
#define COMSIG_LIVING_STATUS_STUN "living_stun"
///from base of mob/living/Paralyze() (amount, ignore_canstun)
#define COMSIG_LIVING_STATUS_PARALYZE "living_paralyze"
///from base of mob/living/Sleeping() (amount, ignore_canstun)
#define COMSIG_LIVING_STATUS_SLEEP "living_sleeping"
	#define COMPONENT_NO_STUN (1<<0) //For all of them


	// Return COMPONENT_CANCEL_ATTACK_CHAIN / COMPONENT_SKIP_ATTACK_CHAIN to stop the grab


/// From /datum/status_effect/proc/on_creation() : (datum/status_effect/effect)
#define COMSIG_LIVING_STATUS_APPLIED "living_status_applied"

/// From /datum/status_effect/proc/Destroy() : (datum/status_effect/effect)
#define COMSIG_LIVING_STATUS_REMOVED "living_status_removed"


// Non TG signals:
///From /living/handle_disabilities().
#define COMSIG_HANDLE_DISABILITIES "handle_disabilities"
///From /living/handle_allergens().
#define COMSIG_HANDLE_ALLERGENS "handle_allergens"

//ALL OF THESE DO NOT TAKE INTO ACCOUNT WHETHER AMOUNT IS 0 OR LOWER AND ARE SENT REGARDLESS!

///from base of mob/Weaken() (amount, ignore_canstun)
#define COMSIG_LIVING_STATUS_WEAKEN "living_weaken"
///from base of mob/Confuse() (amount, ignore_canstun)
#define COMSIG_LIVING_STATUS_CONFUSE "living_confuse"
///from base of mob/Blind() (amount, ignore_canstun)
#define COMSIG_LIVING_STATUS_BLIND "living_blind"
///from /mob/living/proc/stun_effect_act(var/stun_amount, var/agony_amount, var/def_zone, var/used_weapon=null, var/electric = FALSE)
#define COMSIG_STUN_EFFECT_ACT "stun_effect_act"

///from /mob/living/proc/handle_radiation()
#define COMSIG_HANDLE_RADIATION "handle_radiation"
	#define COMPONENT_BLOCK_LIVING_RADIATION (1<<0)
///from base of /mob/living/proc/apply_effect(var/effect = 0,var/effecttype = STUN, var/blocked = 0, var/check_protection = 1, rad_protection)
#define COMSIG_LIVING_IRRADIATE_EFFECT "living_irradiate_effect"
	#define COMPONENT_BLOCK_IRRADIATION (1<<0)

///from /mob/living/proc/apply_effect(effect, effecttype, blocked, check_protection)
#define COMSIG_TAKING_APPLY_EFFECT "applying_effect"
///Return this in response if you don't want the effect to be applied
	#define COMSIG_CANCEL_EFFECT (1<<0)
///from /mob/living/proc/handle_mutations()
#define COMSIG_HANDLE_MUTATIONS "handle_mutations"
	#define COMPONENT_BLOCK_LIVING_MUTATIONS (1<<0)
///from base of /mob/living/regenerate_limbs(): (noheal, excluded_limbs)
#define COMSIG_LIVING_REGENERATE_LIMBS "living_regen_limbs"


//Ventcrawling

///called when a ventcrawling mob checks if it can begin ventcrawling : (obj/machinery/atmospherics/unary/vent_entered)
#define COMSIG_MOB_VENTCRAWL_CHECK "ventcrawl_check"
///called when a ventcrawling mob checks if it can enter a vent : (mob/entering_mob)
#define COMSIG_VENT_CRAWLER_CHECK "ventcrawl_check"
	#define VENT_CRAWL_BLOCK_ENTRY (1<<0)

///called when a ventcrawling mob enters a vent : (obj/machinery/atmospherics/unary/vent_entered)
#define COMSIG_MOB_VENTCRAWL_START "ventcrawl_start"
///called when a ventcrawling mob leaves a vent : (obj/machinery/atmospherics/unary/vent_exited)
#define COMSIG_MOB_VENTCRAWL_END "ventcrawl_end"

///called when a ventcrawling mob enters a vent : (mob/entering_mob)
#define COMSIG_VENT_CRAWLER_ENTERED "ventcrawl_entered_vent"
///called when a ventcrawling mob leaves a vent : (mob/exiting_mob)
#define COMSIG_VENT_CRAWLER_EXITED "ventcrawl_exit_vent"

///called when a living mob collides with a dense turf : /mob/living/proc/turf_collision(var/turf/T, var/speed)
#define COMSIG_LIVING_TURF_COLLISION "living_turf_collision"
	#define COMPONENT_LIVING_BLOCK_TURF_COLLISION (1<<0)
