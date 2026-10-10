/obj/machinery/protean_reconstitutor
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "protean reconstitutor"
	desc = "A complex machine that is most definitely <i>not</i> just a large tub into which one pours a large amount of untethered nanites, then adds a protean positronic brain and orchestrator, in order to reconstitute a disintegrated protean... it's complicated, really!"
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
	clicksound = SFX_MACHINES_BUTTONBEEP	//standard initialization sound
	var/dingsound = SFX_MACHINES_KITCHEN_MICROWAVE_MICROWAVE_END	//sound to play when the process is complete
	var/buzzsound = SFX_ITEMS_NIF_TONE_BAD	//sound to play when we have to abort due to loss of posibrain client

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

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with before the parent init reads them
/obj/machinery/protean_reconstitutor/Initialize(mapload)
	rel_take_all(src, nameof(component_parts))
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

/obj/machinery/protean_reconstitutor/proc/appearance_live()
	return (operable() && anchored) ? 1 : 0

/obj/machinery/protean_reconstitutor/proc/appearance_suffix()
	if(appearance_live())
		return ""
	return broken_now() ? "-broken" : "-nopower"

/obj/machinery/protean_reconstitutor/proc/appearance_brain()
	return (appearance_live() && protean_brain) ? 1 : 0

/obj/machinery/protean_reconstitutor/proc/appearance_orchestrator()
	return (appearance_live() && protean_orchestrator) ? 1 : 0

/obj/machinery/protean_reconstitutor/proc/appearance_refactory()
	return (appearance_live() && protean_refactory) ? 1 : 0

/obj/machinery/protean_reconstitutor/proc/appearance_tank_full()
	return (appearance_live() && nanomass_reserve >= nanomass_required) ? 1 : 0

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/protean_reconstitutor/draw(datum/look/look)
	..()
	look.state("[state_base][appearance_suffix()]")
	if(appearance_brain() == 1)
		look.overlay("recon-brain")
	if(appearance_orchestrator() == 1)
		look.overlay("recon-orchestrator")
	if(appearance_refactory() == 1)
		look.overlay("recon-refactory")
	if(appearance_tank_full() == 1)
		look.overlay("recon-tank_full")

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

CAPABILITIES(/obj/machinery/protean_reconstitutor)
	op("reconstitutor_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(reconstitutor_interaction_item)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), label("Remove component"),
		needs(req_is(nameof(processing_revive), FALSE, because = MSG(protean_reconstitutor/busy)), req(PROC_REF(has_components))),
		asks(/datum/prompt/choice, fields = list("title" = "Remove Component", "question" = "What component would you like to remove?", "choices" = computed(PROC_REF(component_choices)), "timeout" = 0)),
		then(PROC_REF(component_chosen)))
	op("reconstitutor_interaction_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req_is(nameof(processing_revive), FALSE, because = MSG(protean_reconstitutor/processing_revive))), then(PROC_REF(reconstitutor_interaction_hand)))
	extend("machine_panel", needs(req_is(nameof(processing_revive), FALSE, because = MSG(protean_reconstitutor/busy))))
	extend("machine_panel_close", needs(req_is(nameof(processing_revive), FALSE, because = MSG(protean_reconstitutor/busy))))
	extend("machine_deconstruct", needs(req_is(nameof(processing_revive), FALSE, because = MSG(protean_reconstitutor/busy))))

MSG_DEF_SELF(protean_reconstitutor/processing_revive, "reconstitution cycle currently in progress, please wait")

/// Old attackby; a slotted part still went on to ..(), so it falls through.
/obj/machinery/protean_reconstitutor/proc/reconstitutor_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	src.add_fingerprint(user)
	if(processing_revive)
		to_chat(user, span_notice("\The [src] is busy. Please wait for completion of previous operation."))
		playsound(src, buzzsound, 100, 1, -1)
		return OP_OK

	if(default_part_replacement(user, W))
		return OP_OK

	if(istype(W,/obj/item/mmi/digital/posibrain/nano))
		var/obj/item/mmi/digital/posibrain/nano/NB = W
		if(!NB.get_occupant()?.client)
			to_chat(user,span_warning("You cannot use an inactive positronic brain for this process."))
			return OP_OK
		to_chat(user,span_notice("You slot \the [NB] into \the [src]."))
		move_into(src, nameof(src.protean_brain), NB, user)

	if(istype(W,/obj/item/organ/internal/nano/orchestrator))
		to_chat(user,span_notice("You slot \the [W] into \the [src]."))
		move_into(src, nameof(src.protean_orchestrator), W, user)

	if(istype(W,/obj/item/organ/internal/nano/refactory))
		to_chat(user,span_notice("You slot \the [W] into \the [src]."))
		move_into(src, nameof(src.protean_refactory), W, user)

	if(istype(W,/obj/item/stack/nanopaste))
		var/obj/item/stack/nanopaste/NP = W
		if(nanomass_reserve >= nanotank_max)
			to_chat(user,span_notice("The tank is full!"))
			return OP_OK
		var/paste_gain = NP.amount * max(1,NP.mech_repair / paste_inefficiency)
		var/paste_label = "\the [NP]"
		if(!consume(NP, user))
			return OP_OK
		nanomass_reserve += paste_gain
		if(nanomass_reserve > nanotank_max)
			nanomass_reserve = nanotank_max
		to_chat(user,span_notice("You fill \the [src] with paste from [paste_label]. The display now reads [nanomass_reserve]/[nanotank_max] units."))
	return OP_DECLINE

MSG_DEF_SELF(protean_reconstitutor/busy, "%T% is busy. Please wait for completion of previous operation.")
MSG_DEF_SELF(protean_reconstitutor/no_components, "%T% does not have any protean components you can retrieve.")

/// Requirement of the wrench: a component to take out.
/obj/machinery/protean_reconstitutor/proc/has_components(datum/act/op/A)
	return (protean_brain || protean_orchestrator || protean_refactory) ? null : MSG(protean_reconstitutor/no_components)

/// The components the wrench's question offers.
/obj/machinery/protean_reconstitutor/proc/component_choices(datum/act/A)
	. = list()
	for(var/atom/movable/part in list(protean_brain, protean_orchestrator, protean_refactory))
		. += part

/// The wrench's answer: that component comes out.
/obj/machinery/protean_reconstitutor/proc/component_chosen(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/choice = A.answer?.value
	var/obj/item/tool = A.held
	if(!istype(choice) || processing_revive || choice.loc != src)
		return OP_OK
	to_chat(user, "You fish \the [choice] out of \the [src].")
	choice.forceMove(get_turf(src))
	playsound(src, tool.usesound, 50, TRUE)
	if(choice == protean_brain)
		rel_take(src, nameof(protean_brain))
	else if(choice == protean_refactory)
		rel_take(src, nameof(protean_refactory))
	else if(choice == protean_orchestrator)
		rel_take(src, nameof(protean_orchestrator))
	return OP_OK

/// Refactory materials cached across the revive (it wipes them), or null.
/obj/machinery/protean_reconstitutor/var/tmp/list/materials_cache

/// Old attack_hand (it never reached the machinery gate).
/obj/machinery/protean_reconstitutor/proc/reconstitutor_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(!protean_brain || !protean_orchestrator || !protean_refactory || (nanomass_reserve < nanomass_required))
		//no brain, no orchestrator, and/or not enough goo
		to_chat(user,span_warning("Essential components missing, or insufficient materials available!"))
		playsound(src, buzzsound, 100, 1, -1)
		return OP_OK
	if(!protean_brain.get_occupant()?.client)
		src.visible_message(span_warning("\The [src] chirps, \"Warning, no positronic neural network activity detected! Recommend removing inactive core.\""))
		return OP_OK
	else if(!processing_revive && protean_brain && protean_orchestrator && protean_refactory && (nanomass_reserve >= nanomass_required))
		//we're good, let's get recombobulating!
		act_message(user, src, others = span_notice("%U% initializes %T%. It chirps, \"Please stand by, synchronizing components... estimated time to completion: five minutes.\""))
		processing_revive = TRUE
		power_change()
		if(prob(2))
			play_sfx(src, SFX_MACHINES_BLENDER)
		else
			playsound(src, clicksound, 50, 1)
		nanomass_reserve -= nanomass_required
		log_game("PROTEAN: [key_name(user)] started a reconstitution cycle at [AREACOORD(src)]")
		after(src, base_cook_time, PROC_REF(reconstitute_begin))
	return OP_OK

/// Reconstitution step 1: the body is grown after the base cook time.
/obj/machinery/protean_reconstitutor/proc/reconstitute_begin()
	if(QDELETED(src))
		return
	if(!protean_brain || !protean_orchestrator || !protean_refactory)
		abort_reconstitution(null, "Essential components removed!")
		return
	var/mob/living/carbon/human/protean/P = new /mob/living/carbon/human/protean
	P.forceMove(src)
	P.name = "Unfinished Protean"
	P.real_name = "Unfinished Protean"
	var/list/organs = list()
	for(var/obj/item/organ/present as anything in INTERNAL_ORGANS(P))
		organs += present.organ_tag
	materials_cache = null
	if(!length(organs))
		reconstitute_organs_done(P)
		return
	after(src, per_organ_delay, PROC_REF(reconstitute_organ), with = list(P, organs, 1), keeps_dead = TRUE)

/// Reconstitution step 2: one organ per per_organ_delay.
/obj/machinery/protean_reconstitutor/proc/reconstitute_organ(mob/living/carbon/human/protean/P, list/organs, index)
	if(QDELETED(P))
		processing_revive = FALSE
		return
	var/organ = organs[index]
	var/obj/item/O = P.organ_in(organ)
	if(istype(O,/obj/item/organ/internal/nano/refactory))
		src.visible_message(span_notice("\The [src] chirps, \"Initializing refactory...\""))
		// Deleting the blank detaches it; the salvaged one takes its slot.
		replaced_by(O)
		protean_refactory.replaced(P)
		//cache our mats otherwise they get wiped by the revive
		materials_cache = protean_refactory.materials.Copy()
	if(istype(O,/obj/item/organ/internal/nano/orchestrator))
		src.visible_message(span_notice("\The [src] chirps, \"Linking nanoswarm to orchestrator...\""))
		replaced_by(O)
		protean_orchestrator.replaced(P)
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
		var/obj/item/mmi/digital/posibrain/nano/salvaged_brain = protean_brain
		own_clear(BR, nameof(BR.stored_mmi), OWN_DELETE) //toss the dummy...
		BR.slot_clear()
		salvaged_brain.forceMove(BR)
		own_move(salvaged_brain, BR, nameof(BR.stored_mmi)) //...and implant the salvaged mmi in its place (from our protean_brain)
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
			var/datum/antagonist/antag_data = SSantag.get_antag_data(P.mind.special_role)
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

		PUBLISH_LEGACY(P, /datum/notice/human_dna_finalized)

		var/datum/mind_host/core_host = get_mind_host(salvaged_brain)
		core_host.release_mind(P, "protean reconstitution")
	if(index < length(organs))
		after(src, per_organ_delay, PROC_REF(reconstitute_organ), with = list(P, organs, index + 1), keeps_dead = TRUE)
		return
	reconstitute_organs_done(P)

/obj/machinery/protean_reconstitutor/proc/reconstitute_organs_done(mob/living/carbon/human/protean/P)
	rel_take(src, nameof(protean_refactory))
	rel_take(src, nameof(protean_brain))
	rel_take(src, nameof(protean_orchestrator))
	after(src, finalize_time, PROC_REF(reconstitute_finish), with = list(P))

/// Reconstitution step 3: revive and release the finished protean.
/obj/machinery/protean_reconstitutor/proc/reconstitute_finish(mob/living/carbon/human/protean/P)
	P.revive()
	P.apply_vore_prefs()
	//run a little revive, load their prefs, and boot a new NIF on them for the finishing touches and cleanup... (yes, we need to initialize a new NIF, they don't get one from the revive process)
	//using revive is honestly a bit overkill since it kinda deletes-and-replaces most of the guts anyway (hence the cache and restore of refactory contents; otherwise they get wiped!), but it also ensures the new protean comes out in their "base form" as well as hopefully cleaning up any loose ends in the resurrection process
	var/obj/item/nif/protean/new_nif = new()
	new_nif.quick_implant(P)
	//revive complete, now restore the cached mats (if we had any)
	if(materials_cache)
		src.visible_message(span_notice("\The [src] chirps, \"Reindexing archived refactory materials storage.\""))
		for(var/obj/item/O as anything in INTERNAL_ORGANS(P))
			if(istype(O,/obj/item/organ/internal/nano/refactory))
				var/obj/item/organ/internal/nano/refactory/RF = O
				RF.materials = materials_cache.Copy()
				materials_cache = null
	//finally... drop them in front of the machine
	src.visible_message(span_notice("\The [src] chirps, \"Protean reconstitution cycle complete!\""))
	to_chat(P,span_notice("You feel your sense of self expanding, spreading out to inhabit your new \'body\'. You feel... <i><b>ALIVE!</b></i>"))
	playsound(src, dingsound, 100, 1, -1)	//soup's on!
	P.forceMove(src.loc)
	processing_revive = FALSE
	log_game("PROTEAN: [key_name(P)] was reconstituted at [AREACOORD(src)]")
	changed(src)

/// Stop a cycle cleanly: salvaged components go back into the tank, the
/// unfinished body is dissolved, the nanites are refunded and the machine is
/// free again (bug 19: it used to stay busy forever).
/obj/machinery/protean_reconstitutor/proc/abort_reconstitution(mob/living/carbon/human/P, reason)
	visible_message(span_warning("\The [src] buzzes, \"[reason] Aborting cycle!\""))
	playsound(src, buzzsound, 100, 1, -1)
	log_game("PROTEAN: reconstitution aborted at [AREACOORD(src)]: [reason]")
	if(P)
		for(var/obj/item/organ/O in list(protean_refactory, protean_orchestrator))
			if(O.owner != P)
				continue
			// A ledger move out of its limb: the detach hook clears the caches.
			var/atom/holder = O.loc
			holder.slot_remove(O, src, null, LEDGER_MOVE_FORCED)
		if(protean_brain && protean_brain.loc != src)
			protean_brain.forceMove(src)
		spent(P)
	nanomass_reserve = min(nanotank_max, nanomass_reserve + nanomass_required)
	processing_revive = FALSE
	changed(src)

/obj/machinery/protean_reconstitutor/ownership()
	. = ..()
	. += owns(nameof(protean_brain), policy = OWN_CONTAINED)
	. += owns(nameof(protean_orchestrator), policy = OWN_CONTAINED)
	. += owns(nameof(protean_refactory), policy = OWN_CONTAINED)
