//=============================================================================
//Admin-spawn only catslugs below - Expect overpowered things & silliness below
//=============================================================================

//Deathsquad catslug
/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug/deathslug
	name = "Asset Purrtection"
	desc = "What are you doing staring at this angry little fella? <b>Run.</b>"
	tt_desc = "Mollusca Felis Eversor"
	icon_state = "deathslug"
	icon_living = "deathslug"
	icon_rest = "deathslug_rest"
	icon_dead = "deathslug_dead"
	myid_access = list(ACCESS_CENT_GENERAL, ACCESS_CENT_SPECOPS, ACCESS_CENT_LIVING, ACCESS_CENT_STORAGE)
	endurance = 100		//Tough noodles
	taser_kill = 0
	mob_size = MOB_MEDIUM		//As funny as picking up deathslugs & throwing them at people to be merked would be, I'm not willing to sprite their holders. Something something hardsuit heavy can be the "IC" reason for this.
	siemens_coefficient = 0

	minbodytemp = 0
	maxbodytemp = 5000

	player_msg = "You work in the service of corporate Asset Protection, answering directly to the Board of Directors and Asset Protection Commandos."

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug/deathslug)
	configure(atom_rules(armor_spec = "melee=60;bullet=50;laser=50;energy=40;bomb=40;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/catslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug))
	owns_one(nameof(mob_radio), /obj/item/radio/headset, starts = /obj/item/radio/headset/mob_headset/deathslug)

/// The space slugs' cards open every station door as well.
/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug/deathslug/id_access()
	return ..() | SSaccess.get_all_station_access()
