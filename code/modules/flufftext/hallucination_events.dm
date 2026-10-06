/////////////////////////////////////////////////////////////////////////////////////////////////////
// Hallucination events
/////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/hallucinations/proc/event_hudscrew()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	//Screwy HUD
	//to_chat(our_human, "Screwy HUD")
	hal_screwyhud = pick(list(
								HUD_HALLUCINATION_CRIT,
								HUD_HALLUCINATION_TOXIN,
								HUD_HALLUCINATION_OXY,
								HUD_HALLUCINATION_ONFIRE
							))
	after(src, rand(15,35) SECONDS, PROC_REF(clear_screwyhud))

/datum/hallucinations/proc/event_painmessage()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	//Fake pain messages
	//to_chat(our_human, "fake messages")
	var/list/pain_message = list("The inside of your head hurts...",
								"Your stomach hurts.",
								"You feel sick.",
								"Your upper body hurts.",
								"Your head hurts.",
								"Your arm hurts.",
								"Your leg hurts.",
								"Your lower body hurts.",
								"Your foot hurts.",
								"Your hand hurts.",
								"The pain is excruciating!",
								"Your whole body is going numb!",
								"You feel like you could die any moment now!",
								"Please, just end the pain!",
								"You feel a sudden pain across your body.",
								"You cringe as a violent pain takes over your body.",
								"It feels like your body is eating itself inside out.",
								"IT HURTS.",
								"Your body feels as if it's trying to rip itself open..."
								)
	if(prob(20) && our_human.status_units(STAT_JITTERY) < 50)
		our_human.status_adjust(STAT_JITTERY, 120)
	to_chat(our_human, span_danger(pick(pain_message)))

/datum/hallucinations/proc/event_fake_item()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	//Strange items
	//to_chat(our_human, "Traitor Items")
	if(halitem)
		return

	var/list/slots_free = list(ui_lhand,ui_rhand)
	if(our_human.get_equipped_item(SLOT_ID_HAND_L))
		slots_free -= ui_lhand
	if(our_human.get_equipped_item(SLOT_ID_HAND_R))
		slots_free -= ui_rhand
	if(!our_human.get_equipped_item(SLOT_ID_BELT))
		slots_free += ui_belt
	if(!our_human.get_equipped_item(SLOT_ID_POCKET_L))
		slots_free += ui_storage1
	if(!our_human.get_equipped_item(SLOT_ID_POCKET_R))
		slots_free += ui_storage2

	if(!slots_free.len)
		return

	var/obj/CI = new()
	CI.screen_loc = pick(slots_free)
	CI.hud_layerise()
	switch(rand(1,6))
		if(1) //revolver
			CI.icon = 'icons/obj/gun.dmi'
			CI.icon_state = "revolver"
			CI.name = "Revolver"
		if(2) //c4
			CI.icon = 'icons/obj/assemblies.dmi'
			CI.icon_state = "plastic-explosive0"
			CI.name = "Mysterious Package"
			if(prob(25))
				CI.icon_state = "c4small_1"
		if(3) //sword
			CI.icon = 'icons/obj/weapons.dmi'
			CI.icon_state = "longsword"
			CI.name = "Sword"
		if(4) //stun baton
			CI.icon = 'icons/obj/weapons.dmi'
			CI.icon_state = "stunbaton"
			CI.name = "Stun Baton"
		if(5) //emag
			CI.icon = 'icons/obj/card.dmi'
			CI.icon_state = "emag"
			CI.name = "Cryptographic Sequencer"
		if(6) //flashbang
			CI.icon = 'icons/obj/grenade.dmi'
			CI.icon_state = "flashbang1"
			CI.name = "Flashbang"
	rel_set(src, nameof(halitem), CI)
	rel_set(src, nameof(halitem_client), our_human.client)
	our_human.client.screen += CI
	after(src, rand(10,25) SECONDS, PROC_REF(remove_hallucination_item))

/datum/hallucinations/proc/remove_hallucination_item()
	// I can't manage this with /image/client_only due to screenloc, so an owned item plus its client it is! Called on both timer and destroying this component.
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(halitem_client && halitem)
		halitem_client.screen -= halitem
	rel_clear(src, nameof(halitem_client))
	own_clear(src, nameof(halitem), OWN_DELETE)

/datum/hallucinations/proc/event_strange_sound()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)

	//Strange audio
	var/send_sound
	switch(rand(1,12))
		if(1)
			send_sound = 'sound/machines/door/old_airlock.ogg'
		if(2)
			if(prob(50))
				send_sound = 'sound/effects/Explosion1.ogg'
			else
				send_sound = 'sound/effects/Explosion2.ogg'
		if(3)
			send_sound = 'sound/effects/explosionfar.ogg'
		if(4)
			send_sound = 'sound/effects/Glassbr1.ogg'
		if(5)
			send_sound = 'sound/effects/Glassbr2.ogg'
		if(6)
			send_sound = 'sound/effects/Glassbr3.ogg'
		if(7)
			send_sound = 'sound/machines/twobeep.ogg'
		if(8)
			send_sound = 'sound/machines/door/windowdoor.ogg'
		if(9)
			//To make it more realistic, I added two gunshots (enough to kill)
			send_sound = 'sound/weapons/gunshot1.ogg'
			after(src, rand(1,3) SECONDS, PROC_REF(secondary_sound), with = list('sound/weapons/gunshot2.ogg'))
		if(10)
			send_sound = 'sound/weapons/smash.ogg'
		if(11)
			//Same as above, but with tasers.
			send_sound = 'sound/weapons/taser.ogg'
			after(src, rand(1,3) SECONDS, PROC_REF(secondary_sound), with = list('sound/weapons/taser.ogg'))
	//Rare audio
		if(12)
//These sounds are (mostly) taken from Hidden: Source
			var/list/creepyasssounds = list('sound/effects/ghost.ogg', 'sound/effects/ghost2.ogg', 'sound/effects/Heart Beat.ogg', 'sound/effects/screech.ogg',\
				'sound/hallucinations/behind_you1.ogg', 'sound/hallucinations/behind_you2.ogg', 'sound/hallucinations/far_noise.ogg', 'sound/hallucinations/growl1.ogg', 'sound/hallucinations/growl2.ogg',\
				'sound/hallucinations/growl3.ogg', 'sound/hallucinations/im_here1.ogg', 'sound/hallucinations/im_here2.ogg', 'sound/hallucinations/i_see_you1.ogg', 'sound/hallucinations/i_see_you2.ogg',\
				'sound/hallucinations/look_up1.ogg', 'sound/hallucinations/look_up2.ogg', 'sound/hallucinations/over_here1.ogg', 'sound/hallucinations/over_here2.ogg', 'sound/hallucinations/over_here3.ogg',\
				'sound/hallucinations/turn_around1.ogg', 'sound/hallucinations/turn_around2.ogg', 'sound/hallucinations/veryfar_noise.ogg', 'sound/hallucinations/wail.ogg')
			send_sound = pick(creepyasssounds)

	our_human.playsound_local(get_turf(our_human), send_sound, vol = 75, channel = CHANNEL_AMBIENCE_FORCED)

/datum/hallucinations/proc/secondary_sound(sound_path)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	our_human.playsound_local(get_turf(our_human), sound_path, vol = 75, channel = CHANNEL_AMBIENCE_FORCED)

/datum/hallucinations/proc/event_flash_environmental_threats()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	//Flashes of danger
	//to_chat(our_human, "Danger Flash")
	if(halimage)
		return

	var/list/possible_points = list()
	for(var/turf/simulated/floor/F in view(our_human,world.view))
		possible_points += F
	if(!possible_points.len)
		return

	var/turf/simulated/floor/target = pick(possible_points)
	var/image/client_only/CI
	switch(rand(1,3))
		if(1)
			CI = new('icons/turf/space.dmi',target,"[rand(1,25)]",TURF_LAYER)
		if(2)
			CI = new('icons/effects/fire.dmi',target,"1",TURF_LAYER)
		if(3)
			CI = new('icons/obj/assemblies.dmi',target,"plastic-explosive2",OBJ_LAYER+0.01)
	halimage = CI
	CI.append_client(our_human.client)
	om_qdel_after(CI, rand(1,5) SECONDS) //Only seen for a brief moment.

/datum/hallucinations/proc/event_flash_monsters()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	//Flashes of danger
	//to_chat(our_human, "Danger Flash")
	if(halbody)
		return

	var/list/possible_points = list()
	for(var/turf/simulated/floor/F in view(our_human,world.view))
		possible_points += F
	if(!possible_points.len)
		return

	var/turf/simulated/floor/target = pick(possible_points)
	var/image/client_only/CI
	switch(rand(1,4))
		if(1)
			CI = new('icons/mob/human.dmi',target,"husk_l",TURF_LAYER)
		if(2,3)
			CI = new('icons/mob/human.dmi',target,"husk_s",TURF_LAYER)
		if(4)
			CI = new('icons/mob/alien.dmi',target,"alienother",TURF_LAYER)
	halbody = CI
	CI.append_client(our_human.client)
	om_qdel_after(CI, rand(5,8) SECONDS) //Only seen for a brief moment.

/datum/hallucinations/proc/event_sleeping()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	//Fake death
	//to_chat(our_human, "fake death")
	our_human.status_set(STAT_SLEEPING, 20)
	hal_crit = TRUE
	hal_screwyhud = HUD_HALLUCINATION_CRIT
	after(src, rand(5,10) SECONDS, PROC_REF(reset_hallucination_sleeping))

/datum/hallucinations/proc/clear_screwyhud()
	hal_screwyhud = HUD_HALLUCINATION_NONE

/datum/hallucinations/proc/reset_hallucination_sleeping()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	our_human.status_set(STAT_SLEEPING, 0)
	hal_crit = FALSE
	hal_screwyhud = HUD_HALLUCINATION_NONE

/datum/hallucinations/proc/event_attacker()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/attacker = our_human.create_hallucination_attacker(forced_type = /obj/effect/fake_attacker/human/attacker) // Currently just uses the attacker type for now, remove argument to use any other subtype
	if(attacker)
		om_qdel_after(attacker, rand(25,30) SECONDS)

/////////////////////////////////////////////////////////////////////////////////////////////////////
// Xenochimera feral events
/////////////////////////////////////////////////////////////////////////////////////////////////////
/datum/hallucinations/proc/event_hunger()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	//food
	if(halbody)
		return

	var/list/possible_points = list()
	for(var/turf/simulated/floor/F in view(our_human,world.view))
		possible_points += F
	if(!possible_points.len)
		return

	var/turf/simulated/floor/target = pick(possible_points)
	var/image/client_only/CI
	switch(rand(1,10))
		if(1)
			CI = new('icons/mob/animal.dmi',target,"cow",TURF_LAYER)
		if(2)
			CI = new('icons/mob/animal.dmi',target,"chicken",TURF_LAYER)
		if(3)
			CI = new('icons/obj/food.dmi',target,"bigbiteburger",TURF_LAYER)
		if(4)
			CI = new('icons/obj/food.dmi',target,"meatbreadslice",TURF_LAYER)
		if(5)
			CI = new('icons/obj/food.dmi',target,"sausage",TURF_LAYER)
		if(6)
			CI = new('icons/obj/food.dmi',target,"bearmeat",TURF_LAYER)
		if(7)
			CI = new('icons/obj/food.dmi',target,"fishfillet",TURF_LAYER)
		if(8)
			CI = new('icons/obj/food.dmi',target,"meat",TURF_LAYER)
		if(9)
			CI = new('icons/obj/food.dmi',target,"meatstake",TURF_LAYER)
		if(10)
			CI = new('icons/obj/food.dmi',target,"monkeysdelight",TURF_LAYER)

	halbody = CI
	CI.append_client(our_human.client)
	om_qdel_after(CI, rand(5,8) SECONDS) //Only seen for a brief moment.

/datum/hallucinations/proc/event_hear_voices()
	PROTECTED_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	//hear voices. Could make the voice pick from nearby creatures, but nearby creatures make feral hallucinations rare so don't bother.
	var/list/hiddenspeakers = list("Someone distant", "A voice nearby","A familiar voice", "An echoing voice", "A cautious voice", "A scared voice", "Someone around the corner", "Someone", "Something", "Something scary", "An urgent voice", "An angry voice")
	var/list/speakerverbs = list("calls out", "yells", "screams", "exclaims", "shrieks", "shouts", "hisses", "snarls")
	var/list/spookyphrases = list("It's over here!","Stop it!", "Hunt it down!", "Get it!", "Quick, over here!", "Anyone there?", "Who's there?", "Catch that thing!", "Stop it! Kill it!", "Anyone there?", "Where is it?", "Find it!", "There it is!")
	to_chat(our_human, span_game(span_say(span_name(pick(hiddenspeakers)) + " [pick(speakerverbs)], \"[pick(spookyphrases)]\"")))
