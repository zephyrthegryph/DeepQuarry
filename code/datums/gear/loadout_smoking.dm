// DQEdit — DeepQuarry preferences + loadout rewrite (commit fd3e36a673). Bay preference_setup framework deleted; /datum/gear loadout catalog relocated from code/modules/client/preference_setup/loadout/ to code/datums/gear/.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.


/datum/gear/pipe
	display_name = "pipe"
	path = /obj/item/clothing/mask/smokable/pipe

/datum/gear/pipe/New()
	..()
	var/list/pipes = list()
	for(var/pipe_style in typesof(/obj/item/clothing/mask/smokable/pipe))
		var/obj/item/clothing/mask/smokable/pipe/pipe = pipe_style
		pipes[initial(pipe.name)] = pipe
	gear_tweaks += new/datum/gear_tweak/path(sortAssoc(pipes))

/datum/gear/matchbook
	display_name = "matchbook"
	path = /obj/item/storage/box/matches

/datum/gear/lighter
	display_name = "cheap lighter"
	path = /obj/item/flame/lighter

/datum/gear/lighter/zippo
	display_name = "Zippo selection"
	path = /obj/item/flame/lighter/zippo

/datum/gear/lighter/zippo/New()
	..()
	var/list/zippos = list()
	for(var/zippo in typesof(/obj/item/flame/lighter/zippo))
		var/obj/item/flame/lighter/zippo/zippo_type = zippo
		zippos[initial(zippo_type.name)] = zippo_type
	gear_tweaks += new/datum/gear_tweak/path(sortAssoc(zippos))

/datum/gear/ashtray
	display_name = "ashtray, plastic"
	path = /obj/item/material/ashtray/plastic

/datum/gear/cigar
	display_name = "cigar"
	path = /obj/item/clothing/mask/smokable/cigarette/cigar

/datum/gear/cigarettes
	display_name = "cigarette selection"
	path = /obj/item/storage/fancy/cigarettes

/datum/gear/cigarettes/New()
	..()
	var/list/cigarettes = list()
	for(var/obj/item/storage/fancy/cigarettes/cigarette_brand as anything in (typesof(/obj/item/storage/fancy/cigarettes)))
		cigarettes[initial(cigarette_brand.name)] = cigarette_brand
	gear_tweaks += new/datum/gear_tweak/path(sortAssoc(cigarettes))
