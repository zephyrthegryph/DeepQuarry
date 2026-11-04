//Syndicate catslug
/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug/syndislug
	name = "Mercenyary"
	desc = "What are you doing staring at this crimson-hardsuit wearing angry little fella? <b>Run.</b>"
	tt_desc = "Mollusca Felis Mors"
	icon_state = "syndislug"
	icon_living = "syndislug"
	icon_rest = "syndislug_rest"
	icon_dead = "syndislug_dead"
	myid_access = list(ACCESS_MAINT_TUNNELS, ACCESS_SYNDICATE, ACCESS_EXTERNAL_AIRLOCKS)
	endurance = 100		//Tough noodles
	taser_kill = 0
	melee_damage_lower = 15
	melee_damage_upper = 20
	mob_size = MOB_MEDIUM		//Something something hardsuits are heavy.
	siemens_coefficient = 0

	minbodytemp = 0
	maxbodytemp = 5000

	player_msg = "You are in the employ of a criminal syndicate hostile to corporate interests. Follow the Mercenary or Commando's orders and assist them in their goals by any means available."

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug/syndislug)
	configure(atom_rules(armor_spec = "melee=80;bullet=65;laser=50;energy=15;bomb=80;bio=100;rad=60", catalogue_data = list(/datum/category_item/catalogue/fauna/catslug)))
	configure(mob_rules(faction = FACTION_SYNDICATE))
	configure(living_rules(say_list_type = /datum/say_list/catslug))
	owns_one(nameof(mob_radio), /obj/item/radio/headset, starts = /obj/item/radio/headset/mob_headset/syndislug)

/mob/living/simple_mob/vore/alienanimals/catslug/custom/spaceslug/syndislug/id_access()
	return ..() | SSaccess.get_all_station_access()
