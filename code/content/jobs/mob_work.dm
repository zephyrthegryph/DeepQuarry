// Content-specific callbacks for mob work.

/datum/task/mob_work/spider_web
	name = "spider_web"
	complete_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/web_done
	cancel_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/work_interrupted

/datum/task/mob_work/spider_eggs
	name = "spider_eggs"
	complete_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/eggs_done
	cancel_proc = /mob/living/simple_mob/animal/giant_spider/nurse/proc/work_interrupted

/datum/task/mob_work/ant_build
	name = "ant_build"
	complete_proc = /mob/living/simple_mob/animal/tyr/mineral_ants/proc/build_done
	cancel_proc = /mob/living/simple_mob/animal/tyr/mineral_ants/proc/build_interrupted

/// The cloak needs only a living mob: no claim, no range.
/datum/task/mob_work/cloak
	name = "cloak"
	duration = 1 SECOND
	claims = FALSE
	complete_proc = /mob/living/simple_mob/animal/space/mouse_army/stealth/proc/cloak_done
	cancel_proc = /mob/living/simple_mob/animal/space/mouse_army/stealth/proc/cloak_interrupted

/datum/task/mob_work/cloak/check_reason()
	var/mob/M = actor
	if(!istype(M) || M.stat == DEAD)
		return "not alive"
	return null

/datum/task/mob_work/cloak/watched_reads()
	return list(list(actor, "stat"))
