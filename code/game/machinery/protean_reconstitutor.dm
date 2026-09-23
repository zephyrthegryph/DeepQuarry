/obj/machinery/protean_reconstitutor
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "protean reconstitutor"
	desc = "A complex machine that is most definitely <i>not</i> just a large tub into which one pours a large amount of untethered nanites, then adds a protean positronic brain and orchestrator, in order to reconstitute a disintegrated protean... it's complicated, really!"
	description_info = "Use a protean positronic brain, orchestrator, refactory, and nanopaste to \'fill\' the machine, then interact with it once it's ready. Protean components can be retrieved using a wrench, but any nanopaste inserted will be converted, cannot be reclaimed, and will be lost if the machine is disassembled!"
	icon = 'icons/obj/protean_recon.dmi'
	icon_state = "recon-nopower"
	var/state_base = "recon"
	anchored = TRUE
	density = TRUE
	power_channel = EQUIP
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 1000
	var/processing_revive = FALSE
	clicksound = 'sound/machines/buttonbeep.ogg'	//standard initialization sound
	var/dingsound = 'sound/machines/kitchen/microwave/microwave-end.ogg'	//sound to play when the process is complete
	var/buzzsound = 'sound/items/nif_tone_bad.ogg'	//sound to play when we have to abort due to loss of posibrain client

	//vars for basic functionality
	var/obj/item/mmi/digital/posibrain/nano/protean_brain = null	//only allow protean brains, no midround upgrades to bypass the whitelist!
	var/obj/item/organ/internal/nano/orchestrator/protean_orchestrator = null	//essential
	var/obj/item/organ/internal/nano/refactory/protean_refactory = null	//not essential, but nice to have; lets us transfer stored materials
	var/nanomass_reserve = 0		//starting reserve - will be wiped if it's deconstructed!
	var/nanotank_max = 300			//how much we can store at once, higher = better
	var/nanomass_required = 150		//how much we need in order to make a new body, non-adjustable
	var/paste_inefficiency = 5		//divisor to mech_repair value of paste added; higher = less effective; adv paste is +40 reserve at base, or +200 at max!

	//time vars
	var/base_cook_time = 150 SECONDS	//how long to initially delay before starting the overall cooking cycle
	var/per_organ_delay = 5 SECONDS	//how long to delay the cycle per organ and per synch step (multiply by three to get time for all three organs), then add base cook time for total time
	var/finalize_time = 135 SECONDS	//finally, how long we need before popping them out of the tank

	//component vars
	circuit = /obj/item/circuitboard/protean_reconstitutor

// This board declares no req_components, so its default parts are declared
// here instead of read off the board (roadmap C6): still resolved lazily
// into latent entries in CONTAINER_SLOT_INTERNALS, not eager objects.
/obj/machinery/protean_reconstitutor/latent_generator()
	// `list(circuit = 1, ...)` would use the literal identifier "circuit" as
	// the key (DM's named-argument list syntax), not circuit's value -- the
	// key must be set by index instead to be the board's actual type path.
	var/list/gen = list(
		/obj/item/stock_parts/matter_bin = 1,
		/obj/item/stock_parts/manipulator = 1,
		/obj/item/stock_parts/console_screen = 1,
		/obj/item/stack/cable_coil = 5,
	)
	gen[circuit] = 1
	return gen

/obj/machinery/protean_reconstitutor/Initialize(mapload)
	component_parts = null
	RefreshParts()
	. = ..()

/obj/machinery/protean_reconstitutor/RefreshParts()
	//total paste storage cap (300 * the rating, straightforward)
	var/store_rating = initial(nanotank_max)
	for(var/obj/item/stock_parts/matter_bin/MB in slot_contents(CONTAINER_SLOT_INTERNALS))
		store_rating = store_rating * MB.rating
	for(var/datum/latent_entry/entry as anything in latent_entries(CONTAINER_SLOT_INTERNALS))
		if(ispath(entry.path, /obj/item/stock_parts/matter_bin))
			var/rating = dq_type_var(entry.path, "rating")
			for(var/i in 1 to entry.count)
				store_rating = store_rating * rating
	nanotank_max = store_rating

	//inefficiency of adding paste (amount of uses * (mech_repair / inefficiency)); most complex, good way to get good bang for your buck tho
	var/paste_rating = initial(paste_inefficiency)
	paste_rating -= (get_part_rating(/obj/item/stock_parts/manipulator) - get_part_count(/obj/item/stock_parts/manipulator))
	paste_inefficiency = paste_rating
	..()

/obj/machinery/protean_reconstitutor/update_icon()
	cut_overlays()
	if(stat & (NOPOWER|BROKEN) || !anchored)
		if(stat & BROKEN)
			icon_state = "[state_base]-broken"
		else
			icon_state = "[state_base]-nopower"
		return
	icon_state = state_base
	if(protean_brain)
		add_overlay("[state_base]-brain")
	if(protean_orchestrator)
		add_overlay("[state_base]-orchestrator")
	if(protean_refactory)
		add_overlay("[state_base]-refactory")
	if(nanomass_reserve >= nanomass_required)
		add_overlay("[state_base]-tank_full")

/obj/machinery/protean_reconstitutor/examine()
	. = ..()
	if(protean_refactory)
		. += "A protean refactory is present."
	if(protean_orchestrator)
		. += "A protean orchestrator is present."
	if(protean_brain)
		. += "It currently has a protean positronic brain."
		if(!protean_brain.get_occupant()?.client)
			. += span_warning("The positronic brain appears to be inactive!")
	. += "The readout shows that it has [nanomass_reserve] units of nanites ready for use. It requires [nanomass_required] per \'revive\' process, and has a maximum capacity of [nanotank_max] units."

/obj/machinery/protean_reconstitutor/attackby(obj/item/W as obj, mob/user as mob)
	src.add_fingerprint(user)
	if(processing_revive)
		to_chat(user, span_notice("\The [src] is busy. Please wait for completion of previous operation."))
		playsound(src, buzzsound, 100, 1, -1)
		return

	if(default_part_replacement(user, W))
		return

	if(istype(W,/obj/item/mmi/digital/posibrain/nano))
		var/obj/item/mmi/digital/posibrain/nano/NB = W
		if(!NB.get_occupant()?.client)
			to_chat(user,span_warning("You cannot use an inactive positronic brain for this process."))
			return
		to_chat(user,span_notice("You slot \the [NB] into \the [src]."))
		user.drop_from_inventory(NB)
		NB.loc = src
		protean_brain = NB

	if(istype(W,/obj/item/organ/internal/nano/orchestrator))
		to_chat(user,span_notice("You slot \the [W] into \the [src]."))
		user.drop_from_inventory(W)
		W.loc = src
		protean_orchestrator = W

	if(istype(W,/obj/item/organ/internal/nano/refactory))
		to_chat(user,span_notice("You slot \the [W] into \the [src]."))
		user.drop_from_inventory(W)
		W.loc = src
		protean_refactory = W

	if(istype(W,/obj/item/stack/nanopaste))
		var/obj/item/stack/nanopaste/NP = W
		if(nanomass_reserve >= nanotank_max)
			to_chat(user,span_notice("The tank is full!"))
			return
		nanomass_reserve += NP.amount * max(1,NP.mech_repair / paste_inefficiency)
		if(nanomass_reserve > nanotank_max)
			nanomass_reserve = nanotank_max
		to_chat(user,span_notice("You fill \the [src] with paste from \the [NP]. The display now reads [nanomass_reserve]/[nanotank_max] units."))
		qdel(NP)
	update_icon()
	return ..()

/obj/machinery/protean_reconstitutor/wrench_act(mob/user, obj/item/tool)
	if(processing_revive)
		to_chat(user, span_notice("\The [src] is busy. Please wait for completion of previous operation."))
		return ITEM_INTERACT_BLOCKING
	if(!protean_brain && !protean_orchestrator && !protean_refactory)
		to_chat(user, "\The [src] does not have any protean components you can retrieve.")
		return ITEM_INTERACT_BLOCKING
	var/atom/movable/choice = tgui_input_list(user, "What component would you like to remove?", "Remove Component", list(protean_brain, protean_orchestrator, protean_refactory))
	if(!choice)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, "You fish \the [choice] out of \the [src].")
	choice.forceMove(get_turf(src))
	playsound(src, tool.usesound, 50, TRUE)
	if(choice == protean_brain)
		protean_brain = null
	else if(choice == protean_refactory)
		protean_refactory = null
	else if(choice == protean_orchestrator)
		protean_orchestrator = null
	return ITEM_INTERACT_SUCCESS

/obj/machinery/protean_reconstitutor/screwdriver_act(mob/user, obj/item/tool)
	if(processing_revive)
		to_chat(user, span_notice("\The [src] is busy. Please wait for completion of previous operation."))
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/protean_reconstitutor/crowbar_act(mob/user, obj/item/tool)
	if(processing_revive)
		to_chat(user, span_notice("\The [src] is busy. Please wait for completion of previous operation."))
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/protean_reconstitutor/attack_hand(mob/user as mob)
	if(!protean_brain || !protean_orchestrator || !protean_refactory || (nanomass_reserve < nanomass_required))
		//no brain, no orchestrator, and/or not enough goo
		to_chat(user,span_warning("Essential components missing, or insufficient materials available!"))
		playsound(src, buzzsound, 100, 1, -1)
		update_icon()
		return
	if(processing_revive)
		//we're currently processing a patient, chill out!
		src.visible_message(span_notice("\The [src] chirps, \"Reconstitution cycle currently in progress, please wait!\""))
		playsound(src, buzzsound, 100, 1, -1)
		return
	if(!protean_brain.get_occupant()?.client)
		src.visible_message(span_warning("\The [src] chirps, \"Warning, no positronic neural network activity detected! Recommend removing inactive core.\""))
		return
	else if(!processing_revive && protean_brain && protean_orchestrator && protean_refactory && (nanomass_reserve >= nanomass_required))
		//we're good, let's get recombobulating!
		src.visible_message(span_notice("[user] initializes \the [src]. It chirps, \"Please stand by, synchronizing components... estimated time to completion: five minutes.\""))
		processing_revive = TRUE
		power_change()
		if(prob(2))
			playsound(src, 'sound/machines/blender.ogg', 50, 1)
		else
			playsound(src, clicksound, 50, 1)
		nanomass_reserve -= nanomass_required
		log_game("PROTEAN: [key_name(user)] started a reconstitution cycle at [AREACOORD(src)]")
		sleep(base_cook_time)
		if(QDELETED(src))
			return
		if(!protean_brain || !protean_orchestrator || !protean_refactory)
			abort_reconstitution(null, "Essential components removed!")
			return
		var/mob/living/carbon/human/protean/P = new /mob/living/carbon/human/protean
		var/mats_cached
		var/list/materials_cache
		P.loc = src
		P.name = "Unfinished Protean"
		P.real_name = "Unfinished Protean"
		for(var/organ in P.internal_organs_by_name)
			sleep(per_organ_delay)
			if(QDELETED(src))
				return
			var/obj/item/O = P.internal_organs_by_name[organ]
			if(istype(O,/obj/item/organ/internal/nano/refactory))
				src.visible_message(span_notice("\The [src] chirps, \"Initializing refactory...\""))
				P.internal_organs_by_name.Remove(O)
				P.contents.Remove(O)
				qdel(O)
				P.internal_organs_by_name.Add(list(O_FACT = protean_refactory))
				P.internal_organs.Add(protean_refactory)
				//cache our mats otherwise they get wiped by the revive
				materials_cache = protean_refactory.materials.Copy()
				mats_cached = TRUE
				protean_refactory.loc = P
			if(istype(O,/obj/item/organ/internal/nano/orchestrator))
				src.visible_message(span_notice("\The [src] chirps, \"Linking nanoswarm to orchestrator...\""))
				P.internal_organs_by_name.Remove(O)
				P.internal_organs.Remove(O)
				P.contents.Remove(O)
				qdel(O)
				P.internal_organs_by_name.Add(list(O_ORCH = protean_orchestrator))
				P.internal_organs.Add(protean_orchestrator)
				protean_orchestrator.loc = P
			if(istype(O,/obj/item/organ/internal/mmi_holder/posibrain/nano))
				src.visible_message(span_notice("\The [src] chirps, \"Synchronizing positronic neural architecture...\""))
				//on the offchance our client blipped before getting to this step, abort, schloop the organs back into the machine, dissolve the body, and refund the nanos
				if(!protean_brain.get_occupant()?.client)
					abort_reconstitution(P, "No positronic neural activity detected!")
					return
				var/client/posibrain_client = protean_brain.get_occupant().client
				var/datum/data/record/record_found = find_general_record("name", posibrain_client.prefs.read_preference(/datum/preference/name/real_name))
				if(!record_found)
					abort_reconstitution(P, "No crew record matches this neural architecture!")
					return
				var/charjob = record_found.fields["real_rank"]
				var/obj/item/organ/internal/mmi_holder/posibrain/nano/BR = O
				BR.stored_mmi = null	//toss the dummy...
				BR.contents.Cut()
				BR.stored_mmi = protean_brain	//...and implant the salvaged mmi in its place
				BR.contents.Add(protean_brain)
				var/picked_ckey = posibrain_client.ckey
				var/picked_slot = posibrain_client.prefs.default_slot
				if(P.dna)
					P.dna.ResetUIFrom(P)
					P.sync_dna_traits(FALSE) // Traitgenes Sync traits to genetics if needed
					P.sync_organ_dna()
				P.initialize_vessel()

				if(P.mind)
					P.mind.loaded_from_ckey = picked_ckey
					P.mind.loaded_from_slot = picked_slot
					var/datum/antagonist/antag_data = SSantag_job.get_antag_data(P.mind.special_role)
					if(antag_data)
						antag_data.add_antagonist(P.mind)
						antag_data.place_mob(P)
					P.mind.assigned_role = charjob
					P.mind.role_alt_title = SSjob.get_player_alt_title(P, charjob)

				// Languages come with the character's identity when the mind moves in.
				// migrated language_custom_keys
				var/list/_posi_lang_custom = posibrain_client.prefs.read_preference(/datum/preference/language_custom_keys)
				for(var/key in _posi_lang_custom)
					if(_posi_lang_custom[key])
						var/datum/language/keylang = GLOB.all_languages[_posi_lang_custom[key]]
						if(keylang)
							P.language_keys[key] = keylang

				if(posibrain_client.prefs.read_preference(/datum/preference/text/human/preferred_language))
					var/datum/language/def_lang = GLOB.all_languages[posibrain_client.prefs.read_preference(/datum/preference/text/human/preferred_language)]
					if(def_lang)
						P.default_language = def_lang

				SEND_SIGNAL(P, COMSIG_HUMAN_DNA_FINALIZED)

				var/datum/component/mind_host/core_host = get_mind_host(protean_brain)
				core_host.release_mind(P, "protean reconstitution")
				protean_brain.loc = BR
		protean_refactory = null
		protean_brain = null
		protean_orchestrator = null
		sleep(finalize_time)	//let 'em cook a tiny bit longer
		P.revive()
		P.apply_vore_prefs()
		//run a little revive, load their prefs, and boot a new NIF on them for the finishing touches and cleanup... (yes, we need to initialize a new NIF, they don't get one from the revive process)
		//using revive is honestly a bit overkill since it kinda deletes-and-replaces most of the guts anyway (hence the cache and restore of refactory contents; otherwise they get wiped!), but it also ensures the new protean comes out in their "base form" as well as hopefully cleaning up any loose ends in the resurrection process
		var/obj/item/nif/protean/new_nif = new()
		new_nif.quick_implant(P)
		//revive complete, now restore the cached mats (if we had any)
		if(mats_cached == TRUE)
			src.visible_message(span_notice("\The [src] chirps, \"Reindexing archived refactory materials storage.\""))
			for(var/organ in P.internal_organs_by_name)
				var/obj/item/O = P.internal_organs_by_name[organ]
				if(istype(O,/obj/item/organ/internal/nano/refactory))
					var/obj/item/organ/internal/nano/refactory/RF = O
					RF.materials = materials_cache.Copy()
					materials_cache.Cut()
					mats_cached = FALSE
		//finally... drop them in front of the machine
		src.visible_message(span_notice("\The [src] chirps, \"Protean reconstitution cycle complete!\""))
		to_chat(P,span_notice("You feel your sense of self expanding, spreading out to inhabit your new \'body\'. You feel... <i><b>ALIVE!</b></i>"))
		playsound(src, dingsound, 100, 1, -1)	//soup's on!
		P.loc = src.loc
		processing_revive = FALSE
		log_game("PROTEAN: [key_name(P)] was reconstituted at [AREACOORD(src)]")
		update_icon()
	update_icon()

/// Stop a cycle cleanly: salvaged components go back into the tank, the
/// unfinished body is dissolved, the nanites are refunded and the machine is
/// free again (bug 19: it used to stay busy forever).
/obj/machinery/protean_reconstitutor/proc/abort_reconstitution(mob/living/carbon/human/P, reason)
	visible_message(span_warning("\The [src] buzzes, \"[reason] Aborting cycle!\""))
	playsound(src, buzzsound, 100, 1, -1)
	log_game("PROTEAN: reconstitution aborted at [AREACOORD(src)]: [reason]")
	if(P)
		for(var/obj/item/organ/O in list(protean_refactory, protean_orchestrator))
			if(O.loc != P)
				continue
			P.internal_organs -= O
			P.internal_organs_by_name -= O.organ_tag
			O.owner = null
			O.forceMove(src)
		if(protean_brain && protean_brain.loc != src)
			protean_brain.forceMove(src)
		qdel(P)
	nanomass_reserve = min(nanotank_max, nanomass_reserve + nanomass_required)
	processing_revive = FALSE
	update_icon()
