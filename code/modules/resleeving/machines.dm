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
		rel_add(src, nameof(containers), new /obj/item/reagent_containers/glass/bottle/biomass(src))

/obj/machinery/clonepod/transhuman/growclone(datum/transhuman/body_record/current_project)
	//Manage machine-specific stuff.
	if(mess || attempting)
		return 0
	attempting = 1 //One at a time!!
	set_locked(1)
	eject_wait = 1
	after(src, 3 SECONDS, PROC_REF(allow_eject))

	// Remove biomass when the cloning is started, rather than when the guy pops out
	remove_biomass(CLONE_BIOMASS)

	//Get the DNA and generate a new mob
	var/mob/living/carbon/human/H = current_project.produce_human_mob(src,FALSE,FALSE,"clone ([rand(0,999)])")
	PUBLISH_LEGACY(H, /datum/notice/human_dna_finalized)

	//Give breathing equipment if needed
	if(current_project.breath_type != null && current_project.breath_type != GAS_O2)
		H.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(H), SLOT_ID_MASK)
		var/obj/item/tank/tankpath
		if(current_project.breath_type == GAS_PHORON)
			tankpath = /obj/item/tank/vox
		else
			tankpath = text2path("/obj/item/tank/" + current_project.breath_type)

		if(tankpath)
			H.equip_to_slot_or_del(new tankpath(H), SLOT_ID_BACK)
			rel_set(H, nameof(H.internal), H.get_equipped_item(SLOT_ID_BACK))
			if(istype(H.internal,/obj/item/tank) && H.internals)
				H.internals.icon_state = "internal1"

	//Apply damage: the sleeve is grown out of genetic damage in the pod.
	set_occupant(H)
	H.body.afflict(/datum/affliction/genetic_damage, null, DQ_SLEEVE_GROWTH_LOAD)
	H.status_at_least(STAT_PARALYZED, 4)
	H.status_at_least(STAT_SLEEPING, 4)

	//Machine specific stuff at the end
	update_icon()
	attempting = 0
	return 1

/// Grows its clone while it has one (set_occupant() wakes it); empty, it sleeps.
/obj/machinery/clonepod/transhuman/work_step(datum/act/timer/A)
	var/mob/living/occupant = get_occupant()
	if(has_stat(NOPOWER))
		if(occupant)
			set_locked(0)
			go_out()
		return PROCESS_KILL

	if((occupant) && (occupant.loc == src))
		if(occupant.stat == DEAD)
			set_locked(0)
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
			play_sfx(src, SFX_MACHINES_DING)
			audible_message("\The [src] signals that the growing process is complete.", runemessage = "ding")
			connected_message("Growing Process Complete.")
			set_locked(0)
			go_out()
			return

	else if((!occupant) || (occupant.loc != src))
		set_occupant(null)
		if(locked)
			set_locked(0)
		update_icon()
		return PROCESS_KILL

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

	var/list/stored_material =  list(MAT_STEEL = 30000, MAT_GLASS = 30000) // ALLOW(instance_list): d: edited in place per instance (3 writers)
	var/obj/machinery/computer/transhuman/resleeving/connected      //What console it's done up with (relation)
	var/body_cost = 15000  //Cost of a cloned body (metal and glass ea.)
	var/max_res_amount = 30000 //Max the thing can hold
	var/datum/transhuman/body_record/current_br // the record being printed (relation)

	var/broken = 0
	var/burn_value = 0 //Setting these to 0, if resleeving as organic with unupgraded sleevers gives them no damage, resleeving synths with unupgraded synthfabs should not give them potentially 105 damage.
	var/brute_value = 0

// This board declares no req_components, so its default parts are declared
// here instead of read off the board (roadmap C6): still resolved lazily
// into latent entries in CONTAINER_SLOT_INTERNALS, not eager objects.
/// Print progress (percent); 0 while idle.
OM_FIELD(/obj/machinery/transhuman/synthprinter, busy, 0, CHANGE_MACHINE_SETTINGS)
/obj/machinery/transhuman/synthprinter/latent_generator()
	// `list(circuit = 1, ...)` would use the literal identifier "circuit" as
	// the key (DM's named-argument list syntax), not circuit's value -- the
	// key must be set by index instead to be the board's actual type path.
	var/list/gen = list(
		/obj/item/stock_parts/matter_bin = 1,
		/obj/item/stock_parts/scanning_module = 1,
		/obj/item/stock_parts/manipulator = 2,
		/obj/item/stack/cable_coil = 2,
	)
	gen[circuit] = 1
	return gen

/obj/machinery/transhuman/synthprinter/Initialize(mapload)
	. = ..()
	own_clear(src, nameof(component_parts), OWN_DELETE) // this machine runs without stock parts
	RefreshParts()
	update_icon()

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

/// Prints while busy with a body; idle, it sleeps until one is queued.
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/transhuman/synthprinter)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(busy), wakes_on = list(nameof(busy)))

/obj/machinery/transhuman/synthprinter/proc/work_step(datum/act/timer/A)
	if(has_stat(NOPOWER))
		set_busy(0)
		rel_clear(src, nameof(current_br))
		update_icon()
		return

	if(busy > 0 && busy <= 95)
		set_busy(busy + 5)

	if(busy >= 100)
		make_body()

/obj/machinery/transhuman/synthprinter/proc/print(datum/transhuman/body_record/BR)
	if(!istype(BR) || QDELETED(BR) || busy)
		return 0

	if(stored_material[MAT_STEEL] < body_cost || stored_material[MAT_GLASS] < body_cost)
		return 0

	rel_set(src, nameof(current_br), BR)
	set_busy(5)
	update_icon()

	return 1

/obj/machinery/transhuman/synthprinter/proc/make_body()
	//Manage machine-specific stuff

	var/datum/transhuman/body_record/current_project = current_br
	if(!current_project)
		set_busy(0)
		rel_clear(src, nameof(current_br))
		update_icon()
		return

	//Get the DNA and generate a new mob
	var/mob/living/carbon/human/H = current_project.produce_human_mob(src,TRUE,FALSE,"synth ([rand(0,999)])")
	PUBLISH_LEGACY(H, /datum/notice/human_dna_finalized)

	//Apply damage
	H.injure(INJURY_BLUNT, brute_value, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.injure(INJURY_BURN, burn_value, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)

	//Plonk them here.
	H.forceMove(get_turf(src))

	//Machine specific stuff at the end
	stored_material[MAT_STEEL] -= body_cost
	stored_material[MAT_GLASS] -= body_cost
	set_busy(0)
	update_icon()

	return 1

EXTEND_INTERACTIONS(/obj/machinery/transhuman/synthprinter, \
	INTERACT_HAND_UNGATED(null, PROC_REF(synthprinter_interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(synthprinter_interaction_item)), \
)

/// Old attack_hand.
/obj/machinery/transhuman/synthprinter/proc/synthprinter_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if((busy == 0) || (has_stat(NOPOWER)))
		return TRUE
	to_chat(user, "Current print cycle is [busy]% complete.")
	return TRUE

/// Old attackby.
/obj/machinery/transhuman/synthprinter/proc/synthprinter_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	. = INTERACTION_HANDLED_PASS
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

APPEARANCE_TEMPLATE(/obj/machinery/transhuman/synthprinter, "pod_{appearance_mode}")

/obj/machinery/transhuman/synthprinter/proc/appearance_mode()
	if(busy && !has_stat(NOPOWER))
		return "1"
	return broken ? "g" : "0"

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

	/// The occupant in the sealed occupant slot (a relation view; set only by set_occupant()).
	var/mob/living/carbon/human/sleever_occupant
	var/obj/machinery/computer/transhuman/resleeving/connected //What console it's done up with (relation)

	var/sleevecards = 2

// This board declares no req_components, so its default parts are declared
// here instead of read off the board (roadmap C6): still resolved lazily
// into latent entries in CONTAINER_SLOT_INTERNALS, not eager objects.
/obj/machinery/transhuman/resleever/latent_generator()
	// `list(circuit = 1, ...)` would use the literal identifier "circuit" as
	// the key (DM's named-argument list syntax), not circuit's value -- the
	// key must be set by index instead to be the board's actual type path.
	var/list/gen = list(
		/obj/item/stock_parts/scanning_module = 2,
		/obj/item/stock_parts/manipulator = 2,
		/obj/item/stock_parts/console_screen = 1,
		/obj/item/stack/cable_coil = 2,
	)
	gen[circuit] = 1
	return gen

/obj/machinery/transhuman/resleever/Initialize(mapload)
	. = ..()
	own_clear(src, nameof(component_parts), OWN_DELETE) // this machine runs without stock parts
	RefreshParts()
	update_icon()

/// Sealed occupant slot (C8a, containment.md §10): the sleever's own field is
/// the occupant's environment, same as before the ledger tracked it.
/datum/om/relation/slot/occupant/resleever
	holder = /obj/machinery/transhuman/resleever
	slot_id = OCCUPANT_SLOT_RESLEEVER
	name = "resleever"

/obj/machinery/transhuman/resleever/proc/set_occupant(mob/living/carbon/human/H)
	SHOULD_NOT_OVERRIDE(TRUE)
	rel_set(src, nameof(sleever_occupant), H) // null clears it

/obj/machinery/transhuman/resleever/proc/get_occupant()
	RETURN_TYPE(/mob/living/carbon/human)
	SHOULD_NOT_OVERRIDE(TRUE)
	return sleever_occupant

/obj/machinery/transhuman/resleever/RefreshParts()
	var/scan_rating = get_part_rating(/obj/item/stock_parts/scanning_module)
	confuse_amount = (48 - scan_rating * 8)

	var/manip_rating = get_part_rating(/obj/item/stock_parts/manipulator)
	blur_amount = (48 - manip_rating * 8)

EXTEND_INTERACTIONS(/obj/machinery/transhuman/resleever, \
	INTERACT_HAND_UNGATED(null, TYPE_PROC_REF(/atom, interaction_open_ui)), \
	INTERACT_ITEM(null, PROC_REF(resleever_interaction_item)), \
	INTERACT_DRAG("Put inside", PROC_REF(resleever_interaction_drag), REQ_PANEL(FALSE), REQ_TARGET_STATE(/obj/machinery/transhuman/resleever/proc/can_take_dragged)), \
	INTERACT_VERB("EJECT Occupant", PROC_REF(resleever_verb_eject)), \
	INTERACT_VERB("Move INSIDE", PROC_REF(resleever_verb_move_inside)), \
)

CAPABILITIES(/obj/machinery/transhuman/resleever)
	interface("ResleevingPod", title = "Resleever")
	without("ui_open")
	ui_shape(occupied = bool(), name = schema_text(), health = num(), stat = num(), mindStatus = bool(), mindName = schema_text())

/obj/machinery/transhuman/resleever/ui_prepare(mob/user, datum/tgui/ui)
	if(!operable())
		return FALSE

	return TRUE

/// /obj/machinery/transhuman/resleever's window data.
/obj/machinery/transhuman/resleever/ui_data(datum/act/eval/A)
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

/// Old attackby.
/obj/machinery/transhuman/resleever/proc/resleever_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	src.add_fingerprint(user)
	if(default_part_replacement(user, W))
		return INTERACTION_HANDLED_PASS
	if(istype(W, /obj/item/grab))
		var/obj/item/grab/G = W
		if(!ismob(G?.grab_target()))
			return INTERACTION_HANDLED_PASS
		var/mob/M = G?.grab_target()
		if(put_mob(M, user))
			consume(G, user)
			return INTERACTION_HANDLED_PASS //Don't call up else we'll get attack messsages
	if(istype(W, /obj/item/paicard/sleevecard))
		var/obj/item/paicard/sleevecard/C = W
		user.unEquip(C)
		C.removePersonality()
		consume(C, user)
		sleevecards++
		to_chat(user, span_notice("You store \the [C] in \the [src]."))
		return INTERACTION_HANDLED_PASS

	return FALSE

/// Requirement: a mob carrying others can't be put inside. Anything that isn't a mob is turned away silently by the effect.
/obj/machinery/transhuman/resleever/proc/can_take_dragged(mob/user, atom/target, atom/movable/held)
	if(ismob(held))
		var/mob/M = held
		if(M.has_buckled_mobs())
			return "[M] has other entities attached to it; remove them first"
	return TRUE

/// Old MouseDrop_T.
/obj/machinery/transhuman/resleever/proc/resleever_interaction_drag(mob/user, mob/living/carbon/O, datum/interaction/interaction)
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

	if(O?.buckled_to())
		return 0

	if(put_mob(O, user))
		if(O == user)
			act_message(user, src, others = "%U% climbs into %T%.")
		else
			act_message(user, O, others = "%U% puts %T% into \the [src].")

	add_fingerprint(user)
	return TRUE

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
		after(nif, 0, /proc/install_nif_software, with = list(nif, MR.nif_software)) //Delay to not install software before NIF is fully installed
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

	occupant.status_set(STAT_CONFUSED, max(occupant.status_units(STAT_CONFUSED), confuse_amount))								// Apply immedeate effects
	occupant.status_at_least(STAT_BLURRY, blur_amount)

	// Vore deaths get a fake modifier labeled as such
	if(!occupant.mind)
		log_runtime("[occupant] didn't have a mind to check for vore_death, which may be problematic.")

	if(occupant.mind)
		if(occupant.original_player && ckey(occupant.mind.key) != occupant.original_player)
			log_and_message_admins("is now a cross-sleeved character. Body originally belonged to [occupant.real_name]. Mind is now [occupant.mind.name].",occupant)
		var/datum/antagonist/antag_data = SSantag.get_antag_data(occupant.mind.special_role)
		if(antag_data)
			antag_data.add_antagonist(occupant.mind)
			antag_data.place_mob(occupant)
		if(occupant.mind.antag_holder)
			occupant.mind.antag_holder.apply_antags(occupant)

	if(original_occupant)
		occupant = original_occupant

	play_sfx(src, SFX_MACHINES_MEDBAYSCANNER1, 2) // Play our sound at the end of the mind injection!
	return 1

/obj/machinery/transhuman/resleever/proc/go_out()
	var/mob/living/carbon/human/occupant = get_occupant()
	if(!occupant)
		return
	slot_remove(occupant, get_turf(src))
	set_occupant(null)
	icon_state = "implantchair"
	return

/obj/machinery/transhuman/resleever/proc/put_mob(mob/living/carbon/human/M, mob/user)
	if(!ishuman(M))
		to_chat(user, span_warning("\The [src] cannot hold this!"))
		return
	if(get_occupant())
		to_chat(user, span_warning("\The [src] is already occupied!"))
		return
	M.stop_pulling()
	if(!move_into(src, OCCUPANT_SLOT_RESLEEVER, M, user))
		to_chat(user, span_warning("\The [src] won't take [M]!"))
		return
	set_occupant(M)
	src.add_fingerprint(user)
	icon_state = "implantchair_on"
	return 1

/// Old EJECT Occupant verb.
/obj/machinery/transhuman/resleever/proc/resleever_verb_eject(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat != 0)
		return
	go_out()
	add_fingerprint(user)
	return

/// Old Move INSIDE verb.
/obj/machinery/transhuman/resleever/proc/resleever_verb_move_inside(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat != 0 || !operable())
		return
	put_mob(user, user)
	return

/// The fresh clone may be ejected now.
/obj/machinery/clonepod/transhuman/proc/allow_eject()
	eject_wait = 0
