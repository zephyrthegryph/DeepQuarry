// Presentation reactions on /mob: roots, helpers reached by call, published keys, owned object vars.
/mob/living
	var/health_pct = 100
	var/dsoverlay
	var/seer
	var/shock = 0
	var/datum/thing/target
	var/list/queue
	var/alerts
	var/lying
	var/blinded = 0
	var/published_one = 0
	var/untracked_two = 0
	var/hidden_three = 0

TRACKED(/mob/living, blinded)
PUBLISHED_BY(/mob/living, published_one, KEY_ONE)

/mob/living/life_hud()
	var/n = health_pct
	dsoverlay = shock
	life_hud_extra()
	src.life_hud_health_icons()
	unrelated_helper()
	return alerts + target + published_one

/mob/living/life_hud_health_icons()
	return health_pct + queue + untracked_two

/mob/living/life_hud_darksight()
	// ALLOW(derived_reads): fixture keep for a reaction read
	return hidden_three

/mob/living/life_hud_extra()
	return blinded + lying + shock

/mob/living/unrelated_helper()
	return untracked_two

/mob/living/life_vision()
	process_glasses()
	return seer + health_pct + hidden_three

/mob/living/process_glasses()
	return shock + untracked_two

/mob/living/life_canmove()
	update_canmove()
	return lying + shock

/mob/living/update_canmove()
	return queue

/mob/living/carbon/life_vision()
	return published_one + hidden_three

/mob/living/carbon/derived()
	. += runs_while(nameof(shock))

/mob/living/carbon/should_run()
	return shock + untracked_two

/obj/pump
	var/pressure = 0

/obj/pump/reactions()
	. = ..()
	. += every(1 SECONDS, PROC_REF(step), members = /datum/capability/pumped)
	. += on_notice(/datum/notice/x, PROC_REF(h))
	. += on_cross(PROC_REF(c))
	. += after_init(PROC_REF(a))
	. += every(2 SECONDS, PROC_REF(step2))

/obj/other_pump/reactions()
	. += every(1 SECONDS, PROC_REF(step), members = /datum/capability/alpha)

/proc/reactions()
	. += every(1 SECONDS, PROC_REF(nope))
