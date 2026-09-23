////////////////////////////////
//// Machines required for body printing
//// and decanting into bodies
////////////////////////////////

/////// Grower Pod ///////
/obj/machinery/clonepod/transhuman
	name = "grower pod"
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	circuit = /obj/item/circuitboard/transhuman_clonepod

//A full version of the pod
/obj/machinery/clonepod/transhuman/full/Initialize(mapload)
	. = ..()
	for(var/i = 1 to container_limit)
		LAZYADD(containers, new /obj/item/reagent_containers/glass/bottle/biomass(src))

/obj/machinery/clonepod/transhuman/growclone(datum/transhuman/body_record/current_project)
	//Manage machine-specific stuff.
	if(mess || attempting)
		return 0
	attempting = 1 //One at a time!!
	locked = 1
	eject_wait = 1
	spawn(30)
		eject_wait = 0

	// Remove biomass when the cloning is started, rather than when the guy pops out
	remove_biomass(CLONE_BIOMASS)

	//Get the DNA and generate a new mob
	var/mob/living/carbon/human/H = current_project.produce_human_mob(src,FALSE,FALSE,"clone ([rand(0,999)])")
	SEND_SIGNAL(H, COMSIG_HUMAN_DNA_FINALIZED)

	//Give breathing equipment if needed
	if(current_project.breath_type != null && current_project.breath_type != GAS_O2)
		H.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(H), slot_wear_mask)
		var/obj/item/tank/tankpath
		if(current_project.breath_type == GAS_PHORON)
			tankpath = /obj/item/tank/vox
		else
			tankpath = text2path("/obj/item/tank/" + current_project.breath_type)

		if(tankpath)
			H.equip_to_slot_or_del(new tankpath(H), slot_back)
			H.internal = H.get_equipped_item(SLOT_ID_BACK)
			if(istype(H.internal,/obj/item/tank) && H.internals)
				H.internals.icon_state = "internal1"

	//Apply damage: the sleeve is grown out of genetic damage in the pod.
	set_occupant(H)
	H.body.afflict(/datum/affliction/genetic_damage, null, DQ_SLEEVE_GROWTH_LOAD)
	H.Paralyse(4)
	H.Sleeping(4)

	//Machine specific stuff at the end
	update_icon()
	attempting = 0
	return 1

/obj/machinery/clonepod/transhuman/process()
	var/mob/living/occupant = get_occupant()
	if(stat & NOPOWER)
		if(occupant)
			locked = 0
			go_out()
		return

	if((occupant) && (occupant.loc == src))
		if(occupant.stat == DEAD)
			locked = 0
			go_out()
			connected_message("Clone Rejected: Deceased.")
			return

		else if(clone_growth_load(occupant) > clone_release_load())

			//Slowly get that clone healed and finished.
			occupant.mend(TREAT_GENETIC_REPAIR, (2 * heal_rate) / DQ_CLONE_GROWTH_SCALE)

			//Premature clones may have brain damage.
			occupant.mend(TREAT_NEURAL_REPAIR, CEILING((0.5*heal_rate), 1))

			//So clones don't die of oxyloss in a running pod.
			if(occupant.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE) < 30)
				occupant.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 60)

			//Also oxygenate ourselves because inaprovaline is so bad at preventing hypoxia!!
			occupant.mend(TREAT_OXYGENATION, 4)

			use_power(7500) //This might need tweaking.
			return

		else if(!eject_wait)
			playsound(src, 'sound/machines/ding.ogg', 50, 1)
			audible_message("\The [src] signals that the growing process is complete.", runemessage = "ding")
			connected_message("Growing Process Complete.")
			locked = 0
			go_out()
			return

	else if((!occupant) || (occupant.loc != src))
		set_occupant(null)
		if(locked)
			locked = 0
		update_icon()
		return

	return

/// Sleeves are grown out completely before release.
/obj/machinery/clonepod/transhuman/clone_release_load()
	return 0

/obj/machinery/clonepod/transhuman/examine(mob/user, infix, suffix)
	. = ..()
	if(get_occupant())
		var/completion = get_completion()
		. += "Progress: [round(completion)]% [chat_progress_bar(round(completion), TRUE)]"

//Synthetic version
/obj/machinery/transhuman/synthprinter
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "SynthFab 3000"
	desc = "A rapid fabricator for synthetic bodies."
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	icon = 'icons/obj/machines/synthpod.dmi'
	icon_state = "pod_0"
	circuit = /obj/item/circuitboard/transhuman_synthprinter
	density = TRUE
	anchored = TRUE

	var/list/stored_material =  list(MAT_STEEL = 30000, MAT_GLASS = 30000)
	var/connected      //What console it's done up with
	var/busy = 0       //Busy cloning
	var/body_cost = 15000  //Cost of a cloned body (metal and glass ea.)
	var/max_res_amount = 30000 //Max the thing can hold
	var/datum/weakref/current_br

	var/broken = 0
	var/burn_value = 0 //Setting these to 0, if resleeving as organic with unupgraded sleevers gives them no damage, resleeving synths with unupgraded synthfabs should not give them potentially 105 damage.
	var/brute_value = 0

// This board declares no req_components, so its default parts are declared
// here instead of read off the board (roadmap C6): still resolved lazily
// into latent entries in CONTAINER_SLOT_INTERNALS, not eager objects.
/obj/machinery/transhuman/synthprinter/latent_generator()
	return list(
		circuit = 1,
		/obj/item/stock_parts/matter_bin = 1,
		/obj/item/stock_parts/scanning_module = 1,
		/obj/item/stock_parts/manipulator = 2,
		/obj/item/stack/cable_coil = 2,
	)

/obj/machinery/transhuman/synthprinter/Initialize(mapload)
	. = ..()
	component_parts = null
	RefreshParts()
	update_icon()

/obj/machinery/transhuman/synthprinter/Destroy()
	current_br = null
	. = ..()

/obj/machinery/transhuman/synthprinter/RefreshParts()

	//Scanning modules reduce burn rating by 15 each
	var/burn_rating = initial(burn_value)
	burn_rating -= get_part_rating(/obj/item/stock_parts/scanning_module) * 15
	burn_value = burn_rating

	//Manipulators reduce brute by 10 each
	var/brute_rating = initial(burn_value)
	brute_rating -= get_part_rating(/obj/item/stock_parts/manipulator) * 10
	brute_value = brute_rating

	//Matter bins multiply the storage amount by their rating.
	var/store_rating = initial(max_res_amount)
	for(var/obj/item/stock_parts/matter_bin/MB in slot_contents(CONTAINER_SLOT_INTERNALS))
		store_rating = store_rating * MB.rating
	for(var/datum/latent_entry/entry as anything in latent_entries(CONTAINER_SLOT_INTERNALS))
		if(ispath(entry.path, /obj/item/stock_parts/matter_bin))
			var/rating = dq_type_var(entry.path, "rating")
			for(var/i in 1 to entry.count)
				store_rating = store_rating * rating
	max_res_amount = store_rating

/obj/machinery/transhuman/synthprinter/process()
	if(stat & NOPOWER)
		if(busy)
			busy = 0
			current_br = null
		update_icon()
		return

	if(busy > 0 && busy <= 95)
		busy += 5

	if(busy >= 100)
		make_body()

	return

/obj/machinery/transhuman/synthprinter/proc/print(datum/weakref/BR)
	if(!BR?.resolve() || busy)
		return 0

	if(stored_material[MAT_STEEL] < body_cost || stored_material[MAT_GLASS] < body_cost)
		return 0

	current_br = BR
	busy = 5
	update_icon()

	return 1

/obj/machinery/transhuman/synthprinter/proc/make_body()
	//Manage machine-specific stuff

	var/datum/transhuman/body_record/current_project = current_br?.resolve()
	if(!current_project)
		busy = 0
		current_br = null
		update_icon()
		return

	//Get the DNA and generate a new mob
	var/mob/living/carbon/human/H = current_project.produce_human_mob(src,TRUE,FALSE,"synth ([rand(0,999)])")
	SEND_SIGNAL(H, COMSIG_HUMAN_DNA_FINALIZED)

	//Apply damage
	H.injure(INJURY_BLUNT, brute_value, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.injure(INJURY_BURN, burn_value, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)

	//Plonk them here.
	H.forceMove(get_turf(src))

	//Machine specific stuff at the end
	stored_material[MAT_STEEL] -= body_cost
	stored_material[MAT_GLASS] -= body_cost
	busy = 0
	update_icon()

	return 1

/obj/machinery/transhuman/synthprinter/attack_hand(mob/user)
	if((busy == 0) || (stat & NOPOWER))
		return
	to_chat(user, "Current print cycle is [busy]% complete.")
	return

/obj/machinery/transhuman/synthprinter/attackby(obj/item/W, mob/user)
	src.add_fingerprint(user)
	if(busy)
		to_chat(user, span_notice("\The [src] is busy. Please wait for completion of previous operation."))
		return
	if(default_part_replacement(user, W))
		return
	if(panel_open)
		to_chat(user, span_notice("You can't load \the [src] while it's opened."))
		return
	if(!istype(W, /obj/item/stack/material))
		to_chat(user, span_notice("You cannot insert this item into \the [src]!"))
		return

	var/obj/item/stack/material/S = W
	if(!(S.material.name in stored_material))
		to_chat(user, span_warning("\The [src] doesn't accept [material_display_name(S.material)]!"))
		return

	var/amnt = S.perunit
	if(stored_material[S.material.name] + amnt <= max_res_amount)
		if(S && S.get_amount() >= 1)
			var/count = 0
			while(stored_material[S.material.name] + amnt <= max_res_amount && S.get_amount() >= 1)
				stored_material[S.material.name] += amnt
				S.use(1)
				count++
			to_chat(user, "You insert [count] [S.name] into \the [src].")
	else
		to_chat(user, "\the [src] cannot hold more [S.name].")

	return

/obj/machinery/transhuman/synthprinter/update_icon()
	..()
	icon_state = "pod_0"
	if(busy && !(stat & NOPOWER))
		icon_state = "pod_1"
	else if(broken)
		icon_state = "pod_g"

/////// Resleever Pod ///////
/obj/machinery/transhuman/resleever
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "resleeving pod"
	desc = "Used to combine mind and body into one unit."
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	icon = 'icons/obj/machines/implantchair.dmi'
	icon_state = "implantchair"
	circuit = /obj/item/circuitboard/transhuman_resleever
	density = TRUE
	opacity = 0
	anchored = TRUE
	var/blur_amount
	var/confuse_amount

	VAR_PRIVATE/datum/weakref/weakref_occupant = null
	var/connected = null

	var/sleevecards = 2

// This board declares no req_components, so its default parts are declared
// here instead of read off the board (roadmap C6): still resolved lazily
// into latent entries in CONTAINER_SLOT_INTERNALS, not eager objects.
/obj/machinery/transhuman/resleever/latent_generator()
	return list(
		circuit = 1,
		/obj/item/stock_parts/scanning_module = 2,
		/obj/item/stock_parts/manipulator = 2,
		/obj/item/stock_parts/console_screen = 1,
		/obj/item/stack/cable_coil = 2,
	)

/obj/machinery/transhuman/resleever/Initialize(mapload)
	. = ..()
	component_parts = null
	RefreshParts()
	update_icon()

/obj/machinery/transhuman/resleever/Destroy()
	. = ..()


/obj/machinery/transhuman/resleever/proc/set_occupant(mob/living/carbon/human/H)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!H)
		weakref_occupant = null
		return
	weakref_occupant = WEAKREF(H)

/obj/machinery/transhuman/resleever/proc/get_occupant()
	RETURN_TYPE(/mob/living/carbon/human)
	SHOULD_NOT_OVERRIDE(TRUE)
	return weakref_occupant?.resolve()

/obj/machinery/transhuman/resleever/RefreshParts()
	var/scan_rating = get_part_rating(/obj/item/stock_parts/scanning_module)
	confuse_amount = (48 - scan_rating * 8)

	var/manip_rating = get_part_rating(/obj/item/stock_parts/manipulator)
	blur_amount = (48 - manip_rating * 8)

/obj/machinery/transhuman/resleever/attack_hand(mob/user as mob)
	tgui_interact(user)

/obj/machinery/transhuman/resleever/tgui_interact(mob/user, datum/tgui/ui = null)
	if(stat & (NOPOWER|BROKEN))
		return

	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ResleevingPod", "Resleever")
		ui.open()

/obj/machinery/transhuman/resleever/tgui_data(mob/user)
	var/list/data = list()

	var/mob/living/carbon/human/H = get_occupant()
	data["occupied"] = !!H
	if(H)
		data["name"] = H.name
		data["health"] = round(H.vitality() * 100)
		data["stat"] = H.stat
		data["mindStatus"] = !!H.mind
		data["mindName"] = H.mind?.name
	return data

/obj/machinery/transhuman/resleever/attackby(obj/item/W, mob/user)
	src.add_fingerprint(user)
	if(default_part_replacement(user, W))
		return
	if(istype(W, /obj/item/grab))
		var/obj/item/grab/G = W
		if(!ismob(G.affecting))
			return
		var/mob/M = G.affecting
		if(put_mob(M))
			qdel(G)
			return //Don't call up else we'll get attack messsages
	if(istype(W, /obj/item/paicard/sleevecard))
		var/obj/item/paicard/sleevecard/C = W
		user.unEquip(C)
		C.removePersonality()
		qdel(C)
		sleevecards++
		to_chat(user, span_notice("You store \the [C] in \the [src]."))
		return

	return ..()

/obj/machinery/transhuman/resleever/MouseDrop_T(mob/living/carbon/O, mob/user)
	if(!istype(O))
		return 0 //not a mob
	if(user.incapacitated())
		return 0 //user shouldn't be doing things
	if(O.anchored)
		return 0 //mob is anchored???
	if(get_dist(user, src) > 1 || get_dist(user, O) > 1)
		return 0 //doesn't use adjacent() to allow for non-GLOB.cardinal (fuck my life)
	if(!ishuman(user) && !isrobot(user))
		return 0 //not a borg or human
	if(panel_open)
		to_chat(user, span_notice("Close the maintenance panel first."))
		return 0 //panel open

	if(O.buckled)
		return 0
	if(O.has_buckled_mobs())
		to_chat(user, span_warning("\The [O] has other entities attached to it. Remove them first."))
		return

	if(put_mob(O))
		if(O == user)
			visible_message("[user] climbs into \the [src].")
		else
			visible_message("[user] puts [O] into \the [src].")

	add_fingerprint(user)

/obj/machinery/transhuman/resleever/proc/putmind(datum/transhuman/mind_record/MR, mode = 1, mob/living/carbon/human/override = null, db_key)
	var/mob/living/carbon/human/occupant = get_occupant()
	if((!occupant || !istype(occupant) || occupant.stat >= DEAD) && mode == 1)
		return 0

	if(mode == 2 && sleevecards) //Card sleeving
		var/obj/item/paicard/sleevecard/card = new /obj/item/paicard/sleevecard(get_turf(src))
		card.sleeveInto(MR, db_key = db_key)
		sleevecards--
		return 1

	//If we're sleeving a subtarget, briefly swap them to not need to duplicate tons of code.
	var/mob/living/carbon/human/original_occupant
	if(override)
		original_occupant = occupant
		occupant = override

	//In case they already had a mind!
	if(occupant && occupant.mind)
		to_chat(occupant, span_warning("You feel your mind being overwritten..."))
		log_and_message_admins("was resleeve-wiped from their body.",occupant.mind)
		occupant.ghostize()

	// The mind brings its identity (languages, OOC notes) by reference.
	MR.mind_ref.active = 1 //Well, it's about to be.
	transfer_mind(MR.mind_ref, occupant, "resleeved") //Does mind+ckey+client.
	occupant.identifying_gender = MR.id_gender

	occupant.apply_vore_prefs() //Cheap hack for now to give them SOME bellies.
	if(MR.one_time)
		var/how_long = round((world.time - MR.last_update)/10/60)
		to_chat(occupant, span_danger("Your mind backup was a 'one-time' backup. \
		You will not be able to remember anything since the backup, [how_long] minutes ago."))

	//Re-supply a NIF if one was backed up with them.
	if(MR.nif_path)
		var/obj/item/nif/nif = new MR.nif_path(occupant,null,MR.nif_savedata)
		spawn(0)			//Delay to not install software before NIF is fully installed
			for(var/path in MR.nif_software)
				new path(nif)
		nif.durability = MR.nif_durability //Restore backed up durability after restoring the softs.

	// If it was a custom sleeve (not owned by anyone), update namification sequences
	if(!occupant.original_player)
		occupant.real_name = occupant.mind.name
		occupant.name = occupant.real_name
		occupant.dna.real_name = occupant.real_name

	//Give them a backup implant
	var/obj/item/implant/backup/new_imp = new()
	if(new_imp.handle_implant(occupant, BP_HEAD))
		new_imp.post_implant(occupant)


	//Inform them and make them a little dizzy.
	if(confuse_amount + blur_amount <= 16)
		to_chat(occupant, span_notice("You feel a small pain in your head as you're given a new backup implant. Your new body feels comfortable already, however."))
	else
		to_chat(occupant, span_warning("You feel a small pain in your head as you're given a new backup implant. Oh, and a new body. It's disorienting, to say the least."))

	occupant.SetConfused(max(occupant.confused, confuse_amount))								// Apply immedeate effects
	occupant.eye_blurry = max(occupant.eye_blurry, blur_amount)

	// Vore deaths get a fake modifier labeled as such
	if(!occupant.mind)
		log_runtime("[occupant] didn't have a mind to check for vore_death, which may be problematic.")

	if(occupant.mind)
		if(occupant.original_player && ckey(occupant.mind.key) != occupant.original_player)
			log_and_message_admins("is now a cross-sleeved character. Body originally belonged to [occupant.real_name]. Mind is now [occupant.mind.name].",occupant)
		var/datum/antagonist/antag_data = SSantag_job.get_antag_data(occupant.mind.special_role)
		if(antag_data)
			antag_data.add_antagonist(occupant.mind)
			antag_data.place_mob(occupant)
		if(occupant.mind.antag_holder)
			occupant.mind.antag_holder.apply_antags(occupant)

	if(original_occupant)
		occupant = original_occupant

	playsound(src, 'sound/machines/medbayscanner1.ogg', 100, 1) // Play our sound at the end of the mind injection!
	return 1

/obj/machinery/transhuman/resleever/proc/go_out()
	var/mob/living/carbon/human/occupant = get_occupant()
	if(!occupant)
		return
	occupant.forceMove(get_turf(src))
	set_occupant(null)
	icon_state = "implantchair"
	return

/obj/machinery/transhuman/resleever/proc/put_mob(mob/living/carbon/human/M)
	if(!ishuman(M))
		to_chat(usr, span_warning("\The [src] cannot hold this!"))
		return
	if(get_occupant())
		to_chat(usr, span_warning("\The [src] is already occupied!"))
		return
	M.stop_pulling()
	M.forceMove(src)
	set_occupant(M)
	src.add_fingerprint(usr)
	icon_state = "implantchair_on"
	return 1

/obj/machinery/transhuman/resleever/verb/get_out()
	set name = "EJECT Occupant"
	set category = "Object"
	set src in oview(1)
	if(usr.stat != 0)
		return
	go_out()
	add_fingerprint(usr)
	return

/obj/machinery/transhuman/resleever/verb/move_inside()
	set name = "Move INSIDE"
	set category = "Object"
	set src in oview(1)
	if(usr.stat != 0 || stat & (NOPOWER|BROKEN))
		return
	put_mob(usr)
	return
