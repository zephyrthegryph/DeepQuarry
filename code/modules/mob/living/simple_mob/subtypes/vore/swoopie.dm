/datum/category_item/catalogue/technology/drone/corrupt_hound/swoopie // Writing this so that they arnt corrupt hounds! -Reo
	name = "Drone - SWOOPIE XL"
	desc = "A large drone that typically wanders about maintenance or other places that are dirty, mindlessly sucking \
	up everything it deems to be debris, trash or a pest. \
	It looks like a blue and yellow long-necked bird with a large distinct black, plump belly and flexible neck that \
	bulges with every object it swoops. \
	They tend to run on extremely basic AI until proper ones are available to be downloaded from an external, \
	oddly spooky, provider. \
	<br><br>\
	The SWOOPIE's belly and neck are made of a synthetic rubber compound that is durable enough to allow them to pack \
	away even the most fiesty of pests once they make it past the synthbird's beak, and staring into that beak would allow \
	one to see far down into the drone, though the frequent curving of the SWOOPIE's neck often makes seeing down \
	the entire length next to impossible even with a cooperative unit, let alone the passive suction that threatens to \
	make anything that gets too close to the bot's beak vanish down the drone's stretchy hose throat. \
	SWOOPIE XLs are equipped with powerful CHURNO-VAC digestive chambers that are able to effectively melt down most \
	anything that gets claimed by their vac-beaks, indescriminately melting anything that happens to end up in that chamber, \
	it would be a terrible idea to allow yourself get swooped by one of these drones, unless you want to add to their biofuel reserves."
	value = CATALOGUER_REWARD_MEDIUM

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie
	name = "SWOOPIE XL"
	desc = "A large birdlike robot with thick assets, plump belly, and a long elastic vacuum hose of a neck. Somehow still a cleanbot, even if just for its duties."
	catalogue_data = list(/datum/category_item/catalogue/technology/drone/corrupt_hound/swoopie)
	icon_state = "swoopie"
	icon_living = "swoopie"
	icon_dead = "swoopie_dead"
	icon_rest = "swoopie_rest"
	icon = 'icons/mob/vore64x64.dmi'
	vis_height = 64
	has_eye_glow = TRUE
	custom_eye_color = "#00CC00"
	mount_offset_y = 30
	vore_capacity_ex = list("stomach" = 1, "neck1" = 1, "neck2" = 1, "neck3" = 1, "neck4" = 1)
	vore_fullness_ex = list("stomach" = 0, "neck1" = 0, "neck2" = 0, "neck3" = 0, "neck4" = 0)
	vore_icon_bellies = list("stomach", "neck1", "neck2", "neck3", "neck4")
	vore_icons = 0
	vore_pounce_chance = 100
	vore_pounce_maxhealth = 200
	has_hands = TRUE
	adminbus_trash = TRUE //You know what, sure whatever. It's not like anyone's gonna be taking this bird on unga trips to be their gamer backpack, which kinda was the main reason for the trash eater restrictions in the first place anyway.
	faction = "neutral"
	say_list_type = /datum/say_list/swoopie
	mob_bump_flag = 0
	player_msg = "You are a SWOOPIE XL cleaning bot! Use DISARM intent on yourself to change your integrated Vac-Pack settings, or GRAB intent to swoop stuff up! Turning off the Vac-Pack will make your grab clicks function as normal grab intent clicks."

	var/obj/item/vac_attachment/swoopie/Vac

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/Initialize(mapload)
	. = ..()
	if(!voremob_loaded)
		voremob_loaded = TRUE
		init_vore()
	if(istype(Vac))
		rel_set(Vac, nameof(Vac.output_dest), vore_selected)
		Vac.vac_power = 3
		rel_set(Vac, nameof(Vac.vac_owner), src)

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/IIsAlly(mob/living/L)
	. = ..()
	if(L && has_trait(L, TRAIT_AMBIENT_PEST_MOB)) // If they're a pest, swoop no matter what!
		return FALSE

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/attack_target(atom/A)
	if(!(ai_brain != null))
		return ..()
	if(istype(A, /mob/living)) //Swoopie gonn swoop
		var/mob/living/M = A //typecast
		if(can_spontaneous_vore(src, A))
			return ..()
		Vac.afterattack(M, src, 1)
		return
	if(istype(A, /obj/item))
		Vac.afterattack(A, src, 1)
		return
	. = ..() //if not vaccable, just do what it normally does

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/load_default_bellies()
	grant(src, granted_verb(/mob/living/proc/restrict_trasheater), src)
	var/obj/belly/B = new /obj/belly(src)
	B.affects_vore_sprites = TRUE
	B.belly_sprite_to_affect = "stomach"
	B.name = "Churno-Vac"
	B.desc = "With an abrupt loud WHUMP after a very sucky trip through the hungry bot's vacuum tube, you finally spill out into its waste container, where everything the bot slurps off the floors ends up for swift processing among the caustic sludge, efficiently melting everything down into a thin slurry to fuel its form. More loose dirt and debris occasionally raining in from above as the bot carries on with its duties to keep the station nice and clean."
	B.digest_messages_prey = list("Under the heat and internal pressure of the greedy machine's gutworks, you can feel the tides of the hot caustic sludge claiming the last bits of space around your body, a few more squeezes of the synthetic muscles squelching and glurking as your body finally loses its form, completely blending down and merging into the tingly sludge to fuel the mean machine.")
	B.digest_mode = DM_DIGEST
	B.item_digest_mode = IM_DIGEST
	B.recycling = TRUE
	B.mode_flags = DM_FLAG_THICKBELLY //Hard to be heard from inside the swoop!
	B.digest_burn = 3
	B.fancy_vore = 1
	B.vore_sound = "Stomach Move"
	B.belly_fullscreen = "VBOanim_belly9"
	B.belly_fullscreen_color = "#202020"
	B.sound_volume = 25
	B.count_items_for_sprite = TRUE
	B.show_liquids = TRUE
	B.reagentbellymode = TRUE
	B.reagent_mode_flags = DM_FLAG_REAGENTSDIGEST
	B.reagentid = "biomass"
	B.reagent_chosen = "Biomass"
	B.reagent_name = "caustic trash-sludge"
	B.custom_reagentcolor = "#3c3030"
	B.reagent_touches = FALSE

	B = new /obj/belly/longneck(src)
	B.affects_vore_sprites = FALSE
	B.name = "Vac-Beak"
	B.desc = "SNAP! You have been sucked up into the big synthbird's beak, the powerful vacuum within the bird roaring somewhere beyond the abyssal deep gullet hungrily gaping before you, eagerly sucking you deeper inside towards a long bulgy ride down the bird's vacuum hose of a neck!"
	B.entrance_logs = TRUE //Exept for the maw. I think that's reasonable. -Reo
	B.autotransferlocation = "vacuum hose"
	B.autotransfer_max_amount = 0
	B.autotransferwait = 60
	B.belly_fullscreen_color2 = "#1C1C1C"
	B.belly_fullscreen_color3 = "#292929"
	B.belly_fullscreen_color4 = "#CCFFFF"
	B.belly_fullscreen = "VBO_maw25" //Swoopies have beaks!!

	rel_set(src, nameof(vore_selected), B)

	B = new /obj/belly/longneck(src)
	B.affects_vore_sprites = TRUE
	B.belly_sprite_to_affect = "neck1"
	B.name = "vacuum hose"
	B.autotransferlocation = "upper vacuum hose"
	B.fancy_vore = 1
	B.vore_sound = "Stomach Move"
	B.sound_volume = 100

	B = new /obj/belly/longneck(src)
	B.affects_vore_sprites = TRUE
	B.belly_sprite_to_affect = "neck2"
	B.name = "upper vacuum hose"
	B.autotransferlocation = "midway vacuum hose"
	B.desc = "It feels very tight in here..."
	B.fancy_vore = 1
	B.vore_sound = "Stomach Move"
	B.sound_volume = 80

	B = new /obj/belly/longneck(src)
	B.affects_vore_sprites = TRUE
	B.belly_sprite_to_affect = "neck3"
	B.name = "midway vacuum hose"
	B.autotransferlocation = "lower vacuum hose"
	B.desc = "Looks like it's gonna be all downhill from here..."
	B.fancy_vore = 1
	B.vore_sound = "Stomach Move"
	B.sound_volume = 40

	B = new /obj/belly/longneck(src)
	B.affects_vore_sprites = TRUE
	B.belly_sprite_to_affect = "neck4"
	B.name = "lower vacuum hose"
	B.autotransferlocation = "Churno-Vac"
	B.desc = "Thank you for your biofuel contribution~"
	B.fancy_vore = 1
	B.vore_sound = "Stomach Move"
	B.sound_volume = 20

/obj/belly/longneck
	affects_vore_sprites = TRUE
	belly_sprite_to_affect = "neck1"
	name = "vacuum hose"
	desc = "With a mighty WHUMP, the suction of the big bird's ravenous vacuum system has sucked you up out of the embrace of its voracious main beak and into a tight bulge squeezing along the long ribbed rubbery tube leading towards the roaring doom of the synthetic bird's efficient waste disposal system."
	digest_mode = DM_HOLD
	item_digest_mode = IM_HOLD
	contaminates = FALSE //Stuff doesnt get messy in the throat, the bird's gut is the messy place!
	entrance_logs = FALSE //QOL to stop spam when stuff is getting gulped down~
	autotransfer_enabled = TRUE
	autotransferchance = 100
	autotransferwait = 60
	autotransferlocation = "Churno-Vac"
	vore_verb = "suck"
	belly_fullscreen_color = "#4d4d4d"
	belly_fullscreen = "VBOanim_gullet1"
	human_prey_swallow_time = 1
	nonhuman_prey_swallow_time = 1
	autotransfer_max_amount = 2
	count_items_for_sprite = TRUE
	item_multiplier = 10
	health_impacts_size = FALSE
	mode_flags = DM_FLAG_TURBOMODE

	size_factor_for_sprite = 5

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/life_type_post_due()
	return TRUE

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/life_type_post(datum/seq_frame/life/F)
	..()
	var/turf/T = get_turf(src)
	if(istype(src.Vac))
		if(src.Vac.loc != src)
			var/turf/VT = get_turf(src.Vac)
			if(!T.Adjacent(VT) || isturf(src.Vac.loc))
				if(isliving(src.Vac.loc))
					var/mob/living/L = src.Vac.loc
					L.remove_from_mob(src.Vac, src)
				else
					src.Vac.forceMove(src)
		var/atom/movable/vac_output = src.Vac.output_dest
		if(!vac_output)
			if(isbelly(src.vore_selected))
				rel_set(src.Vac, nameof(/obj/item/vac_attachment::output_dest), src.vore_selected)
	if(!istype(T) || !istype(src.Vac) || !(src.ai_brain != null) || src.Vac.loc != src || src.stat)
		return
	if(istype(T, /turf/simulated))
		var/turf/simulated/S = T
		if(S.dirt > 50)
			src.Vac.afterattack(S, src, 1)
			return
	for(var/obj/O in turf_contents_of_type(T, /obj))
		if(is_type_in_list(O, GLOB.edible_trash) && !O.anchored)
			src.Vac.afterattack(T, src, 1)
			return
	for(var/mob/living/L in turf_contents_of_type(T, /mob/living))
		if(!L.anchored && L.devourable && L != src && !L?.buckled_to() && L.can_be_drop_prey)
			src.Vac.afterattack(L, src, 1)
			return

/datum/say_list/swoopie
	speak = list("Scanning for debris...", "Scanning for dirt...", "Scanning for pests...", "Squawk!")
	emote_hear = list("squawks!", "whirrs idly.", "revs up its vacuum.")
	emote_see = list("twitches.", "sways.", "stretches its neck.", "stomps idly.")
	say_maybe_target = list("Pest detected?")
	say_got_target = list("PEST DETECTED!")

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/intercept_use(atom/A, params, stance = I_HURT)
	if(stat) //Cant suck if we're not able to...
		return FALSE
	if(istype(A, /obj/item/storage)) //Dont put the nossle in bags
		return FALSE
	if(istype(Vac) && A.Adjacent(src))
		face_atom(A)
		if(stance == I_DISARM && A == src) //Only if on disarm intent.
			Vac.attack_self(src)
			return TRUE
		if(stance == I_GRAB && Vac.vac_power != 0) //Only on grab intent. if someone needs to use grab intent they can just turn off the vac
			if(istype(A, /obj/machinery/disposal)) //You used that bin when the bird was right there? How inconsiderate!
				var/obj/machinery/disposal/D = A
				if(D.flushing)
					to_chat(src, "\The [D] has already began flushing, you're too late to grab whatever was inside!")
					return TRUE
				var/foundstuff = 0 //Check if we actually found anything in the bin...
				D.latent_materialize_all() // a walk needs real things (C5)
				for(var/atom/movable/AM in D) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
					if(istype(AM, /mob/living))
						var/mob/living/M = AM
						if(!can_spontaneous_vore(src, M))
							to_chat(M, span_warning("[src] plunges their head into \the [D], while you narrowly avoid being sucked up!"))
							continue
						to_chat(M, span_warning("[src] plunges their head into \the [D], sucking up everything inside- Including you!"))
					foundstuff = 1
					AM.forceMove(src)
				if(foundstuff)
					act_message(src, null, null, MSG_OTHERS(span_warning("%U% plunges their head into \the [D], greedily sucking up everything inside!")))
				else //Oh, Nothing was inside...
					to_chat(src, span_infoplain("You poke your head into \the [D], but there doesnt seem to be anything of interest..."))
				return TRUE
			var/resolved = Vac.resolve_attackby(A, src, click_parameters = params)
			if(!resolved && A && Vac)
				Vac.afterattack(A, src, 1, params, stance)
				return TRUE
	return FALSE

EXTEND_INTERACTIONS(/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie, INTERACT_HAND_UNGATED_AS(I_DISARM, "Toggle Vac-Pack", PROC_REF(swoopie_interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_GRAB, "Take Vac-Pack", PROC_REF(swoopie_interaction_hand)))

/// Old attack_hand: disarm toggles the Vac-Pack, a head grab takes it; otherwise the normal touch.
/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/proc/swoopie_interaction_hand(mob/living/L, obj/item/held, datum/interaction/interaction)
	if(stat) //Make sure we're alive
		return FALSE
	if(interaction.stance == I_DISARM && Vac)
		Vac.attack_self(L)
		return TRUE
	if(interaction.stance == I_GRAB && Vac && Vac.loc == src)
		if(L.zone_sel.selecting == BP_HEAD)
			if(L.put_in_active_hand(Vac))
				act_message(L, src, null, MSG_OTHERS(span_warning("%U% grabs %T% by the neck, brandishing the thing like a regular vacuum cleaner!")))
				L.start_pulling(src)
				return TRUE
	return FALSE

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/verb/borrow_vac()
	set name = "Borrow Vac-Pack"
	set desc = "Allows adjacent user to borrow Swoopie's Vac-Pack"
	set category = VERB_CAT_OBJECT
	set src in oview(1)
	if(istype(Vac))
		if(usr != src)
			usr.put_in_active_hand(Vac)
		else
			open_request(src, /datum/prompt/choice, PROC_REF(vac_borrower_chosen), answerer = src, title = "Swoopie", question = "Borrow Vac-Pack for", choices = mobs_in_view(1, src), timeout = 0)

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/proc/vac_borrower_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/L = A.answer.value
	if(L == src || !istype(Vac) || !Adjacent(L))
		return
	L.put_in_active_hand(Vac)

// DQEdit - change_settings verb body moved to
// modular_dq/.../ports/swoopie.dm where it toggles mob-side swoop_pests /
// swoop_trash vars (the legacy AI subtype is gone).


/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/Login()
	. = ..()
	om_grant(src, GRANT_VERB_HIDE, /mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/verb/change_settings, src) //Controlled swoopies dont need their settings changed externally

//Special Swoopie vaccum so it can be handled better than a vareditted vacpack.
/obj/item/vac_attachment/swoopie
	name = "Swoopie Vac-Beak"
	desc = "Useful for slurping mess off the floors. Even dirt and pests depending on settings. This vaccum seems to be permanantly attached to the swoopie's rumbling rubber trashbag."
	icon = 'icons/mob/vacpack_swoop.dmi'
	item_state = null

/obj/item/vac_attachment/swoopie/dropped(mob/user, equipping, slot) //This should fix it sitting on the ground until the next life() tick
	. = ..()
	if(!vac_owner)
		return
	forceMove(vac_owner)

//Custom Swoopie AI to make it swoop up trash when asked to
// Select an obj if no mobs are around.


CAPABILITIES(/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie)
	owns_one(nameof(Vac), starts = /obj/item/vac_attachment/swoopie)

