/obj/item/organ
	name = "organ"
	icon = 'icons/obj/surgery.dmi'
	germ_level = 0
	drop_sound = SFX_ITEMS_DROP_FLESH
	pickup_sound = SFX_ITEMS_PICKUP_FLESH

	// Strings.
	var/organ_tag = "organ"				// Unique identifier.
	var/parent_organ = BP_TORSO			// Organ holding this object.

	// Status tracking.
	var/vital							// Lose a vital limb, die immediately.
	var/stapled_nerves = FALSE

	// Reference data.
	var/mob/living/carbon/human/owner	// Current mob owning the organ.
	var/list/transplant_data			// Transplant match data.
	var/list/autopsy_data		// Trauma data for forensics.
	var/list/trace_chemicals	// Traces of chemicals in the organ.
	var/datum/organ_data/data = new()	// Stores data for appearance and investigation

	// Damage vars.
	var/min_bruised_damage = 10			// Damage before considered bruised
	var/min_broken_damage = 60 // Damage before becoming broken Flat doubling of all min_broken_damage
	var/can_reject = 1					// Can this organ reject?
	var/rejecting						// Is this organ already being rejected?
	var/decays = TRUE					// Can this organ decay at all?
	var/preserved = 0					// If this is 1, prevents organ decay.

	// Language vars. Putting them here in case we decide to do something crazy with sign-or-other-nonverbal languages.
	var/list/will_assist_languages
	var/list/datum/language/assists_languages

	// Organ verb vars.
	var/list/organ_verbs		// Verbs added by the organ when present in the body.
	var/list/target_parent_classes	// Is the parent supposed to be organic, robotic, assisted?
	var/forgiving_class = TRUE	// Will the organ give its verbs when it isn't a perfect match? I.E., assisted in organic, synthetic in organic.

	var/butcherable = TRUE
	var/meat_type	// What does butchering, if possible, make?


/obj/item/organ
	/// Organ condition bits (ORGAN_DEAD, ORGAN_BROKEN, ...).
	var/status = 0
	/// Current damage to the organ.
	var/damage = 0
	/// Damage cap.
	var/max_damage = null
	/// ORGAN_FLESH / ORGAN_ASSISTED / ORGAN_ROBOT / ...
	var/robotic = 0

// The organ's state is tracked: written through set_status(), set_damage(), set_max_damage() and set_robotic(), which publish the write.
TRACKED(/obj/item/organ, status)
TRACKED(/obj/item/organ, damage)
TRACKED(/obj/item/organ, max_damage)
TRACKED(/obj/item/organ, robotic)


// afflictions on the organ are cured; organ mods removed.
/obj/item/organ/on_destroy(force)
	handle_organ_mod_special(TRUE)
	// Afflictions located on this organ die with it, attached or detached.
	if(owner?.body)
		for(var/datum/affliction/A as anything in owner.body.afflictions_at(src))
			A.cure()
	..()

/obj/item/organ/proc/update_health()
	return


/obj/item/organ/Initialize(mapload, internal)
	. = ..()
	if(isliving(loc))
		var/mob/living/born_in = loc
		src.w_class = max(src.w_class + mob_size_difference(born_in.mob_size, MOB_MEDIUM), 1) //smaller mobs have smaller organs.
		// Born inside a mob: take our place in its body (sets `owner`).
		place_in_body(born_in)

	if(!max_damage)
		set_max_damage(min_broken_damage * 2)
	if(iscarbon(owner))
		var/mob/living/carbon/C = owner
		if(!C.species)
			data.setup_from_species(GLOB.all_species[SPECIES_HUMAN])
		if(owner.dna)
			data.setup_from_dna(C.dna)
			data.setup_from_species(C.species)
		else
			log_runtime("[src] at [loc] spawned without a proper DNA.")
		var/mob/living/carbon/human/H = C
		if(istype(H) && data)
			add_blooddna_organ(data)
	else
		data.setup_from_species(GLOB.all_species["Human"])

	handle_organ_mod_special()

/obj/item/organ/proc/set_initial_meat()
	if(owner)
		if(!meat_type)
			// D25: the part's own biology decides what it's made of, not the owner's.
			if(is_robotic())
				meat_type = /obj/item/stack/material/steel
			else if(ishuman(owner))
				var/mob/living/carbon/human/H = owner
				meat_type = H?.species?.meat_type

			if(!meat_type)
				if(owner.meat_type)
					meat_type = owner.meat_type
				else
					meat_type = /obj/item/reagent_containers/food/snacks/meat

/obj/item/organ/proc/set_dna(datum/dna/new_dna)
	if(new_dna)
		data.setup_from_dna(new_dna)
		forensic_data?.clear_blooddna()
		add_blooddna_organ(data)

// --- Construction predicates (P2-S2) ------------------------------------------
// One vocabulary for "what is this part built from?" instead of raw
// `robotic >= ORGAN_*` comparisons with mixed thresholds.

/// Fully prosthetic: robot, lifelike or nanoform. No pulse, no blood, repaired
/// with tools rather than medicine.
/obj/item/organ/proc/is_robotic()
	return ORGAN_ROBOT <= robotic // the predicate itself

/// Has any mechanical component: assisted (pacemaker-style) or fully robotic.
/obj/item/organ/proc/is_assisted()
	return ORGAN_ASSISTED <= robotic // the predicate itself

/// Made of nanites (protean).
/obj/item/organ/proc/is_nanoform()
	return ORGAN_NANOFORM <= robotic // the predicate itself

/// Plain flesh: no mechanical parts at all.
/obj/item/organ/proc/is_organic()
	return ORGAN_ASSISTED > robotic // the predicate itself

/// The part's biology (BIOLOGY_* flag) for afflictions and treatment tags.
/// Assisted parts are still organic tissue.
/obj/item/organ/proc/biology()
	if(is_nanoform())
		return BIOLOGY_NANOFORM
	if(is_robotic())
		return BIOLOGY_SYNTHETIC
	return BIOLOGY_ORGANIC

/obj/item/organ/proc/die()
	if(!is_robotic())
		set_status(status | ORGAN_DEAD)
	saturate_damage()
	handle_organ_mod_special(TRUE)
	if(owner && vital)
		owner.can_defib = FALSE
		owner.death()
	loose_refresh()

/// Bring the organ's integrity to max_damage (death). Internal organs do it
/// with a necrosis lesion (see organ_integrity.dm).
/obj/item/organ/proc/saturate_damage()
	set_damage(max_damage)

/obj/item/organ/adjust_germ_level(amount)		// Unless you're setting germ level directly to 0, use this proc instead
	germ_level = CLAMP(germ_level + amount, 0, INFECTION_LEVEL_MAX)
	if(ishuman(owner))
		var/mob/living/carbon/human/H = owner
		after(H, 0, TYPE_PROC_REF(/mob/living/carbon/human, organs_refresh), key = "organs_refresh")

/// The organ's work over `cycles` Life cycles of body time: the body's organ clock calls it for organs in a body
/// (body_clock.dm), the loose-organ clock for the rest (attach.dm). Effects scale by `cycles`; nothing counts ticks.
/obj/item/organ/proc/organ_tick(cycles)

	//dead already, no need for more processing
	if(status & ORGAN_DEAD)
		return
	// Don't process if we're in a freezer, an MMI or a stasis bag.or a freezer or something I dunno
	if(istype(loc,/obj/item/mmi))
		return
	if(preserved)
		return

	//check if we've hit max_damage
	if(damage >= max_damage)
		die()

	handle_organ_proc_special(cycles)

	if(!owner)
		tick_detached_afflictions()

	//Process infections
	if(is_robotic() || (istype(owner) && (owner.species && (owner.species.flags & (IS_PLANT | NO_INFECT)))))
		germ_level = 0
		return

	if(!owner && reagents)
		var/datum/reagent/blood/B = locate_in_list(reagents.reagent_list, /datum/reagent/blood)
		if(B && prob(40) && !isbelly(loc))
			reagents.remove_reagent(REAGENT_ID_BLOOD,0.1)
			blood_splatter(src,B,1)
		if(CONFIG_GET(flag/organs_decay) && decays)
			var/obj/item/organ/internal/rotting = src
			if(istype(rotting))
				rotting.apply_lesion_damage(rand(1,3), /datum/affliction/lesion/necrosis, TRUE)
		adjust_germ_level(cycles) //If something knocked a limb off, usually it'll have 100ish germs. This means you have ~30 minutes to get it back on before it becomes necrotic.
		if(germ_level >= INFECTION_LEVEL_THREE)
			die()

	else if(owner && owner?.body_temperature() >= 170)	//cryo stops germs from moving and doing their bad stuffs
		//** Handle antibiotics and curing infections
		handle_antibiotics(cycles)
		handle_rejection(cycles)
		handle_germ_effects(cycles)
		// bridge germ_level into the wound_infection condition.
		// Once germs cross INFECTION_LEVEL_ONE we spawn the condition,
		// which then handles symptoms / progression / chem cure on its
		// own. germ_level continues to evolve underneath as the hidden
		// physics; the condition is the player-facing surface.
		dq_bridge_germ_to_condition()

/obj/item/organ/examine(mob/user)
	. = ..()

	//Descriptors for 'status of the limb'
	if(status & ORGAN_DEAD) //Can happen for other reasons than infection.
		. += span_bolddanger("The [name] is dead.")
	if(status & ORGAN_MUTATED)
		. += span_danger("The [name] is mutated and deformed.")
	if(is_fractured())
		. += span_danger("The [name] is broken.")

	//Descriptors for 'how infected is this organ'
	if(germ_level < INFECTION_LEVEL_ONE)
		return
	switch(germ_level)
		if(INFECTION_LEVEL_ONE to INFECTION_LEVEL_TWO - 1)
			. += span_warning("Signs of a minor infection are apparent.")
		if(INFECTION_LEVEL_TWO to INFECTION_LEVEL_THREE - 1)
			. += span_boldwarning("Signs of a moderate infection are apparent.")
		if(INFECTION_LEVEL_THREE to INFINITY)
			. += span_bolddanger("Necrosis has set in.")

/obj/item/organ/get_mechanics_info(list/additional_information)
	if(!additional_information)
		additional_information = list()
	if(butcherable && meat_type)
		additional_information += "Can be butchered with use of any sharp and edged object."
	if(germ_level)
		additional_information += "Can be washed in a sink, shower, or sprayed with space cleaner to clean infection. This will not bring it back from death, however."
	if(status & ORGAN_DEAD)
		additional_information += "Can have five units of peridaxon applied to bring the organ back from death. This will not cure any infection, however."
	. = ..(additional_information)
	return .

/obj/item/organ/get_description_antag()
	. = ..()
	if(butcherable && meat_type)
		. += "Can be butchered with use of any sharp and edged object, allowing for quick disposal of evidence."
	return .

//A little wonky: internal organs stop calling this (they return early in process) when dead, but external ones cause further damage when dead
/obj/item/organ/proc/handle_germ_effects(cycles)
	//** Handle the effects of infections
	if(is_robotic()) //Just in case!
		germ_level = 0
		return 0

	var/antibiotics = owner ? owner.factor(BF_ANTIMICROBIAL) : 0

	// the germ_level toxin-damage path is replaced by the
	// wound_infection condition (code/modules/medical/...).
	// We keep germ_level itself for surgery sanitation, antibiotic
	// progression, and necrosis-by-germs (still ticks below), but the
	// damage-doing side is now a condition that presents with symptoms,
	// can cascade, and reacts to specific reagents.

	if (germ_level > 0 && germ_level < INFECTION_LEVEL_ONE/2 && prob(min(100, 30 * cycles)))
		adjust_germ_level(-antibiotics)

	/// Germ Accumulation

	//Dead organs accumulate germs indefinitely
	if(status & ORGAN_DEAD)
		adjust_germ_level(cycles)

	//Half of level 1 is growing but harmless
	if (germ_level >= INFECTION_LEVEL_ONE/2)
		// Growth is a rate proportional to the germs (exponential): germ_level / 600 a cycle, the mean of the old
		// prob(germ_level / 6) roll of one. Ambient to INFECTION_LEVEL_TWO in about 15 minutes.
		if(!antibiotics)
			adjust_germ_level(germ_level / 600 * cycles)

	//Level 1 qualifies for specific organ processing effects
	if(germ_level >= INFECTION_LEVEL_ONE)
		. = 1 //Organ qualifies for effect-specific processing
		var/fever_temperature = owner?.species.heat_discomfort_level * 1.10 //Heat discomfort level plus 10%
		if(owner?.body_temperature() < fever_temperature)
			owner?.adjust_bodytemperature(min(0.2,(fever_temperature - owner?.body_temperature()) / 10) * cycles) //Will usually climb by 0.2 a cycle, else 10% of the difference if less

	//Level two qualifies for further processing effects
	if (germ_level >= INFECTION_LEVEL_TWO)
		. = 2 //Organ qualifies for effect-specific processing
		//No particular effect on the general 'organ' at 3

	//Level three qualifies for significant growth and further effects
	if (germ_level >= INFECTION_LEVEL_THREE && antibiotics < ANTIBIO_OD)
		. = 3 //Organ qualifies for effect-specific processing
		adjust_germ_level(7.5 * cycles) //Germ_level increases without overdose of antibiotics (the mean of rand(5, 10) a cycle)

/obj/item/organ/proc/handle_rejection(cycles)
	// Process unsuitable transplants. TODO: consider some kind of
	// immunosuppressant that changes transplant data to make it match.
	if(data && can_reject)
		if(!rejecting)
			if(blood_incompatible(data.b_type, owner.dna.b_type, data.get_species_name(), owner.species.name)) // Process species by name.
				rejecting = 1
		else
			rejecting += cycles // Rejection severity grows with the time it has gone on, in cycles.
			// What the old code did every tenth cycle, spread over each cycle (the means of its rolls).
			switch(rejecting)
				if(0 to 50)
					adjust_germ_level(0.1 * cycles)
				if(50 to 200)
					adjust_germ_level(0.15 * cycles)
				if(200 to 500)
					adjust_germ_level(0.25 * cycles)
				if(500 to INFINITY)
					adjust_germ_level(0.4 * cycles)
					owner.reagents.add_reagent(REAGENT_ID_TOXIN, 0.15 * cycles)

/obj/item/organ/proc/receive_chem(chemical as obj)
	return 0

/obj/item/organ/proc/remove_rejuv()
	spent(src)

/obj/item/organ/proc/rejuvenate(ignore_prosthetic_prefs)
	set_damage(0)
	set_status(0)
	germ_level = 0
	if(owner)
		handle_organ_mod_special()
	if(!ignore_prosthetic_prefs && owner && owner.client && owner.client.prefs && owner.client.prefs.read_preference(/datum/preference/name/real_name) == owner.real_name)
		var/list/organ_data = owner.client.prefs.read_preference(/datum/preference/organ_data)
		var/status = organ_data?[organ_tag]
		if(status == FBP_ASSISTED)
			mechassist()
		else if(status == FBP_MECHANICAL)
			robotize()

/obj/item/organ/proc/is_damaged()
	return damage > 0

/obj/item/organ/proc/is_bruised()
	return damage >= min_bruised_damage

/// Is this organ's bone fractured? Only limbs have bones to break
/// (/obj/item/organ/external/is_fractured()).
/obj/item/organ/proc/is_fractured()
	return FALSE

/obj/item/organ/proc/is_broken()
	return (damage >= min_broken_damage || (status & ORGAN_CUT_AWAY) || is_fractured())

//Germs
/obj/item/organ/proc/handle_antibiotics(cycles)
	if(istype(owner))
		var/antibiotics = owner.factor(BF_ANTIMICROBIAL)

		if (!germ_level || antibiotics < ANTIBIO_NORM)
			return

		if (germ_level < INFECTION_LEVEL_ONE)
			germ_level = 0	//cure instantly
		else if (germ_level < INFECTION_LEVEL_TWO)
			adjust_germ_level(-antibiotics * 4 * cycles)	//at germ_level < 500, this should cure the infection in a minute
		else if (germ_level < INFECTION_LEVEL_THREE)
			adjust_germ_level(-antibiotics * 2 * cycles) //at germ_level < 1000, this will cure the infection in 5 minutes
		else
			adjust_germ_level(-antibiotics * cycles)	// You waited this long to get treated, you don't really deserve this organ

//Adds autopsy data for used_weapon.
/obj/item/organ/proc/add_autopsy_data(used_weapon, damage)
	var/datum/autopsy_data/W = LAZYACCESS(autopsy_data, used_weapon)
	if(!W)
		W = new()
		W.weapon = used_weapon
		rel_add(src, nameof(autopsy_data), W, used_weapon)

	W.hits += 1
	W.damage += damage
	EXPIRY_STAMP(W, time_inflicted, CLOCK_WORLD)

/// Organs are anatomy, not item integrity: /atom/take_damage() does nothing
/// to them. A patient's organs are harmed through injure() (internal organs:
/// lesions, code/modules/body/parts/organ_integrity.dm; limbs: wounds,
/// organ_external.dm) and healed through mend().
/obj/item/organ/take_damage(damage_amount, damage_type, damage_flag, sound_effect, attack_dir, armour_penetration)
	return 0

/// EMP harm to a prosthetic organ's own hardware. Body-internal.
/obj/item/organ/proc/suffer_emp_damage(amount)
	return

/obj/item/organ/internal/suffer_emp_damage(amount)
	apply_lesion_damage(amount, null, TRUE)

/obj/item/organ/external/suffer_emp_damage(amount)
	apply_wound_damage(amount, 0)

/obj/item/organ/proc/bruise()
	set_damage(max(damage, min_bruised_damage))

/obj/item/organ/proc/break_organ() //can't name this break because it's a reserved word
	set_damage(max(damage, min_broken_damage))

/obj/item/organ/proc/robotize() //Being used to make robutt hearts, etc
	set_robotic(ORGAN_ROBOT)
	src.set_status(src.status & ~ORGAN_BLEEDING)
	src.set_status(src.status & ~ORGAN_CUT_AWAY)
	shed_mismatched_afflictions()

/// After a biology change, cure the afflictions on this organ that can no
/// longer exist on it (organic wounds on a prosthetic, and so on).
/obj/item/organ/proc/shed_mismatched_afflictions()
	if(!owner?.body)
		return
	var/part_biology = owner.body.biology_of(src)
	for(var/datum/affliction/A as anything in afflictions_here())
		if(!(A.biology & part_biology))
			log_game("BODY: [key_name(owner)] [A.type] cured on [name]: biology changed.")
			A.cure()

/obj/item/organ/proc/mechassist() //Used to add things like pacemakers, etc
	robotize()
	set_robotic(ORGAN_ASSISTED)
	min_bruised_damage = 15
	min_broken_damage = 60 // Flat doubling of all min_broken_damage
	butcherable = FALSE

/obj/item/organ/proc/digitize() //Used to make the circuit-brain. On this level in the event more circuit-organs are added/tweaks are wanted.
	robotize()

/// A pulse reaches what the organ holds, and damages assisted/robotic organs by severity.
/obj/item/organ/proc/organ_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/datum/damage_packet/packet = N.packet
	for(var/obj/O as anything in contents_of(src))
		O.emp_act(packet.severity)

	if(!(is_assisted()))
		return
	for(var/i = 1; i <= robotic; i++)
		switch (packet.severity)
			if (EMP_HEAVY)
				suffer_emp_damage(rand(5,9))
			if (EMP_MEDIUM)
				suffer_emp_damage(rand(3,7))
			if (EMP_LIGHT)
				suffer_emp_damage(rand(2,5))
			if (EMP_HARMLESS)
				suffer_emp_damage(rand(1,3))

/// Takes this organ out of its body, onto the floor under the owner. A ledger
/// move out of its slot: the detach hook (code/modules/body/parts/attach.dm)
/// does the bookkeeping, afflictions travel with it and a vital loss kills.
/// Forced: removal is a command, not a request. Returns TRUE if it came out.
/obj/item/organ/proc/removed(mob/living/user)
	var/mob/living/M = owner
	if(!M)
		return FALSE
	if(user && vital)
		add_attack_logs(user, M, "Removed vital organ [src.name]")
	var/atom/holder = loc
	var/atom/drop = M.drop_location()
	if(!holder?.slot_remove(src, drop, user, LEDGER_MOVE_FORCED))
		log_runtime("PARTS: removing [src] ([type]) from [key_name(M)] failed: holder [holder] ([holder?.type]), drop [drop]")
		return FALSE
	return TRUE

/// Puts this organ into `target`, in `affected` (default: the limb its
/// parent_organ names). A ledger move into the part slot: the attach hook does
/// the bookkeeping and the afflictions it carries rejoin the body. Returns
/// TRUE on success; a refused placement is logged and changes nothing.
/obj/item/organ/proc/replaced(mob/living/carbon/human/target, obj/item/organ/external/affected)
	if(!istype(target))
		return FALSE
	capture_transplant_data(target)
	var/obj/item/organ/external/E = affected || target.get_organ(parent_organ)
	if(!E)
		log_runtime("PARTS: [src] ([type]) has no [parent_organ] to go into on [key_name(target)]")
		return FALSE
	return place_into(E, SLOT_ID_PART_ORGANS)

/// Records who this organ was transplanted into, from the blood it carries
/// if any, else from `target`.
/obj/item/organ/proc/capture_transplant_data(mob/living/carbon/human/target)
	var/datum/reagent/blood/transplant_blood = null
	if(reagents)
		transplant_blood = locate_in_list(reagents.reagent_list, /datum/reagent/blood)
	transplant_data = list()
	if(!transplant_blood)
		transplant_data["species"] =    target?.species.name
		transplant_data["blood_type"] = target?.dna.b_type
		transplant_data["blood_DNA"] =  target?.dna.unique_enzymes
	else
		transplant_data["species"] =    transplant_blood?.data["species"]
		transplant_data["blood_type"] = transplant_blood?.data["blood_type"]
		transplant_data["blood_DNA"] =  transplant_blood?.data["blood_DNA"]

/// Takes the place this organ's tags give it in `M`'s body, which it was just
/// born inside: an internal organ goes into the limb its parent_organ names.
/// A mob with no part tree keeps it loose in its interior, where the attach
/// hook adopts it.
/obj/item/organ/proc/place_in_body(mob/living/M)
	var/datum/ledger/L = dq_ledger(M) // syncs: a mob with no part tree adopts us here
	if(!L?.def_by_id(SLOT_ID_PART_ROOT))
		return !!L
	var/obj/item/organ/external/E = LAZYACCESS(M.organs_by_name, parent_organ)
	if(!E)
		log_runtime("PARTS: [src] ([type]) born in [key_name(M)] with no [parent_organ] to go into; left loose")
		return FALSE
	return place_into(E, SLOT_ID_PART_ORGANS)

/// The one attaching move: into `holder`'s `slot_id`. A refusal is logged and
/// changes nothing. A move between two places in the same body (an organ
/// shunted from the head to the torso) is a reparent: the detach half keeps
/// the part's body-side state and doesn't count it as lost (attach.dm).
/obj/item/organ/proc/place_into(atom/holder, slot_id)
	var/why = dq_ledger_refusal(src, holder, slot_id)
	if(why)
		log_runtime("PARTS: [src] ([type]) refused by [holder] ([holder.type]) [slot_id]: [why]")
		return FALSE
	var/reparent = owner && dq_part_destination_owner(holder, slot_id) == owner
	if(reparent)
		GLOB.dq_part_reparenting = src
	. = dq_ledger_commit(src, holder, slot_id)
	if(reparent)
		GLOB.dq_part_reparenting = null

/obj/item/organ/proc/bitten(mob/user)

	if(is_robotic())
		return

	to_chat(user, span_notice("You take an experimental bite out of \the [src]."))
	var/datum/reagent/blood/B = locate_in_list(reagents.reagent_list, /datum/reagent/blood)
	blood_splatter(src,B,1)

	user.drop_from_inventory(src)
	var/obj/item/reagent_containers/food/snacks/organ/O = new(get_turf(src))
	O.name = name
	O.icon = icon
	O.icon_state = icon_state

	// Pass over the blood.
	reagents.trans_to(O, reagents.total_volume)
	transfer_fingerprints_to(O)
	transfer_blooddna_to(O)

	user.put_in_active_hand(O)
	consume(src, user)

MSG_DEF(organ/butcher_begin, span_danger("You are preparing to butcher %T%!"), span_danger("%U% prepares to butcher %T%!"))

// An organ in hand: bitten (outside combat, aiming at the mouth); an organ on the table: butchered with a blade (a screwdriver for a robotic
// one) or revived with peridaxon.
CAPABILITIES(/obj/item/organ)
	reagents(5)
	loose_organ_clock()
	owns_many(nameof(detached_afflictions))
	owns_many(nameof(autopsy_data))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(organ_emp)))
	op("bite", in_hand(), stance(I_HELP), label("Bite"), when(req_bool(PROC_REF(bite_offered))), then(PROC_REF(bite_op)))
	op("butcher", item(/obj/item), label("Butcher"), when(req_bool(PROC_REF(butcher_offered))), begins(MSG(organ/butcher_begin)), wait(PROC_REF(butcher_wait)), on_interrupt(PROC_REF(butcher_failed)), then(PROC_REF(butcher_op_done)))
	op("revive", item(/obj/item/reagent_containers), label("Revive"), then(PROC_REF(revive_op)))

/// The organ can be bitten: flesh, and the eater aims at the mouth.
/obj/item/organ/proc/bite_offered(datum/act/op/A)
	var/mob/user = A.actor
	return !is_robotic() && user?.zone_sel?.selecting == O_MOUTH

/obj/item/organ/proc/bite_op(datum/act/op/A)
	bitten(A.actor)

/obj/item/organ/proc/butcher_offered(datum/act/op/A)
	return can_butcher(A.held, A.actor)

/// Ten seconds, by the tool's speed.
/obj/item/organ/proc/butcher_wait(datum/act/op/A)
	var/obj/item/O = A.held
	return 10 SECONDS * (O?.toolspeed || 1)

/obj/item/organ/proc/butcher_failed(datum/act/op/A)
	var/mob/living/user = A.actor
	to_chat(user, span_notice("You reconsider butchering \the [src]..."))
	act_message(user, src, others = span_notice("%U% reconsiders butchering %T%!"))

/obj/item/organ/proc/butcher_op_done(datum/act/op/A)
	butcher_done(A.actor)

/obj/item/organ/proc/revive_op(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/container = A.held
	if(!container.reagents?.has_reagent(REAGENT_ID_PERIDAXON, 5))
		return OP_DECLINE // five units of peridaxon or nothing: the click goes on as before
	if(is_beyond_repair())
		to_chat(user, span_warning("\The [src] is dead beyond any revival."))
		return
	set_status(status & ~ORGAN_DEAD)
	var/obj/item/organ/internal/internal_organ = src
	if(istype(internal_organ))
		internal_organ.restore_lesions(1)
	else
		set_damage(damage - 1)
	//Fix JUST enough damage so it doesn't immediately die again. For full repair, use denec removal surgery.
	container.reagents.remove_reagent(REAGENT_ID_PERIDAXON, 5)
	to_chat(user, "You use the [container] to revive \the [src]")

/obj/item/organ/proc/can_butcher(obj/item/O, mob/living/user)
	if(butcherable && meat_type) // ALLOW(reads): the organ's meat is read when the butchery is tried, never from a cached menu

		if(istype(O, /obj/machinery/gibber))	// The great equalizer.
			return TRUE

		if(is_robotic())
			if(O.has_tool_quality(TOOL_SCREWDRIVER))
				return TRUE

		else
			if(is_sharp(O) && has_edge(O))
				return TRUE

	return FALSE

/// Butchers the organ into meat at once (a person butchers through the "butcher" op, which waits); the meat goes to `newtarget`.
/obj/item/organ/proc/butcher(obj/item/O, mob/living/user, atom/newtarget)
	return butcher_done(user, newtarget)

/obj/item/organ/proc/butcher_done(mob/living/user, atom/newtarget)
	if(user)
		if(is_robotic())
			act_message(user, src, others = span_warning("%U% disassembles %T%."))

		else
			act_message(user, src, others = span_warning("%U% butchers %T%."))

	if(!newtarget)
		newtarget = get_turf(src)

	var/obj/item/newmeat = new meat_type(newtarget)

	if(istype(newmeat, /obj/item/reagent_containers/food/snacks/meat))
		newmeat.name = "[src.name] [newmeat.name]"	// "liver meat" "heart meat", etc.

	if(LAZYLEN(contents)) //You can't shove the nuke disk into a leg and then butcher the leg to delete the nuke disk.
		for(var/obj/contained_object in contents)
			contained_object.forceMove(newtarget)

	spent(src, user)

/obj/item/organ/proc/organ_can_feel_pain()
	if(data.get_species_flags() & NO_PAIN)
		return 0
	if(status & ORGAN_DESTROYED)
		return 0
	if(robotic && robotic < ORGAN_LIFELIKE)	//Super fancy humanlike robotics probably have sensors, or something?
		return 0
	if(stapled_nerves)
		return 0
	return 1

/obj/item/organ/proc/handle_organ_mod_special(removed = FALSE)	// Called when created, transplanted, and removed.
	if(!istype(owner))
		return

	// Each organ grants its verbs with itself as source, so a verb shared with another
	// working organ stays while that organ still grants it.
	if(!removed && organ_verbs && check_verb_compatability())
		for(var/granted_path in organ_verbs)
			grant(owner, granted_verb(granted_path), src)
	else if(organ_verbs)
		for(var/granted_path in organ_verbs)
			revoke(owner, granted_verb(granted_path), src)
	return

/// TRUE when organ_tick() has nothing to do for this organ right now, so the body's organ clock
/// may park: no germs, no rejection under way, not at its damage limit. Organs with
/// their own handle_organ_proc_special() work say FALSE unless they know better.
/obj/item/organ/proc/life_step_idle()
	if((status & ORGAN_DEAD) || preserved || istype(loc, /obj/item/mmi))
		return TRUE
	return !germ_level && !rejecting && damage < max_damage

/obj/item/organ/proc/handle_organ_proc_special(cycles)	// Called when processed.
	return

/// Kelvin of waste heat per robotic core part (torso, groin, head) per organ tick.
#define ROBOBODY_WASTE_HEAT_PER_PART 0.5

/// Waste heat from a robotic chassis. ONE writer (D25): only the machine power
/// cell calls this; heatsinks dissipate it.
/obj/item/organ/proc/apply_robobody_heat()
	if(owner && owner.is_alive())
		owner.adjust_bodytemperature(round(owner.robobody_count * ROBOBODY_WASTE_HEAT_PER_PART, 0.1))

#undef ROBOBODY_WASTE_HEAT_PER_PART

/obj/item/organ/proc/check_verb_compatability()		// Used for determining if an organ should give or remove its verbs. I.E., FBP part in a human, no verbs. If true, keep or add.
	if(owner)
		if(ishuman(owner))
			var/mob/living/carbon/human/H = owner
			var/obj/item/organ/O = H.get_organ(parent_organ)
			if(!O)	// Parent limb is missing; nothing to be compatible with.
				return FALSE
			if(forgiving_class)
				if(!O.is_robotic() && robotic <= ORGAN_LIFELIKE)	// Parent is organic or assisted, we are at most synthetic.
					return TRUE

				if(O.is_robotic() && is_assisted())		// Parent is synthetic, and we are biosynthetic at least.
					return TRUE

			if(!target_parent_classes || !target_parent_classes.len)	// Default checks, if we're not looking for a Specific type.

				if(O.robotic == robotic)	// Same thing, we're fine.
					return TRUE

				if(!O.is_robotic() && !is_robotic())
					return TRUE

				if(O.is_robotic() && is_robotic())
					return TRUE

			else
				if(O.robotic in target_parent_classes)
					return TRUE

	return FALSE
