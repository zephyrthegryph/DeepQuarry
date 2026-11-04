//ERT catslug
/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug/responseslug
	name = "Emeowgency Responder"
	desc = "The cavalry has arrived."
	tt_desc = "Mollusca Felis Salvator"
	icon_state = "responseslug"
	icon_living = "responseslug"
	icon_rest = "responseslug_rest"
	icon_dead = "responseslug_dead"
	myid_access = list(ACCESS_CENT_GENERAL, ACCESS_CENT_SPECOPS, ACCESS_CENT_LIVING, ACCESS_CENT_STORAGE)
	endurance = 100		//Tough noodles
	taser_kill = 0
	mob_size = MOB_MEDIUM		//Something something hardsuits are heavy.
	siemens_coefficient = 0

	minbodytemp = 0
	maxbodytemp = 5000

	player_msg = "You are an <b>anti</b> antagonist! Within the rules, try to save the station and its inhabitants from the ongoing crisis. Try to make sure other players have <i>fun</i>! \
	If you are status_units(STAT_CONFUSED) or at a loss, always adminhelp, and before taking extreme actions, please try to also contact the administration! \
	Think through your actions and make the roleplay immersive! <b>Please remember all rules aside from those without explicit exceptions apply to the ERT.</b>"

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug/responseslug)
	configure(atom_rules(armor_spec = "melee=60;bullet=50;laser=30;energy=15;bomb=30;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/catslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug))
	owns_one(nameof(mob_radio), /obj/item/radio/headset, starts = /obj/item/radio/headset/mob_headset/responseslug)

/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug/responseslug/id_access()
	return ..() | SSaccess.get_all_station_access()
