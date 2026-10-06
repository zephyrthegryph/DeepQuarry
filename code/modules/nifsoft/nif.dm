/* //////////////////////////////
The NIF has a proc API shared with NIFSofts, and you should not really ever
directly interact with this API. Procs like install(), uninstall(), etc should
not be directly called. If you want to install a new NIFSoft, pass the NIF in
the constructor for a new instance of the NIFSoft. If you want to force a NIFSoft
to be uninstalled, use imp_check to get a reference to it, and call
uninstall() only on the return value of that.

You can also set the stat of a NIF to NIF_TEMPFAIL without any issues to disable it.
*/ //////////////////////////////

//Holder on humans to prevent having to 'find' it every time
/mob/living/carbon/human/var/obj/item/nif/nif

//Nanotech Implant Foundation
/obj/item/nif
	name = "nanite implant framework"
	desc = "A mass-production model of a nano working surface, in a box. Can print new \
	implants inside living hosts on the fly based on software uploads. Must be surgically \
	implanted in the head to work, and requires periodical maintenance. Warning: this device \
	is extremely sensitive to electromagnetic pulse waves."

	icon = 'icons/obj/device_alt.dmi'
	icon_state = "nif_0"
	unacidable = TRUE

	w_class = ITEMSIZE_TINY
	var/known_implant = TRUE

	var/durability = 100					// Durability remaining
	var/bioadap = FALSE						// If it'll work in fancy species
	var/gib_nodrop = FALSE					// NIF self-destructs when owner is gibbed

	var/tmp/power_usage = 0						// Nifsoft adds to this
	var/tmp/mob/living/carbon/human/human		// Our owner!
	// ALLOW(instance_list): d: fixed-slot software table indexed by list_pos
	var/tmp/list/nifsofts[TOTAL_NIF_SOFTWARE]	// All our nifsofts
	var/tmp/list/nifsofts_life			// Ones that want to be talked to on life()
	var/owner									// Owner character name
	var/owner_key								// Account associated with the nif
	var/examine_msg								//Message shown on examine.

	var/tmp/vision_flags = 0		// Flags implants set for faster lookups
	var/tmp/health_flags = 0
	var/tmp/combat_flags = 0
	var/tmp/other_flags = 0

	var/tmp/stat = NIF_PREINSTALL		// Status of the NIF
	EXPIRY_TMP_DECLARE(install_done) // Time when install will finish
	var/tmp/open = FALSE				// If it's open for maintenance (1-3)
	var/tmp/should_be_in = BP_HEAD		// Organ we're supposed to be held in

	var/obj/item/communicator/commlink/comm		// The commlink requires this

	var/list/starting_software = list( // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
		/datum/nifsoft/commlink,
		/datum/nifsoft/soulcatcher,
		/datum/nifsoft/ar_civ
	)

	var/global/icon/big_icon
	var/global/click_sound = 'sound/items/nif_click.ogg'
	var/global/bad_sound = 'sound/items/nif_tone_bad.ogg'
	var/global/good_sound = 'sound/items/nif_tone_good.ogg'

	var/list/save_data

	var/list/planes_visible

/// The wear and the saved data a NIF is made with (its constructor params).
/obj/item/nif/var/tmp/wear_at_make
/obj/item/nif/var/tmp/list/load_data_at_make

//Constructor comes with a free AR HUD
// ALLOW(init/INSTANCE_STATE): a NIF loads its saved data, implants into the human it is made in and takes its starting wear
/obj/item/nif/Initialize(mapload)
	. = ..()

	//First one to spawn in the game, make a big icon
	if(!big_icon)
		big_icon = new(icon,icon_state = "nif_full")

	//Put loaded data here if we loaded any
	save_data = islist(load_data_at_make) ? load_data_at_make.Copy() : list()
	var/saved_examine_msg = save_data["examine_msg"]

	//If it's an empty string, they want it blank. If null, it's never been saved, give default.
	if(isnull(saved_examine_msg))
		saved_examine_msg = "There's a certain spark to their eyes."
	examine_msg = saved_examine_msg

	//If given a human on spawn (probably from persistence)
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		if(!quick_implant(H)) //This calls register_human() later down the line.
			WARNING("NIF spawned in [H] failed to implant")
			return INITIALIZE_HINT_QDEL

	//If given wear (like when spawned) then done
	if(wear_at_make)
		durability = wear_at_make
		wear(0) //Just make it update.

	//Draw me yo.
	update_icon()

/obj/item/nif/proc/register_human()
	observe(human, /datum/notice/mob_death, src, then(PROC_REF(on_human_death)))

/obj/item/nif/proc/unregister_human()
	if(!human)
		return
	unobserve(human, /datum/notice/mob_death, src)
	rel_clear(src, nameof(human)) // the pair clears human.nif too

/// Saves the NIF's data when the implanted human dies. The save does savefile I/O, so it
/// runs right after the event instead of inside it (handlers must not sleep).
/obj/item/nif/proc/on_human_death(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/carbon/human/source = A.target
	after(src, 0, PROC_REF(persist_on_death), with = list(source))

/obj/item/nif/proc/persist_on_death(mob/living/carbon/human/source)
	if(!QDELETED(source))
		persist_nif_data(source)

//Destructor cleans up references

// the NIF unregisters from its human.
/obj/item/nif/on_destroy(force)
	unregister_human()
	..()

//Being implanted in some mob
/obj/item/nif/proc/implant(mob/living/carbon/human/H)
	var/obj/item/organ/brain = H.organ_in(O_BRAIN)
	if(istype(brain))
		should_be_in = brain.parent_organ

	if(istype(H) && !H.nif && H.species && (loc == H.get_organ(should_be_in)))
		if(!bioadap && (H.species.flags & NO_DNA)) //NO_DNA is the default 'too complicated' flag
			return FALSE

		rel_set(src, nameof(human), H) // the pair sets H.nif too
		stat = NIF_INSTALLING
		grant(H, granted_verb(/mob/living/carbon/human/proc/set_nif_examine), src)
		rel_set(src, nameof(menu_ref), new /datum/nif_menu(H))
		if(starting_software)
			for(var/path in starting_software)
				new path(src)
			starting_software = null
		register_human()
		return TRUE

	return FALSE

//For debug or antag purposes
/obj/item/nif/proc/quick_implant(mob/living/carbon/human/H)
	if(istype(H))
		var/obj/item/organ/external/parent
		//Try to find their brain and put it near that
		var/obj/item/organ/brain = H.organ_in(O_BRAIN)
		if(istype(brain))
			should_be_in = brain.parent_organ

		parent = H.get_organ(should_be_in)
		//Ok, nevermind then!
		if(!istype(parent))
			return FALSE
		forceMove(parent)
		rel_add(parent, nameof(parent.implants), src)
		after(src, 0.1 SECONDS, PROC_REF(quick_install), with = list(H))
		return TRUE

	return FALSE

/obj/item/nif/proc/quick_install(mob/living/carbon/human/H)
	if(QDELETED(H)) //Or letting them get deleted
		return
	if(H.mind)
		owner = H.mind.name
		owner_key = H.ckey
	implant(H)

//Being removed from some mob
/obj/item/nif/proc/unimplant(mob/living/carbon/human/H)
	var/datum/nifsoft/soulcatcher/SC = imp_check(NIF_SOULCATCHER)
	if(SC) //Clean up stored people, this is dirty but the easiest way.
		own_clear(SC, nameof(SC.brainmobs), OWN_DELETE)
	stat = NIF_PREINSTALL
	vis_update()
	if(H)
		revoke(H, granted_verb(/mob/living/carbon/human/proc/set_nif_examine), src)
	own_clear(src, nameof(menu_ref), OWN_DELETE)
	unregister_human()
	install_done = null
	update_icon()

//Wear update/check proc
/obj/item/nif/proc/wear(wear = 0)
	wear *= (rand(85,115) / 100) //Apparently rand() only takes integers.
	durability -= wear

	if(human)
		persist_nif_data(human)

	if(durability <= 0)
		durability = 0	//failsafe us to a minimum of 0% so we don't just wash into massively negative durability from repeated EMPs
		stat = NIF_TEMPFAIL
		update_icon()

		if(human)
			notify("Danger! General system insta#^!($",TRUE)
			to_chat(human,span_danger("Your NIF vision overlays disappear and your head suddenly seems very quiet..."))

//Repair update/check proc
/obj/item/nif/proc/repair(repair = 0)
	durability = min(durability + repair, initial(durability))

	if(human)
		persist_nif_data(human)

//Attackby proc, for maintenance
DECLARE_INTERACTIONS(/obj/item/nif, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/nif/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(open == 1 && istype(W,/obj/item/stack/cable_coil))
		var/obj/item/stack/cable_coil/C = W
		if(C.get_amount() < 3)
			to_chat(user,span_warning("You need at least three coils of wire to add them to \the [src]."))
			return INTERACTION_HANDLED_PASS
		if(durability >= initial(durability))
			to_chat(user,span_notice("There's no damaged wiring that needs replacing!"))
			open = 3
			update_icon()
			return INTERACTION_HANDLED_PASS
		om_task_timed(user, 6 SECONDS, src, src, PROC_REF(rewire_done), list(user, C))
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/item/nif/proc/rewire_done(mob/user, obj/item/stack/cable_coil/C)
	if(open == 1 && C.use(3))
		act_message(user, src, MSG_SELF(span_notice("You replace any burned out wiring in %T%.")), MSG_OTHERS("%U% replaces some wiring in %T%."))
		play_sfx(src, SFX_ITEMS_DECONSTRUCT)
		open = 2
		update_icon()

/obj/item/nif/proc/pry_open_done(mob/user, obj/item/tool)
	if(open != 0)
		return
	act_message(user, src, MSG_SELF(span_notice("You unscrew and pry open %T%.")), MSG_OTHERS("%U% unscrews and pries open %T%."))
	playsound(src, tool.usesound, 50, 1)
	open = 1
	update_icon()

/obj/item/nif/proc/reseal_done(mob/user, obj/item/tool)
	if(open != 3)
		return
	act_message(user, src, MSG_SELF(span_notice("You re-seal %T% for use once more.")), MSG_OTHERS("%U% closes up %T%."))
	playsound(src, tool.usesound, 50, 1)
	open = FALSE
	repair(initial(durability))
	stat = NIF_PREINSTALL
	update_icon()

/obj/item/nif/proc/reset_circuits_done(mob/user)
	if(open != 2)
		return
	act_message(user, src, MSG_SELF(span_notice("You find and repair any faulty circuits in %T%.")), MSG_OTHERS("%U% resets several circuits in %T%."))
	open = 3
	update_icon()

/obj/item/nif/screwdriver_act(mob/user, obj/item/tool)
	if(open == 0)
		om_task_timed(user, 4 SECONDS, src, src, PROC_REF(pry_open_done), list(user, tool))
		return ITEM_INTERACT_SUCCESS
	if(open == 3)
		om_task_timed(user, 3 SECONDS, src, src, PROC_REF(reseal_done), list(user, tool))
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

/obj/item/nif/multitool_act(mob/user, obj/item/tool)
	if(open != 2)
		return ITEM_INTERACT_BLOCKING
	om_task_timed(user, 8 SECONDS, src, src, PROC_REF(reset_circuits_done), list(user))
	return ITEM_INTERACT_SUCCESS

//Icon updating
/// Appearance reader: the icon_state suffix for the open panel or install state.
/obj/item/nif/proc/appearance_nif_state()
	if(open)
		return "open[open]"
	switch(stat)
		if(NIF_PREINSTALL)
			return "1"
		if(NIF_INSTALLING, NIF_WORKING)
			return "0"
	return "2"

APPEARANCE_TEMPLATE(/obj/item/nif, "nif_{appearance_nif_state}")

//The (dramatic) install process
/obj/item/nif/proc/handle_install()
	if(human.stat || !human.mind) //No stuff while KO or not sleeved
		return FALSE
	persist_storable = FALSE // I am not sure if polaris has nifs, but just in case.
	//Firsties
	if(!install_done)
		if(human.mind.name == owner)
			owner_key = human.ckey
			EXPIRY_SET(src, install_done, 1 MINUTE, CLOCK_WORLD)
			notify("Welcome back, [owner]! Performing quick-calibration...")
		else if(!owner)
			EXPIRY_SET(src, install_done, 15 MINUTES, CLOCK_WORLD) // Install time from 35 minutes to 15 minutes.
			owner_key = human.ckey
			notify("Adapting to new user...")
			after(src, 5 SECONDS, PROC_REF(notify), with = list("Adjoining optic [HAS_SYNTHETIC_BIOLOGY(human) ? "interface" : "nerve"], please be patient.", TRUE))
		else
			notify("You are not an authorized user for this device. Please contact [owner].",TRUE)
			unimplant(human)
			stat = NIF_TEMPFAIL
			return FALSE

	var/percent_done = (world.time - (install_done - (15 MINUTES))) / (15 MINUTES) // 35 minutes down to 15 minutes.

	human.claim_global_hud(GLOB.global_hud.whitense) //This is the camera static

	switch(percent_done) //This is 0.0 to 1.0 kinda percent.
		//Connecting to optical nerves
		if(0.0 to 0.1)
			human.status_set(STAT_BLINDED, 5)

		//Mapping brain
		if(0.2 to 0.9)
			if(prob(98)) return TRUE
			var/incident = rand(1,3)
			switch(incident)
				if(1)
					var/message = pick(list(
								"Your head throbs around your new implant!",
								"The skin around your recent surgery itches!",
								"A wave of nausea overtakes you as the world seems to spin!",
								"The floor suddenly seems to come up at you!",
								"There's a throbbing lump of ice behind your eyes!",
								"A wave of pain shoots down your neck!"
								))
					human.injure(INJURY_PAIN, 35)
					human.custom_pain(message,35)
				if(2)
					human.status_at_least(STAT_WEAKENED, 5)
					to_chat(human,span_danger("A wave of weakness rolls over you."))
				/*if(3)
					human.status_at_least(STAT_SLEEPING, 5) //Disabled for being boring
					to_chat(human,span_danger("You suddenly black out!"))*/

		//Finishing up
		if(1.0 to INFINITY)
			stat = NIF_WORKING
			owner = human.mind.name
			name = initial(name) + " ([owner])"
			if(comm)
				var/saved_name = save_data["commlink_name"]
				if(saved_name)
					comm.register_device(saved_name)
				else if(human)
					comm.register_device(human.name)
			notify("Calibration complete! User data stored!")

//Called each life() tick on the mob
/obj/item/nif/proc/life()
	if(!human || loc != human.get_organ(should_be_in))
		unimplant(human)
		return FALSE

	switch(stat)
		if(NIF_WORKING)
			//Perform our passive drain
			if(!use_charge(power_usage))
				stat = NIF_POWFAIL
				vis_update()
				notify("Insufficient energy!",TRUE)
				return FALSE

			//HUD update!
			//nif_hud.process_hud(human,1) //TODO VIS

			//Process all the ones that want that
			for(var/datum/nifsoft/nifsoft as anything in nifsofts_life)
				nifsoft.life(human)

		if(NIF_POWFAIL)
			if(human && human.nutrition < 100)
				return FALSE
			else
				stat = NIF_WORKING
				vis_update()
				notify("System Reboot Complete.")

		if(NIF_TEMPFAIL)
			//Something else has to take us out of tempfail
			return FALSE

		if(NIF_INSTALLING)
			handle_install()
			return FALSE

//Prints 'AR' messages to the user
/obj/item/nif/proc/notify(message,alert = 0)
	if(!human || stat == NIF_TEMPFAIL) return

	last_notification = message // TGUI Hook

	to_chat(human,span_filter_nif(span_bold("\[[icon2html(src.big_icon, human.client)]NIF\]") + " displays, " + (alert ? span_danger(message) : span_notice(message))))
	if(prob(1)) act_message(human, null, others = span_notice("%U% [pick(GLOB.nif_look_messages)]."))
	if(alert)
		human << bad_sound
	else
		human << good_sound

//Called to spend nutrition, returns 1 if it was able to
/obj/item/nif/proc/use_charge(use_charge)
	if(stat != NIF_WORKING) return FALSE

	//You don't want us to take any? Well okay.
	if(!use_charge)
		return TRUE

	//Not enough nutrition/charge left.
	if(!human || human.nutrition < use_charge)
		return FALSE

	//Was enough, reduce and return.
	human.adjust_nutrition(-use_charge)
	return TRUE

// This operates on a nifsoft *path*, not an instantiation.
// It tells the nifsoft shop if it's installation will succeed, to prevent it
// from charging the user for incompatible software.
MSG_DEF_SELF(nif/tempfail, "Your NIF is not working.")
MSG_DEF_SELF(nif/already_installed, "That software is already installed in your NIF.")
MSG_DEF_SELF(nif/not_for_chassis, "That software is not supported on your chassis type.")
MSG_DEF_SELF(nif/not_for_organics, "That software is not supported in organic life.")

/// Why the NIF cannot take the software (a /datum/msg type), or null. Reads only: a shop asks it before it sells.
/obj/item/nif/proc/install_refusal(datum/nifsoft/path)
	if(stat == NIF_TEMPFAIL) // ALLOW(reads): a NIF's state and software are asked when the software is chosen, never cached
		return /datum/msg/nif/tempfail
	if(nifsofts[initial(path.list_pos)])
		return /datum/msg/nif/already_installed
	if(human)
		var/applies_to = initial(path.applies_to)
		var/synth = HAS_SYNTHETIC_BIOLOGY(human)
		if(synth && !(applies_to & NIF_SYNTHETIC))
			return /datum/msg/nif/not_for_chassis
		if(!synth && !(applies_to & NIF_ORGANIC))
			return /datum/msg/nif/not_for_organics
	return null

/obj/item/nif/proc/can_install(datum/nifsoft/path)
	if(stat == NIF_TEMPFAIL)
		return FALSE

	if(nifsofts[initial(path.list_pos)])
		notify("The software \"[initial(path.name)]\" is already installed.", TRUE)
		return FALSE

	if(human)
		var/applies_to = initial(path.applies_to)
		var/synth = HAS_SYNTHETIC_BIOLOGY(human)
		if(synth && !(applies_to & NIF_SYNTHETIC))
			notify("The software \"[initial(path.name)]\" is not supported on your chassis type.",TRUE)
			return FALSE
		if(!synth && !(applies_to & NIF_ORGANIC))
			notify("The software \"[initial(path.name)]\" is not supported in organic life.",TRUE)
			return FALSE

	return TRUE

//Install a piece of software
/obj/item/nif/proc/install(datum/nifsoft/new_soft)
	if(stat == NIF_TEMPFAIL) return FALSE

	if(nifsofts[new_soft.list_pos])
		return FALSE

	if(human)
		var/applies_to = new_soft.applies_to
		var/synth = HAS_SYNTHETIC_BIOLOGY(human)
		if(synth && !(applies_to & NIF_SYNTHETIC))
			notify("The software \"[new_soft]\" is not supported on your chassis type.",TRUE)
			return FALSE
		if(!synth && !(applies_to & NIF_ORGANIC))
			notify("The software \"[new_soft]\" is not supported in organic life.",TRUE)
			return FALSE

	wear(new_soft.wear)
	rel_add(src, nameof(nifsofts), new_soft, new_soft.list_pos)
	power_usage += new_soft.p_drain

	if(new_soft.tick_flags == NIF_ALWAYSTICK)
		rel_add(src, nameof(nifsofts_life), new_soft)

	return TRUE

//Uninstall a piece of software
/obj/item/nif/proc/uninstall(datum/nifsoft/old_soft)
	var/datum/nifsoft/NS
	if(nifsofts && old_soft.list_pos >= 1 && old_soft.list_pos <= length(nifsofts))
		NS = nifsofts[old_soft.list_pos]

	if(!NS || NS != old_soft)
		return FALSE //what??

	if(!NS.can_uninstall)
		notify("The software \"[NS]\" refuses to be uninstalled.",TRUE)
		return FALSE

	// Detach it from its slot (the list shifts), then pad the slot back: nifsofts is a
	// positional table indexed by list_pos.
	var/slot = old_soft.list_pos
	own_take_member(src, nameof(nifsofts), old_soft)
	if(!nifsofts)
		nifsofts = new /list(TOTAL_NIF_SOFTWARE) // ALLOW(ownership): a fresh positional slot table (nulls only)
	else if(length(nifsofts) < TOTAL_NIF_SOFTWARE)
		nifsofts.Insert(slot, null) // ALLOW(ownership): an empty slot (null), keeping every other soft at its list_pos
	power_usage -= old_soft.p_drain

	if(old_soft.tick_flags == NIF_ALWAYSTICK)
		rel_remove(src, nameof(nifsofts_life), old_soft)

	if(old_soft.active)
		old_soft.deactivate(force = TRUE)

	return TRUE

//Activate a nifsoft
/obj/item/nif/proc/activate(datum/nifsoft/soft)
	if(stat != NIF_WORKING) return FALSE

	if(human)
		if(prob(5)) act_message(human, null, others = span_notice("%U% [pick(GLOB.nif_look_messages)]."))
		var/applies_to = soft.applies_to
		var/synth = HAS_SYNTHETIC_BIOLOGY(human)
		if(synth && !(applies_to & NIF_SYNTHETIC))
			notify("The software \"[soft]\" is not supported on your chassis type and will be uninstalled.",TRUE)
			uninstall(soft)
			return FALSE
		if(!synth && !(applies_to & NIF_ORGANIC))
			notify("The software \"[soft]\" is not supported in organic life and will be uninstalled.",TRUE)
			uninstall(soft)
			return FALSE
		human << click_sound

	if(!use_charge(soft.a_drain))
		notify("Not enough power to activate \"[soft]\" NIFsoft!",TRUE)
		return FALSE

	if(soft.tick_flags == NIF_ACTIVETICK)
		rel_add(src, nameof(nifsofts_life), soft)

	power_usage += soft.a_drain

	return TRUE

//Deactivate a nifsoft
/obj/item/nif/proc/deactivate(datum/nifsoft/soft)
	if(human)
		if(prob(5)) act_message(human, null, others = span_notice("%U% [pick(GLOB.nif_look_messages)]."))
		human << click_sound

	if(soft.tick_flags == NIF_ACTIVETICK)
		rel_remove(src, nameof(nifsofts_life), soft)

	power_usage -= soft.a_drain

	return TRUE

//Deactivate several nifsofts
/obj/item/nif/proc/deactivate_these(list/turn_off)
	for(var/N in turn_off)
		var/datum/nifsoft/NS = nifsofts[N]
		if(NS)
			NS.deactivate()

//Add a flag to one of the holders
/obj/item/nif/proc/set_flag(flag,hint)
	ASSERT(flag != null && hint)

	switch(hint)
		if(NIF_FLAGS_VISION)
			vision_flags |= flag
		if(NIF_FLAGS_HEALTH)
			health_flags |= flag
		if(NIF_FLAGS_COMBAT)
			combat_flags |= flag
		if(NIF_FLAGS_OTHER)
			other_flags |= flag
		else
			CRASH("Not a valid NIF set_flag hint: [hint]")

//Clear a flag from one of the holders
/obj/item/nif/proc/clear_flag(flag,hint)
	ASSERT(flag != null && hint)

	switch(hint)
		if(NIF_FLAGS_VISION)
			vision_flags &= ~flag
		if(NIF_FLAGS_HEALTH)
			health_flags &= ~flag
		if(NIF_FLAGS_COMBAT)
			combat_flags &= ~flag
		if(NIF_FLAGS_OTHER)
			other_flags &= ~flag
		else
			CRASH("Not a valid NIF clear_flag hint: [hint]")

//Check for an installed implant
/obj/item/nif/proc/imp_check(soft)
	if(stat != NIF_WORKING) return FALSE
	ASSERT(soft)

	if(ispath(soft))
		var/datum/nifsoft/path = soft
		soft = initial(path.list_pos)
	var/entry = nifsofts[soft]
	if(entry)
		return entry

//Check for a set flag
/obj/item/nif/proc/flag_check(flag,hint)
	if(stat != NIF_WORKING) return FALSE

	ASSERT(flag && hint)

	var/result = FALSE
	switch(hint)
		if(NIF_FLAGS_VISION)
			if(flag & vision_flags) result = TRUE
		if(NIF_FLAGS_HEALTH)
			if(flag & health_flags) result = TRUE
		if(NIF_FLAGS_COMBAT)
			if(flag & combat_flags) result = TRUE
		if(NIF_FLAGS_OTHER)
			if(flag & other_flags) result = TRUE
		else
			CRASH("Not a valid NIF flag hint: [hint]")

	return result

/obj/item/nif/proc/planes_visible()
	if(stat != NIF_WORKING)
		return list() //None!

	return planes_visible || list()

/obj/item/nif/proc/add_plane(planeid = null)
	if(!planeid)
		return
	LAZYOR(planes_visible, planeid)

/obj/item/nif/proc/del_plane(planeid = null)
	if(!planeid)
		return
	LAZYREMOVE(planes_visible, planeid)

/obj/item/nif/proc/vis_update()
	if(human)
		human.recalculate_vis()

// Alternate NIFs
/obj/item/nif/bad
	name = "bootleg NIF"
	desc = "When NanoTrasen tried to replicate the NIF tech by themselves, this is what they made. You probably shouldn't allow this inside you."
	durability = 10
	starting_software = null

/obj/item/nif/authentic
	name = "luxury NIF"
	desc = "An actual nano working surface, in a box. These are the high-end models, usually only available to big spenders and those with serious contacts. \
	Despite the all the marketing speak, they're really just a high-endurance NIF when it comes down to it."
	durability = 1000

/obj/item/nif/authenticbio
	name = "Bioadaptive Authentic NIF"
	desc = "The cutting-edge of NIF technology, this is the strongest, most reliable, and most adaptive framework developed to date. Extremely expensive to produce."
	durability = 1000
	bioadap = TRUE

/obj/item/nif/bioadap
	name = "bioadaptive NIF"
	desc = "A NIF that goes out of it's way to accomodate strange body types. \
	Will function in species where it normally wouldn't."
	durability = 75
	bioadap = TRUE

/obj/item/nif/protean				// Proteans' integrated NIF
	name = "protean integrated NIF"
	desc = "A NIF that is part of a protean's body structure. Where did you get that anyway?"
	durability = 25
	bioadap = TRUE
	gib_nodrop = TRUE

/obj/item/nif/glitch
	name = "weird NIF"
	desc = "A NIF of a very dubious origin. It seems to be more durable than normal one... But are you sure about this?"
	durability = 300
	bioadap = TRUE
	starting_software = list(
		/datum/nifsoft/commlink,
		/datum/nifsoft/soulcatcher,
		/datum/nifsoft/ar_civ,
		/datum/nifsoft/malware
	)

/obj/item/nif/glitch/bad
	name = "odd NIF"
	desc = "A NIF of a very dubious origin."
	durability = 100
	bioadap = FALSE

////////////////////////////////
// Special Promethean """surgery"""
/obj/item/nif/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!ishuman(M) || !ishuman(user) || (M == user))
		return ..()

	var/mob/living/carbon/human/U = user
	var/mob/living/carbon/human/T = M

	if(T.species?.is_slime_bodied && target_zone == BP_TORSO)
		if(T.get_equipped_item(SLOT_ID_UNIFORM) || T.get_equipped_item(SLOT_ID_SUIT))
			to_chat(user,span_warning("Remove any clothing they have on, as it might interfere!"))
			return ITEM_INTERACT_FAILURE
		var/obj/item/organ/external/eo = T.get_organ(BP_TORSO)
		if(!eo)
			to_chat(user,span_warning("They should probably regrow their torso first."))
			return ITEM_INTERACT_FAILURE
		act_message(U, src, MSG_SELF(span_notice("You begin installing %T% into [T]'s chest by just stuffing it in.")), \
			MSG_OTHERS(span_notice("%U% begins installing %T% into [T]'s chest by just stuffing it in.")), \
			MSG_BLIND("There's a wet SQUISH noise."))
		om_task_start(/datum/om/task/timed/nif_stuff_in, user, T, receiver = src, eo = eo, target_zone = BP_TORSO)
		return ITEM_INTERACT_SUCCESS
	else
		return ..()

/datum/om/task/timed/nif_stuff_in
	duration = 20 SECONDS
	complete_proc = /obj/item/nif/proc/stuff_in_done
	var/obj/item/organ/external/eo

/obj/item/nif/proc/stuff_in_done(datum/om/task/timed/nif_stuff_in/task)
	var/mob/living/user = task.actor
	var/mob/living/carbon/human/T = task.target
	var/obj/item/organ/external/eo = task.eo
	user.unEquip(src)
	forceMove(eo)
	rel_add(eo, nameof(eo.implants), src)
	implant(T)
	play_sfx(T, SFX_EFFECTS_SLIME_SQUISH)

/mob/living/carbon/human/proc/set_nif_examine()
	set name = "NIF Appearance"
	set desc = "If your NIF alters your appearance in some way, describe it here."
	set category = VERB_CAT_OOC_GAME_SETTINGS

	if(!nif)
		// The NIF granted this verb; its unimplant or deletion already revoked it.
		to_chat(src,span_warning("You don't have a NIF, not sure why this was here."))
		return

	open_request(src, /datum/prompt/text/nif_appearance, PROC_REF(nif_appearance_answered), answerer = src, default = nif.examine_msg)

/datum/prompt/text/nif_appearance
	question = "Describe how your NIF alters your appearance, like glowy eyes or metal plate on your head, etc. Be sensible. Clear this for no examine text. 128ch max."
	title = "Describe NIF"
	max_len = 128
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/nif_appearance/recheck_extra()
	var/mob/living/carbon/human/user = owner
	if(!istype(user) || QDELETED(user) || QDELETED(answerer))
		return "gone"
	if(!user.nif)
		return "no NIF"

/mob/living/carbon/human/proc/nif_appearance_answered(datum/act/request/context)
	if(isnull(context.request.value) || context.request.last_error == "gone")
		return
	SStgui.update_uis(src)
	if(context.answer)
		apply_nif_appearance(context.answer.value)
	else if(context.request.last_error == "no NIF")
		to_chat(src,span_warning("You don't have a NIF, not sure why this was here."))

/mob/living/carbon/human/proc/apply_nif_appearance(new_flavor)
	//Sanitize or user cleaned it entirely
	if(!new_flavor)
		nif.examine_msg = ""
		nif.save_data["examine_msg"] = ""
	else
		nif.examine_msg = new_flavor
		nif.save_data["examine_msg"] = new_flavor
	// No mid-round save: NIF data persists on death, round end and leaving the round.

// The implanted human and its NIF name each other (the NIF lives in an organ's implants).
