// Possum catalog entry.
/datum/category_item/catalogue/fauna/opossum
	name = "Opossums"
	desc = "The opossum is a small, scavenging marsupial of the order Didelphimorphia, previously \
	endemic to the Americas of Earth, but now inexplicably found across settled space. Nobody is \
	entirely sure how they travel to such disparate locations, with the leading theories including \
	smuggling, cargo stowaways, fungal spore reproduction, teleportation, or unknown quantum effects."
	value = CATALOGUER_REWARD_TRIVIAL
	unlocked_by_any = list(/datum/category_item/catalogue/fauna/opossum)

// Possum spawner, WAS GOING TO BE used for loot piles BUT CERB IS A DORK.
/obj/item/animal_spawner
	var/critter_type = /mob/living/simple_mob/animal/passive/mouse

CAPABILITIES(/obj/item/animal_spawner)
	map_resolver(GLOBAL_PROC_REF(resolve_animal_spawner), vars = list("critter_type"))

/// MAP_RESOLVER for animal spawners: the critter in its holder, where the spawner would have been
/// (in the hands of the mob holding it, if any).
/proc/resolve_animal_spawner(atom/loc, path, list/varedits)
	var/obj/item/animal_spawner/P = path
	var/mob/living/simple_mob/critter = MAP_VAR(P, varedits, critter_type)
	if(!ispath(critter, /mob/living/simple_mob))
		return TRUE
	var/obj/item/holder/critter_holder = initial(critter.holder_type)
	if(!ispath(critter_holder, /obj/item/holder))
		return TRUE
	critter = new critter(critter_holder)
	critter_holder = new critter_holder(loc, critter)
	var/mob/M = loc
	if(istype(M))
		M.put_in_hands(critter_holder)
	return TRUE

/obj/item/animal_spawner/possum
	name = "possum"
	desc = "The abstract concept of possum, embodied in physical form. If you witness the majesty of abstract possum, please make a bug report on the tracker."
	icon = 'icons/mob/animal.dmi'
	icon_state = "possum"
	critter_type = /mob/living/simple_mob/animal/passive/opossum

// Possum AI holder, mostly just handles playing dead.
/datum/say_list/possum
	speak = list("Hiss!","Aaa!","Aaa?")
	emote_hear = list("hisses")
	emote_see = list("forages for trash", "lounges")

// The poss itself.
/mob/living/simple_mob/animal/passive/opossum
	name = "opossum"
	real_name = "opossum"
	tt_desc = "Didelphis astrum"
	desc = "It's an opossum, a small scavenging marsupial."
	icon = 'icons/mob/pets.dmi'
	icon_state = "possum"
	item_state = "possum"
	icon_living = "possum"
	icon_dead = "possum_dead"
	icon_rest = "possum_dead"
	speak_emote = list("hisses")
	pass_flags = PASSTABLE
	see_in_dark = 6
	endurance = 50
	response_help = "pets"
	response_disarm = "gently pushes aside"
	response_harm = "stamps on"
	density = FALSE
	organ_names = /datum/decl/mob_organ_names/possum
	minbodytemp = 223
	maxbodytemp = 323
	universal_speak = FALSE
	universal_understand = TRUE
	holder_type = /obj/item/holder/possum
	mob_size = MOB_SMALL
	can_pull_size = 2
	can_pull_mobs = MOB_PULL_SMALLER
	say_list_type = /datum/say_list/possum
	catalogue_data = list(/datum/category_item/catalogue/fauna/opossum)
	meat_amount = 2

/mob/living/simple_mob/animal/passive/opossum/injure(kind, amount, zone = null, atom/source = null, armor_pen = 0, affliction = null, flags = NONE)
	. = ..()
	if(. && amount >= 3)
		var/category = injury_category(kind)
		if(category == INJURY_CATEGORY_PHYSICAL || category == INJURY_CATEGORY_THERMAL)
			respond_to_damage()

//respond_to_damage and update_icon for opossum live in
// code/modules/combat_ai/ports/possum.dm where they read the modern mob-side
// is_angry / play_dead_until vars instead of the deleted ai_holder.
/mob/living/simple_mob/animal/passive/opossum/proc/respond_to_damage()
	return

CAPABILITIES(/mob/living/simple_mob/animal/passive/opossum)
	verb_entry(/mob/living/proc/ventcrawl)
	verb_entry(/mob/living/proc/hide)

/mob/living/simple_mob/animal/passive/opossum/poppy
	name = "Poppy the Safety Possum"
	desc = "It's an opossum, a small scavenging marsupial. It's wearing appropriate personal protective equipment, though."
	icon_state = "poppy"
	item_state = "poppy"
	icon_living = "poppy"
	icon_dead = "poppy_dead"
	icon_rest = "poppy_dead"
	tt_desc = "Didelphis astrum salutem"
	organ_names = /datum/decl/mob_organ_names/poppy
	holder_type = /obj/item/holder/possum/poppy

/datum/decl/mob_organ_names/possum
TYPE_TABLE(/datum/decl/mob_organ_names/possum, mob_organ_hit_zones, list("head", "body", "left foreleg", "right foreleg", "left hind leg", "right hind leg", "pouch"))

/datum/decl/mob_organ_names/poppy
TYPE_TABLE(/datum/decl/mob_organ_names/poppy, mob_organ_hit_zones, list("head", "body", "left foreleg", "right foreleg", "left hind leg", "right hind leg", "pouch", "cute little jacket"))

CAPABILITIES(/mob/living/simple_mob/animal/passive/opossum/beastmode)
	verb_entry(/mob/living/proc/ventcrawl, hidden = TRUE) //No ventcrawl for hanner

