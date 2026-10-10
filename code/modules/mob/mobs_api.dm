// The mob system's API (code/modules/mob/mob_service.dm declares the system).
//
//   SSmobs.report_death(mob)   queue a living mob's death for the death table and check the round's win condition

/datum/system/mobs/proc/report_death(mob/living/L)
	if(!L)
		return
	if(!L.key || !L.mind)
		return
	if(!SSticker || !ticker_mode())
		return
	SSticker.mode.check_win()

	// Don't bother with the rest if we've not got a DB to do anything with
	if(!CONFIG_GET(flag/enable_stat_tracking) || !CONFIG_GET(flag/sql_enabled))
		return

	var/area/placeofdeath = get_area(L)
	var/podname = placeofdeath ? placeofdeath.name : "Unknown area"

	var/laname = ""
	var/lakey = ""
	var/mob/lastattacker = L.lastattacker
	if(istype(lastattacker))
		laname = lastattacker.real_name
		lakey = lastattacker.key

	var/list/data = list(
	"name" = "[L.real_name]",
	"byondkey" = "[L.key]",
	"job" = "[L.mind.assigned_role]",
	"special" = "[L.mind.special_role]",
	"pod" = podname,
	"tod" = time2text(world.realtime, "YYYY-MM-DD hh:mm:ss"),
	"laname" = laname,
	"lakey" = lakey,
	"gender" = L.gender,
	"bruteloss" = L.injury_load(INJURY_CATEGORY_PHYSICAL),
	"fireloss" = L.injury_load(INJURY_CATEGORY_THERMAL),
	"brainloss" = L.injury_load(INJURY_CATEGORY_NEURAL),
	"oxyloss" = L.oxygen_debt(),
	"coord" = "[L.x], [L.y], [L.z]"
	)
	death_list += list(data)
