/mob/living/simple_mob/clowns/big/c_shift/honkelemental
	name = "Honk Elemental"
	desc = "That thing can't be real, right?"
	tt_desc = "E Homo sapiens corydon horrificus" //this is a redspace clown
	icon = 'icons/mob/mobs_monsters/giantclowns.dmi'
	icon_state = "honk_elemental"
	icon_living = "honk_elemental"
	icon_dead = "he_dead"
	icon_gib = "generic_gib"
	vis_height = 96


	loot_list = list(/obj/item/bikehorn = 100)

	response_help = "pokes"
	response_disarm = "gently pushes aside"
	response_harm = "hits"


CAPABILITIES(/mob/living/simple_mob/clowns/big/c_shift/honkelemental)
	op("spawn_egg", menu(), label("Spawn Clown Egg"), needs(req_self(), req(PROC_REF(spawn_egg_ready))), then(PROC_REF(spawn_egg_op)))
	configure(mob_rules(faction = FACTION_CLOWN))
	configure(living_rules(say_list_type = /datum/say_list/clown))

/datum/say_list/clown
	speak = list("HONK", "Honk!", "Henk!")
	emote_see = list("honks")

/mob/living/simple_mob/clowns/big/c_shift/honkelemental/proc/spawn_egg_ready(datum/act/op/A)
	if(is_dead())
		return MSG(req_silent)
	return null

/mob/living/simple_mob/clowns/big/c_shift/honkelemental/proc/spawn_egg()
	new /obj/structure/ghost_pod/manual/clegg(get_turf(src))
	flick("he_lay",src)

/mob/living/simple_mob/clowns/big/c_shift/honkelemental/proc/spawn_egg_op(datum/act/op/A)
	spawn_egg()
