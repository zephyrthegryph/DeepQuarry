/obj/structure/redgate
	name = "redgate"
	desc = "It leads to someplace else!"
	icon = 'icons/obj/redgate.dmi'
	icon_state = "off"
	density = FALSE
	unacidable = TRUE
	anchored = TRUE
	pixel_x = -16

	var/tmp/obj/structure/redgate/target
	var/secret = FALSE	//If either end of the redgate has this enabled, ghosts will not be able to click to teleport
	var/static/list/exceptions = list(
		/obj/structure/ore_box,
		/obj/structure/bed/roller
		)	//made it a var so that GMs or map makers can selectively allow things to pass through
	var/static/list/restrictions = list(
		/mob/living/simple_mob/vore/overmap/stardog,
		/mob/living/simple_mob/vore/bigdragon
		)	//There are some things we don't want to come through no matter what.

// its paired gate closes (the link to it is undone with this gate, on both sides: the declared pair).
/obj/structure/redgate/on_destroy(force)
	var/obj/structure/redgate/other = target()
	if(other)
		other.toggle_portal(closing = TRUE)
	..()

/obj/structure/redgate/proc/teleport(mob/M as mob)
	var/keycheck = TRUE
	if (!isliving(M))		//We only want mob/living, no bullets or mechs or AI eyes or items
		if(is_type_in_list(M, exceptions))
			keycheck = FALSE		//we'll allow it
		else
			return
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.redgate_restricted)
			to_chat(M, span_warning("You can not walk through the redgate without another character giving you permission (by clicking on the redgate with you nearby)."))
			return

	if(is_type_in_list(M, restrictions))	//Some stuff we don't want to bring EVEN IF it has a key.
		return

	for(var/obj/O in contents_of(M))
		if(O.redgate_allowed == FALSE)
			to_chat(M, span_warning("The redgate refuses to allow you to pass whilst you possess \the [O]."))
			return

	if(keycheck)		//exceptions probably won't have a ckey
		if(!M.ckey)		//We only want players, no bringing the weird stuff on the other side back
			return

	if(!target())
		toggle_portal()

	var/turf/ourturf = find_our_turf(M)		//Find the turf on the opposite side of the target
	if(!ourturf.check_density(TRUE,TRUE))	//Make sure there isn't a wall there
		M.unbuckle_all_mobs(TRUE)
		if(isliving(M) && M?.pulling_target())
			var/atom/movable/pulled = M?.pulling_target()
			M.stop_pulling()
			play_sfx(src, SFX_EFFECTS_OMINOUS_HUM_2)
			M.forceMove(ourturf)
			if(is_type_in_list(pulled, exceptions))
				for(var/mob/living/buckled_on in pulled?.buckled_mob_list())
					if(!buckled_on.key || is_type_in_list(M, restrictions))
						pulled.unbuckle_mob(buckled_on, TRUE)
				pulled.forceMove(ourturf)
				M.continue_pulling(pulled)
			else
				to_chat(M, span_notice("The redgate refused your pulled item."))
		else
			play_sfx(src, SFX_EFFECTS_OMINOUS_HUM_2)
			M.forceMove(ourturf)		//Let's just do forcemove, I don't really want people teleporting to weird places if they have bluespace stuff
	else
		to_chat(M, span_notice("Something blocks your way."))

/obj/structure/redgate/proc/find_our_turf(atom/movable/AM)	//This finds the turf on the opposite side of the target gate from where you are
	var/offset_x = x - AM.x										//used for more smooth teleporting
	var/offset_y = y - AM.y

	var/turf/temptarg = locate((target().x + offset_x),(target().y + offset_y),target().z)

	return temptarg

/// Opens or closes the portal to match its link; `closing` says the partner is going and the link is not yet undone.
/obj/structure/redgate/proc/toggle_portal(closing = FALSE)
	if(target() && !closing)
		icon_state = "on"
		set_density(TRUE)
		plane = ABOVE_MOB_PLANE
		set_light(5, 0.75, "#da5656")
	else
		icon_state = "off"
		set_density(FALSE)
		plane = OBJ_PLANE
		set_light(0)

/// Something walked into it (the bump action's notice).
/obj/structure/redgate/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/mob/M = N.bumper
	src.teleport(M)
	return

/obj/structure/redgate/Crossed(mob/M as mob)
	src.teleport(M)
	return

/// Old attack_hand.
/obj/structure/redgate/proc/interaction_hand(datum/act/op/A)
	redgate_use(A.actor)
	return OP_OK

/// The hand use of a gate; it asks who to admit by re-running itself with the same arguments.
/obj/structure/redgate/proc/redgate_use(mob/M)
	if(density)
		if(ishuman(M))
			var/mob/living/carbon/human/O = M
			var/list/nearby_restricted = list()
			for(var/obj/structure/redgate/g in world)
				for(var/mob/living/carbon/human/H in oview(7,g))
					if(H.redgate_restricted && !O.redgate_restricted) //For every restricted human near the redgate, if you aren't restricted yourself, put them in a list.
						nearby_restricted |= H
			if(!nearby_restricted.len)
				teleport(M) //teleport functionality remains if no restricted people are nearby.
			else
				var/mob/living/carbon/human/restricted_human = rerun_ask(M, "k121", PROC_REF(redgate_use), args, /datum/prompt/choice, question = "Who do you wish to give access through the redgate?", title = "Nearby Redgate Inhabitants", choices = nearby_restricted)
				if(isnull(restricted_human))
					return
				if(!restricted_human)
					return
				restricted_human.redgate_restricted = FALSE
				to_chat(M, span_notice("You have given [restricted_human] permission to use the redgate."))
				to_chat(restricted_human, span_notice("[M] has given you permission to use the redgate."))
				log_and_message_admins("[M] has given [restricted_human] permission to use the redgate.")
		else
			teleport(M)
	else
		if(!find_partner())
			to_chat(M, span_warning("The [src] remains off... seems like it doesn't have a destination."))

/// Old attack_ghost: follow the gate to its target; with no target, the ghost default.
/obj/structure/redgate/proc/redgate_ghost_travel(datum/act/op/A)
	var/mob/observer/dead/user = A.actor
	if(!target())
		return OP_DECLINE
	if(!(secret || target().secret) || check_rights_for(user?.client, R_HOLDER))
		user.forceMove(get_turf(target()))
	return OP_OK

/obj/structure/redgate/away/Initialize(mapload)
	. = ..()
	if(!find_partner())
		log_and_message_admins("An away redgate spawned but wasn't able to find a gateway to link to. If this appeared at roundstart, something has gone wrong, otherwise if you spawn another gate they should connect.")

/obj/structure/redgate/proc/find_partner()
	for(var/obj/structure/redgate/g in world)
		if(istype(g, /obj/structure/redgate))
			if(g.target())
				continue
			else if(g == src)
				continue
			else if(g.z in using_map.station_levels)
				rel_set(src, nameof(target), g) // REL_PAIR: g's target names us back
				toggle_portal()
				target().toggle_portal()
				break
			else if(g != src)
				rel_set(src, nameof(target), g) // REL_PAIR: g's target names us back
				toggle_portal()
				target().toggle_portal()
				break
	if(!target())
		return FALSE
	else
		return TRUE

/area/redgate
	name = "redgate"
	icon = 'icons/turf/areas_vr.dmi'
	icon_state = "redblacir"
	base_turf = /turf/simulated/mineral/floor/cave

/obj/item/paper/teppiranch
	name = "elegantly scrawled note"
	info = {"<i>Goeleigh,<BR><BR>

	This isn't how I wanted to give this message to you. They say that the light is coming this way, and we won't even know it's here until it's upon us. There's no way to know when it will arrive, so we can't really afford to wait around. My family has secured us a ride on a ship, and we'll be going to one of the rimward colonies. They say that they are making strides to build some new kind of gate there, something that will take us far from that light, somewhere safe. We can't really bring the animals, but perhaps you can make some arrangements for them.<BR><BR>

	As soon as you read this, get yourself out of here and come find us. We left you enough money to make the trip in the usual spot. We'll be in the registry once we arrive. We're waiting for you.<BR><BR>

	Yours, Medley</i>"}

// City areas, there are soooo many

// Islands areas

//train areas

// fantasy areas

//WELCOME TO THE JUNGLE

//Facility locations

//The actual flags. Base type defined to handle some of the basic behaviours.
/obj/item/laserdome_flag
	name = "Flag"
	desc = "Steal the enemy flag and take it to your base in order to score! First team to three captures wins! Or was it five? Eh, check with the referee I guess."
	slowdown = 1 //big flag is harder to run with, encourages teamwork and lets the opposing team catch up. would be nice if this was a forced slowdown that ignores hardy.
	icon = 'icons/obj/flags.dmi'
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_vr.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_vr.dmi',
			)
	item_state = "laserdome_flag"
	icon_state = "flag"
	var/laser_team = "neutral"
	w_class = ITEMSIZE_NO_CONTAINER //no stashing the flag in a bag for you, bucko!
	redgate_allowed = FALSE //no running off the map with the flags either
	var/start_pos
	var/flag_return_delay = 3 SECONDS	//how long you have to hold onto your team's flag before it returns home

// ALLOW(init/INSTANCE_STATE): remembers where it was placed so it can return there
/obj/item/laserdome_flag/Initialize(mapload)
	. = ..()
	start_pos = src.loc	//save our starting location for later

/obj/item/laserdome_flag/proc/flag_return_failed(mob/user)
	user?.drop_from_inventory(src)

/obj/item/laserdome_flag/proc/flag_returned(mob/user)
	user.drop_from_inventory(src)
	src.forceMove(src.start_pos)
	GLOB.global_announcer.autosay("[capitalize(laser_team)] flag returned by [user]!","Laserdome Announcer","Entertainment")

CAPABILITIES(/obj/item/laserdome_flag)
	op("pick_up", hand(), label("Pick up"), then(PROC_REF(flag_pick_up)))

/// Picking the flag up: the other team is told who has it.
/obj/item/laserdome_flag/proc/flag_pick_up(datum/act/op/A)
	var/mob/user = A.actor
	. = OP_OK
	pick_up_by_hand(user)
	var/mob/living/carbon/human/M = loc
	var/grabbing_team

	//if they're not a carbon, we don't care
	if(!istype(M))
		return

	//get their uniform
	if(istype(M.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/lasertag/redtag))
		grabbing_team = "red"
	else if(istype(M.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/lasertag/bluetag))
		grabbing_team = "blue"
	else
		return	//if they're not on a team, stop!

	//set the verb based on matching (or mismatching) outfits, and teleport the flag back to base if it was touched by the owning team
	if(grabbing_team == laser_team)
		act_message(user, src, others = span_warning("%U% is returning %T%!"))
		//channel return, rather than instant; if they fail the channel (e.g. because they got tagged!) then drop it
		task_timed(user, flag_return_delay, src, src, PROC_REF(flag_returned), list(user), IGNORE_TARGET_LOC_CHANGE, PROC_REF(flag_return_failed), list(user))
		return
	else
		act_message(user, src, others = span_warning("%U% has taken %T%!"))
		GLOB.global_announcer.autosay("[src] taken by [capitalize(grabbing_team)] team!","Laserdome Announcer","Entertainment")

/obj/item/laserdome_flag/red
	name = "Red flag"
	icon_state = "red_flag"
	item_state = "laserdome_flag_red"
	laser_team = "red"

/obj/item/laserdome_flag/blue
	name = "Blue flag"
	icon_state = "blue_flag"
	item_state = "laserdome_flag_blue"
	laser_team = "blue"

//Finally, the flag bases. Both bases *must* be in the same map area (e.g. /area/ctf_arena) for the scoring system to work properly. But if they are, then it's basically just spawn-and-play, no other setup needed!
/obj/structure/flag_base
	name = "Flag base"
	desc = "Where your flag rests. Bring the enemy flag here to score!"
	icon = 'icons/obj/flags.dmi'
	icon_state = "flag_base"
	anchored = TRUE
	var/base_team
	var/score = 0
	var/score_limit = 3

/obj/structure/flag_base/blue
	name = "Blue team flag base"
	base_team = "blue"

/obj/structure/flag_base/red
	name = "Red team flag base"
	base_team = "red"

/obj/structure/flag_decor
	name = "Decorative flag"
	desc = "A decorative flag."
	icon = 'icons/obj/flags.dmi'
	icon_state = "flag"

/obj/structure/flag_decor/blue
	icon_state = "blue_flag_deco"

/obj/structure/flag_decor/red
	icon_state = "red_flag_deco"

CAPABILITIES(/obj/structure/flag_base)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/flag_base/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/F = A.held

	//TODO- require the team's flag to be present before they can score?
	if(istype(F,/obj/item/laserdome_flag))
		var/obj/item/laserdome_flag/flag = F
		if(flag.laser_team != base_team)
			GLOB.global_announcer.autosay("[user] captured the [capitalize(flag.laser_team)] flag for [capitalize(base_team)] team!","Laserdome Announcer","Entertainment")
			user.drop_from_inventory(flag)
			flag.forceMove(flag.start_pos) //teleport the captured flag back to its base location
			score++	//increment our score by 1!
			if(score < score_limit)	//announce the current score and how many more captures are needed
				GLOB.global_announcer.autosay("[num2text(score_limit-score)] captures remain until [capitalize(base_team)] team wins.","Laserdome Announcer","Entertainment")
			else if(score >= score_limit)	//now, if score equals or exceeds (somehow) the score limit, announce that our team won and reset the score for all flag bases nearby
				GLOB.global_announcer.autosay("+|[uppertext(base_team)] TEAM HAS WON THE MATCH!|+","Laserdome Announcer","Entertainment")
				for(var/obj/structure/flag_base/FB in contents_of(src.loc.loc))	//this feels dirty, but it works
					FB.score = 0
		else if(flag.laser_team == base_team)
			GLOB.global_announcer.autosay("[capitalize(base_team)] flag returned!","Laserdome Announcer","Entertainment")
			user.drop_from_inventory(flag)
			flag.forceMove(src.loc)			//place our flag neatly back on its pedestal
	return OP_PASS

/obj/item/laserdome_hyperball/get_mechanics_info(list/additional_information)
	return ..(list("Dunking the ball directly into the opposing goal scores more points than throwing it in, but you must be next to the goal.") + additional_information)

/obj/item/laserdome_hyperball
	name = "\improper HYPERball"	//*always* refer to it as "the hyperball", not just "the ball". corporate insists.
	desc = "Because regular balls aren't exciting enough, the future needs HYPERballs!"
	slowdown = -0.5	//carrying the ball actually speeds you up a little bit? given you need to get past enemy defense and dunk. also makes it easier to get the ball away from your base if you intercept.
	icon = 'icons/obj/flags.dmi'
	icon_state = "hyperball"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_vr.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_vr.dmi',
			)
	item_state = "hyperball"
	w_class = ITEMSIZE_NO_CONTAINER	//no shoving it in your backpack to hide it
	redgate_allowed = FALSE	//you can't take your ball and go home
	var/start_pos
	var/last_holder
	var/last_team

/obj/item/laserdome_hyperball_prop
	name = "demonstration HYPERball"
	desc = "Because regular balls aren't exciting enough, the future needs HYPERballs!"
	slowdown = 3	//really discourage people from trying to actually use these in the game if they get them out of the display cases
	icon = 'icons/obj/flags.dmi'
	icon_state = "hyperball"
	w_class = ITEMSIZE_NO_CONTAINER
	redgate_allowed = FALSE //you can't take the demonstration balls and go home either

// ALLOW(init/INSTANCE_STATE): remembers where it was placed so it can return there
/obj/item/laserdome_hyperball/Initialize(mapload)
	. = ..()
	start_pos = src.loc	//save our starting location for later

CAPABILITIES(/obj/item/laserdome_hyperball)
	op("pick_up", hand(), label("Pick up"), then(PROC_REF(hyperball_pick_up)))

/// Picking the ball up: the teams are told who has it.
/obj/item/laserdome_hyperball/proc/hyperball_pick_up(datum/act/op/A)
	var/mob/user = A.actor
	. = OP_OK
	pick_up_by_hand(user)
	var/mob/living/carbon/human/M = loc
	var/grabbing_team

	//if they're not a carbon, we don't care
	if(!istype(M))
		return

	//get their uniform
	if(istype(M.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/lasertag/redtag))
		grabbing_team = "red"
		icon_state = "[initial(icon_state)]_red"
		item_state = "[initial(icon_state)]_red"
	else if(istype(M.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/lasertag/bluetag))
		grabbing_team = "blue"
		icon_state = "[initial(icon_state)]_blue"
		item_state = "[initial(icon_state)]_blue"
	else
		return	//if they're not on a team, stop!

	act_message(user, src, others = span_warning("%U% has taken %T%!"))
	//cache our grabber and their team, for throw interactions with the goals later
	last_holder = M
	last_team = grabbing_team
	//finally, announcer calls out which team has the ball
	GLOB.global_announcer.autosay("[capitalize(grabbing_team)] team on offense!","Laserdome Announcer","Entertainment")
	update_held_icon()

/obj/structure/hyperball_pedestal
	name = "HYPERball pedestal"
	desc = "A fancy stand that the hyperball appears on. Looks strangely like one of the goals, come to think of it..."
	icon = 'icons/obj/flags.dmi'
	icon_state = "hyperball_stand"
	anchored = TRUE

//Finally, the goal objects. Like the flag bases, both goals *must* be in the same map area (e.g. /area/hyperball_arena) for the scoring system to work properly. But if they are, then it's basically just spawn-and-play, no other setup needed!
/obj/structure/hyperball_goal/get_mechanics_info(list/additional_information)
	return ..(list("A dunk scores more than a throw. A thrown ball may miss, or be intercepted by an enemy team member.") + additional_information)

/obj/structure/hyperball_goal
	name = "HYPERball goal"
	desc = "A dangerous-looking hole, with an energy net that stops anything but a hyperball from passing through."
	icon = 'icons/obj/flags.dmi'
	icon_state = "hyperball_goal"
	anchored = TRUE
	var/goal_team
	var/score = 0
	var/score_limit = 21	//3 hand-dunks (hard), or 7 throws (easy), or any combination thereof
	var/dunk_points = 7
	var/range_dunk_points = 3
	var/range_dunk_chance = 75	//chance for a ranged dunk to "hit" the goal

/obj/structure/hyperball_goal/blue
	name = "Blue team HYPERball goal"
	icon_state = "hyperball_goal_blue"
	goal_team = "blue"

/obj/structure/hyperball_goal/red
	name = "Red team HYPERball goal"
	icon_state = "hyperball_goal_red"
	goal_team = "red"

CAPABILITIES(/obj/structure/hyperball_goal)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/hyperball_goal/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/B = A.held
	var/mob/living/carbon/human/M = user
	var/dunking_team
	if(istype(M.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/lasertag/redtag))
		dunking_team = "red"
	else if(istype(M.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/lasertag/bluetag))
		dunking_team = "blue"
	else
		return OP_PASS

	if(istype(B,/obj/item/laserdome_hyperball))
		var/obj/item/laserdome_hyperball/ball = B
		if(dunking_team != goal_team)
			GLOB.global_announcer.autosay("[user] dunked the HYPERball for [capitalize(dunking_team)] team! [num2text(dunk_points)] points scored!","Laserdome Announcer","Entertainment")
			score += dunk_points	//increment our score!
			if(score < score_limit)	//announce the current score and how many more captures are needed
				GLOB.global_announcer.autosay("[num2text(score_limit-score)] points remain until [capitalize(dunking_team)] team wins.","Laserdome Announcer","Entertainment")
			else if(score >= score_limit)	//now, if score equals or exceeds (somehow) the score limit, announce that our team won and reset the score for all flag bases nearby
				GLOB.global_announcer.autosay("+|[uppertext(dunking_team)] TEAM HAS WON THE MATCH!|+","Laserdome Announcer","Entertainment")
				for(var/obj/structure/hyperball_goal/HB in contents_of(src.loc.loc))	//this feels dirty, but it works
					HB.score = 0
		else if(dunking_team == goal_team)	//discourage people from dunking the ball into their own goal as a quick way to teleport it back to the midfield
			switch(goal_team)	//this gets a bit fiddly because we store our score on the target's goal, so we need to scan the map for the opposing team's goal and deduct points from it
				if("blue")
					for(var/obj/structure/hyperball_goal/red/HGR in contents_of(src.loc.loc))
						HGR.score = max(0,HGR.score-dunk_points)
						GLOB.global_announcer.autosay("[user] dunked the HYPERball and scored an own goal! +Points |de-ducted!|+ [capitalize(goal_team)] team score is now: [HGR.score].","Laserdome Announcer","Entertainment")
				if("red")
					for(var/obj/structure/hyperball_goal/blue/HGB in contents_of(src.loc.loc))
						HGB.score = max(0,HGB.score-dunk_points)
						GLOB.global_announcer.autosay("[user] dunked the HYPERball and scored an own goal! +Points |de-ducted!|+ [capitalize(goal_team)] team score is now: [HGB.score].","Laserdome Announcer","Entertainment")

		user.drop_from_inventory(ball)
		ball.forceMove(ball.start_pos) //teleport the ball back to the midfield
		ball.icon_state = "[initial(ball.icon_state)]"
		ball.item_state = "[initial(ball.item_state)]"
	return OP_PASS

/obj/structure/hyperball_goal/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	. = ..()
	if(!istype(source, /obj/item/laserdome_hyperball))
		return

	var/obj/item/laserdome_hyperball/ball = source
	if(prob(range_dunk_chance))
		if(ball.last_team != goal_team)
			GLOB.global_announcer.autosay("[ball.last_holder] threw the HYPERball for [capitalize(ball.last_team)] team! [num2text(range_dunk_points)] points scored!","Laserdome Announcer","Entertainment")
			score += range_dunk_points	//increment our score!
			if(score < score_limit)	//announce the current score and how many more captures are needed
				GLOB.global_announcer.autosay("[num2text(score_limit-score)] points remain until [capitalize(ball.last_team)] team wins.","Laserdome Announcer","Entertainment")
			else if(score >= score_limit)	//now, if score equals or exceeds the score limit, announce that our team won and reset the score for all flag bases nearby
				GLOB.global_announcer.autosay("+|[uppertext(ball.last_team)] TEAM HAS WON THE MATCH!|+","Laserdome Announcer","Entertainment")
				for(var/obj/structure/hyperball_goal/HB in contents_of(src.loc.loc))	//this feels dirty, but it works
					HB.score = 0
		else if(ball.last_team == goal_team)	//discourage people from dunking the ball into their own goal as a quick way to teleport it back to the midfield
			switch(goal_team)	//this gets a bit fiddly because we store our score on the target's goal, so we need to scan the map for the opposing team's goal and deduct points from it
				if("blue")
					for(var/obj/structure/hyperball_goal/red/HGR in contents_of(src.loc.loc))
						HGR.score = max(0,HGR.score-range_dunk_points)
						GLOB.global_announcer.autosay("[ball.last_holder] threw the HYPERball and scored an own goal! +Points |de-ducted!|+ [capitalize(goal_team)] team score is now: [HGR.score].","Laserdome Announcer","Entertainment")
				if("red")
					for(var/obj/structure/hyperball_goal/blue/HGB in contents_of(src.loc.loc))
						HGB.score = max(0,HGB.score-range_dunk_points)
						GLOB.global_announcer.autosay("[ball.last_holder] threw the HYPERball and scored an own goal! +Points |de-ducted!|+ [capitalize(goal_team)] team score is now: [HGB.score].","Laserdome Announcer","Entertainment")

		ball.forceMove(ball.start_pos) //teleport the ball back to the midfield
		ball.icon_state = "[initial(ball.icon_state)]"
		ball.item_state = "[initial(ball.item_state)]"
	else
		//todo; throw the ball in a random direction
		src.visible_message("\The [ball] bounces off \the [src]'s rim!")
		GLOB.global_announcer.autosay("[ball.last_holder] threw the HYPERball and +missed!+ |Oooh!|","Laserdome Announcer","Entertainment")

/obj/structure/prop/machine/biosyphon/laserdome
	name = "Laserdome Orientation Holo"
	desc = {"This device is holoprojecting a wall of flickering text into the air. It seems to be incomprehensible gibberish at first, perhaps an alien language, but the longer you stare the more it starts to make sense, slowly coalescing into coherent sentences in your preferred language. The overall word choice is a little eclectic or unusual at times, and some words remain impossible for you to decipher, but you get the gist pretty quickly. It reads:<br>
	MANY GREETINGS, BRAVE VISITOR!
	THE (LIGHT AMPLIFIED BY STIMULATED EMISSION OF RADIATION) DOME IS FINEST PHYSICAL EXERCISE AND RECREATIONAL FACILITY LOCATED UPON THIS RELATIVE SIDE OF THE \[illegible\] SUPERMASSIVE OBSIDIAN VOID.
	OUR GREAT BRAINS HERE AT THE \[incomprehensible\] HAPPY FUN TIME CORPORATION ARE SURE YOU WILL DEFINITELY MUCH ENJOY PARTAKING IN THE SIGHTS AND SOUNDS OF OUR ESTABLISHMENT.
	EVEN IF YOU DO NOT WISH TO BE (OR ARE PHYSICALLY INCAPABLE OF) TAKING PART IN THE ACCELERATED LIGHT GAMES, PLEASE WITNESS OUR HEROIC GLADIATORS BATTLE FOR YOUR ENJOYMENT, AND VISIT LOCAL SERVICES SUCH AS THE \[incoherent\] ACCELERATED SUSTENANCE JOINT.
	PLEASE TO BE FOLLOWINGS FLOOR-BASED POINTED INDICATORS TOWARDS PLACEMENTS OF INTERESTING! AND BE SURE TO BE TAKINGS FREE RADIO HEADSET CHIP TO BE HEARING ARENA ANNOUNCER!
	THANKINGS YOU FOR YOUR PATRONAGE!!!
	NEWLY AVAILABLE IS FREE-FOR-ALL ARENA, REPLACING OLD BORING STARVIEW LOUNGINGS!
	(p.s. please to be cleanings up after selves, do not leave messes on concourse, thankings you again muchly)"}

/obj/structure/prop/machine/biosyphon/laserdome/hyperball
	name = "Laserdome HYPERball Orientation Holo"
	desc = {"This device is holoprojecting a wall of flickering text into the air. It seems to be incomprehensible gibberish at first, perhaps an alien language, but the longer you stare the more it starts to make sense, slowly coalescing into coherent sentences in your preferred language. The overall word choice is a little eclectic or unusual at times, and some words remain impossible for you to decipher, but you get the gist pretty quickly. It reads:<br>
	RULES OF HYPERBALL ARE SIMPLE!<br>
	TAKE BALL, SLAM-DUNKIFY INTO OPPOSING TEAM GOAL!
	THREE POINTS AWARD FOR THROW (BUT WATCH OUT, CAN MISS)!
	SEVEN POINTS IF ENDUNKENING IS BY HAND!
	POINTS AM DEDUCT IF OWN-DUNKING!
	FIRST TEAM TO TWENTY-AND-ONE POINTS IS WIN!
	MUST WEAR TEAM PLATINGS FOR SCORINGS TO COUNT!
	GOOD LUCK!!!"}

/obj/structure/prop/machine/biosyphon/laserdome/flagcap
	name = "Laserdome Capture-The-Flag Orientation Holo"
	desc = {"This device is holoprojecting a wall of flickering text into the air. It seems to be incomprehensible gibberish at first, perhaps an alien language, but the longer you stare the more it starts to make sense, slowly coalescing into coherent sentences in your preferred language. The overall word choice is a little eclectic or unusual at times, and some words remain impossible for you to decipher, but you get the gist pretty quickly. It reads:<br>
	RULES OF CAPTURING FLAG ARE SIMPLE!
	GO TO ENEMY BASE, TAKE THEIR FLAG, BRING BACK TO OWN BASE!
	NO SCORE IF ENEMY TEAM HAS FLAG, SO PROTECT OWN FLAG!
	RETURN OWN FLAG TO BASE BY TOUCHINGS!
	FIRST TEAM TO THREE CAPTURES IS WIN!
	MUST WEAR TEAM PLATINGS FOR SCORINGS TO COUNT!
	GOOD LUCK!!!"}

/obj/structure/prop/machine/biosyphon/laserdome/freeforall
	name = "Laserdome Free-For-All Orientation Holo"
	desc = {"This device is holoprojecting a wall of flickering text into the air. It seems to be incomprehensible gibberish at first, perhaps an alien language, but the longer you stare the more it starts to make sense, slowly coalescing into coherent sentences in your preferred language. The overall word choice is a little eclectic or unusual at times, and some words remain impossible for you to decipher, but you get the gist pretty quickly. It reads:<br>
	THIS ARENA IS FOR FREE-FOR-ALL AND TEAM-FOR-ALL MODES!
	PURPLED EQUIPMENT IS HAVING NO TEAM ALLEGIANCE!
	RECOMMENDED RULINGS AS FOLLOWS:
	LAST MAN STANDING: WHEN PLAYER HIT, PERMANENTLY ELIMINATED, RETURN TO SPAWN! LAST PLAYER \'ALIVE\' IS WINNING! IN TEAM MODE, LAST TEAM WITH LIVE PLAYERS IS WIN!
	FIRST TO SCORE: WHEN PLAYER HIT, RETURN TO SPAWN! FIRST PLAYER (OR TEAM) TO ELIMINATE AGREED NUMBER OF OTHERS IS WINNING!
	OR, PLAY HOWEVER MOST ENJOYED!
	GOOD LUCK!!!"}

/// Accessor for the target var.
/obj/structure/redgate/proc/target() as /obj/structure/redgate
	return target

CAPABILITIES(/obj/structure/redgate)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	op("hand", hand(), ungated(), then(PROC_REF(interaction_hand)))
	op("redgate_ghost_travel", observer(), label("Travel"), then(PROC_REF(redgate_ghost_travel)))
	links(/obj/structure/redgate::target, /obj/structure/redgate::target)
