/datum/category_item/catalogue/fauna/startreader
	name = "Alien Wildlife - Star Treader"
	desc = "A hard shelled creature that lives on asteroids.\
	It is quite durable and very opportunistic in its feeding habits.\
	It is vulnerable to extreme vibrations, and from the bottom."
	value = CATALOGUER_REWARD_EASY


/mob/living/simple_mob/vore/alienanimals/startreader
	name = "asteroid star treader"
	desc = "A slow, hard shelled creature that stalks asteroids."
	tt_desc = "Testudines Stellarus"
	catalogue_data = list(/datum/category_item/catalogue/fauna/startreader)

	icon = 'icons/mob/alienanimals_x32.dmi'
	icon_state = "startreader"
	icon_living = "startreader"
	icon_dead = "startreader_dead"

	faction = FACTION_SPACE_TURTLE
	endurance = 1000
	movement_cooldown = 10

	see_in_dark = 10

	response_help  = "pets"
	response_disarm = "gently pushes aside"
	response_harm   = "punches"

	harm_intent_damage = 1
	melee_damage_lower = 1
	melee_damage_upper = 10
	attacktext = list("chomped", "bashed", "monched", "bumped")


	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	minbodytemp = 0
	maxbodytemp = 900

	loot_list = list(/obj/random/underdark/uncertain = 25)

	armor_spec = "melee=100;bullet=100;laser=100;energy=100;bio=100;rad=100"

	speak_emote = list("rumbles")

	say_list_type = /datum/say_list/startreader

	vore_active = 1
	vore_capacity = 2
	vore_bump_chance = 25
	vore_ignores_undigestable = 0
	vore_default_mode = DM_DRAIN
	vore_icons = SA_ICON_LIVING
	vore_stomach_name = "gastric sac"
	vore_default_contamination_flavor = "Wet"
	vore_default_contamination_color = "grey"
	vore_default_item_mode = IM_DIGEST

	var/flipped = FALSE
	var/flip_cooldown = 0

	can_be_drop_prey = FALSE

/datum/say_list/startreader
	emote_see = list("bobs", "digs around","gnashes at something","yawns","snaps at something")
	emote_hear = list("thrumms","clicks","rattles","groans","burbles")


/mob/living/simple_mob/vore/alienanimals/startreader/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "gastric sac"
	B.desc = "It's cramped and hot! You're forced into a small ball as your shape is squeezed into the slick, wet chamber. Despite being swallowed into the creature, you find that you actually stretch out of the top a ways, and can JUST BARELY wiggle around..."
	B.mode_flags = 40
	B.digest_brute = 0.5
	B.digest_burn = 0.5
	B.digestchance = 10
	B.absorbchance = 0
	B.escapechance = 15

/mob/living/simple_mob/vore/alienanimals/startreader/apply_melee_effects(mob/living/L)
	if(!isliving(L))
		return
	if(L.has_status(EFFECT_WEAKENED)) //Don't stun people while they're already stunned! That's SILLY!
		return
	if(prob(15))
		visible_message(span_danger("\The [src] trips \the [L]!"))
		L.status_adjust(EFFECT_WEAKENED, rand(1,10))

/datum/life_system/type_post/simple_mob/vore/alienanimals/startreader
	mob_type = /mob/living/simple_mob/vore/alienanimals/startreader

/datum/life_system/type_post/simple_mob/vore/alienanimals/startreader/tick(mob/living/simple_mob/vore/alienanimals/startreader/self, datum/life_context/ctx)
	..()
	if(self.flip_cooldown == 1)
		self.flip_cooldown = 0
		self.flipped = FALSE
		self.handle_flip()
		self.visible_message(span_notice("\The [self] rights itself!!!"))
		return
	if(self.flip_cooldown)
		self.flip_cooldown --
		self.status_set(EFFECT_STUNNED, 2)

/mob/living/simple_mob/vore/alienanimals/startreader/proc/handle_flip()
	if(flipped)
		set_armor(dq_armor_none())
		icon_living = "startreader_flipped"
		status_adjust(EFFECT_STUNNED, flip_cooldown)
	else
		set_armor(dq_armor(list(MELEE = 100, BULLET = 100, LASER = 100, ENERGY = 100, BIO = 100, ARMOR_RAD = 100)))
		icon_living = "startreader"
		status_set(EFFECT_STUNNED, 0)

	update_icon()
