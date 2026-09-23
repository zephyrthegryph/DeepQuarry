/mob/living/carbon/human/proc/update_eyes()
	var/obj/item/organ/internal/eyes/eyes = internal_organs_by_name[O_EYES]
	if(eyes)
		eyes.update_colour()
		update_icons_body() //Body handles eyes
		update_eyes() //For floating eyes only

/mob/living/carbon/human/proc/recheck_bad_external_organs()
	var/damage_this_tick = injury_load(INJURY_CATEGORY_TOXIC)
	for(var/obj/item/organ/external/O in organs)
		damage_this_tick += O.get_burn() + O.get_trauma()
		if(O.germ_level)
			damage_this_tick += 1 //Just tap it if we have germs so we can process those

	if(damage_this_tick > last_dam)
		. = TRUE
	last_dam = damage_this_tick

/datum/life_system/organs
	name = "organs"
	bit = LIFE_SYS_ORGANS
	phase = LIFE_PHASE_TAIL
	order = 150
	segment = LIFE_SEG_HUMAN_LIVE
	mob_type = /mob/living/carbon/human

/datum/life_system/organs/tick(mob/living/carbon/human/self, datum/life_context/ctx)
	process_organs(self)

/// Takes care of organ related updates, such as broken and missing limbs. `force` rebuilds the
/// list of external organs that need processing.
/datum/life_system/organs/proc/process_organs(mob/living/carbon/human/self, force = FALSE)

	var/force_process = self.recheck_bad_external_organs()

	if(force_process || force)
		// Populate directly from organs that need processing instead of adding all
		// then pruning the ones that don't (the old "Silly and slow" approach).
		self.bad_external_organs.Cut()
		for(var/obj/item/organ/external/Ex in self.organs)
			if(Ex.need_process())
				self.bad_external_organs += Ex

	//processing internal organs is pretty cheap, do that first.
	for(var/obj/item/organ/I in self.internal_organs)
		I.process()

	self.handle_stance()
	self.handle_grasp()

	if(!force_process && !self.bad_external_organs.len)
		return

	self.number_wounds = 0
	for(var/obj/item/organ/external/E in self.bad_external_organs)
		if(!E)
			continue
		if(!E.need_process())
			self.bad_external_organs -= E
			continue
		else
			E.process()
			self.number_wounds += length(E.get_wounds())

			if (!self.lying && !self.buckled && world.time - self.l_move_time < 15)
			//Moving around with fractured ribs won't do you any good
				if (prob(10) && !self.stat && self.can_feel_pain() && self.factor(BF_ANALGESIA) < 50 && E.is_broken() && E.internal_organs.len)
					self.custom_pain("Pain jolts through your broken [E.encased ? E.encased : E.name], staggering you!", 50)
					self.emote("scream")
					self.drop_item(self.loc)
					self.Stun(2)

				//Moving makes open wounds get infected much faster
				for(var/datum/affliction/wound/W as anything in E.get_wounds())
					if (W.infection_check())
						W.germ_level += 1

/mob/living/carbon/human/proc/handle_stance()
	// Don't need to process any of this if they aren't standing anyways
	// unless their stance is damaged, and we want to check if they should stay down
	if (!stance_damage && (lying || resting) && (life_tick % 4) != 0)
		return

	stance_damage = 0

	// Buckled to a bed/chair. Stance damage is forced to 0 since they're sitting on something solid
	if (istype(buckled, /obj/structure/bed))
		return

	var/limb_pain = FALSE
	for(var/limb_tag in list(BP_L_LEG,BP_R_LEG,BP_L_FOOT,BP_R_FOOT))
		var/obj/item/organ/external/E = organs_by_name[limb_tag]
		if(!E || !E.is_usable())
			stance_damage += 2 // let it fail even if just foot&leg
		else if (E.is_malfunctioning() && !(lying || resting))
			//malfunctioning only happens intermittently so treat it as a missing limb when it procs
			stance_damage += 2
			if(isturf(loc) && prob(10))
				visible_message("\The [src]'s [E.name] [pick("twitches", "shudders")] and sparks!")
				var/datum/effect/effect/system/spark_spread/spark_system = new ()
				spark_system.set_up(5, 0, src)
				spark_system.attach(src)
				spark_system.start()
				QDEL_IN(spark_system, 1 SECOND)
		else if (E.is_broken())
			stance_damage += 1
		else if (E.is_dislocated())
			stance_damage += 0.5

		if(E && (!E.is_usable() || E.is_broken() || E.is_dislocated()))
			limb_pain = E.organ_can_feel_pain()

	// Canes and crutches help you stand (if the latter is ever added)
	// One cane mitigates a broken leg+foot, or a missing foot.
	// Two canes are needed for a lost leg. If you are missing both legs, canes aren't gonna help you.
	if (get_equipped_item(SLOT_ID_L_HAND) && istype(get_equipped_item(SLOT_ID_L_HAND), /obj/item/cane))
		stance_damage -= 2
	if (get_equipped_item(SLOT_ID_R_HAND) && istype(get_equipped_item(SLOT_ID_R_HAND), /obj/item/cane))
		stance_damage -= 2

	// Jetpacks in zeroG count for holding you up
	var/obj/item/tank/jetpack/thrust = get_jetpack()
	if (lastarea?.get_gravity() == FALSE && thrust?.stabilization_on)
		stance_damage -= 4

	// standing is poor
	if(stance_damage >= 4 || (stance_damage >= 2 && prob(5)))
		if(!(lying || resting) && !isbelly(loc))
			if(limb_pain)
				emote("scream")
			automatic_custom_emote(VISIBLE_MESSAGE, "collapses!", check_stat = TRUE)
		if(!(lying || resting)) // stops permastun with SPINE sdisability
			Weaken(5)

/mob/living/carbon/human/proc/handle_grasp()
	if(!get_equipped_item(SLOT_ID_L_HAND) && !get_equipped_item(SLOT_ID_R_HAND))
		return

	// You should not be able to pick anything up, but stranger things have happened.
	if(get_equipped_item(SLOT_ID_L_HAND))
		for(var/limb_tag in list(BP_L_HAND, BP_L_ARM))
			var/obj/item/organ/external/E = get_organ(limb_tag)
			if(!E)
				visible_message(span_danger("Lacking a functioning left hand, \the [src] drops \the [get_equipped_item(SLOT_ID_L_HAND)]."))
				drop_from_inventory(get_equipped_item(SLOT_ID_L_HAND))
				break

	if(get_equipped_item(SLOT_ID_R_HAND))
		for(var/limb_tag in list(BP_R_HAND, BP_R_ARM))
			var/obj/item/organ/external/E = get_organ(limb_tag)
			if(!E)
				visible_message(span_danger("Lacking a functioning right hand, \the [src] drops \the [get_equipped_item(SLOT_ID_R_HAND)]."))
				drop_from_inventory(get_equipped_item(SLOT_ID_R_HAND))
				break

	// Check again...
	if(!get_equipped_item(SLOT_ID_L_HAND) && !get_equipped_item(SLOT_ID_R_HAND))
		return
	var/adrenaline = has_modifier_of_type(/datum/modifier/adrenaline)
	for (var/obj/item/organ/external/E in organs)
		if(!E || !E.can_grasp)
			continue

		if((E.is_broken() || E.is_dislocated()) && !E.splinted && !adrenaline)
			switch(E.body_part)
				if(HAND_LEFT, ARM_LEFT)
					if(!get_equipped_item(SLOT_ID_L_HAND))
						continue
					drop_from_inventory(get_equipped_item(SLOT_ID_L_HAND))
				if(HAND_RIGHT, ARM_RIGHT)
					if(!get_equipped_item(SLOT_ID_R_HAND))
						continue
					drop_from_inventory(get_equipped_item(SLOT_ID_R_HAND))

			if(!isbelly(loc))
				var/emote_scream = pick("screams in pain and ", "lets out a sharp cry and ", "cries out and ")
				automatic_custom_emote(VISIBLE_MESSAGE, "[(can_feel_pain()) ? "" : emote_scream ]drops what they were holding in their [E.name]!", check_stat = TRUE)
				if(can_feel_pain())
					emote("pain")

		else if(E.is_malfunctioning())
			switch(E.body_part)
				if(HAND_LEFT, ARM_LEFT)
					if(!get_equipped_item(SLOT_ID_L_HAND))
						continue
					drop_from_inventory(get_equipped_item(SLOT_ID_L_HAND))
				if(HAND_RIGHT, ARM_RIGHT)
					if(!get_equipped_item(SLOT_ID_R_HAND))
						continue
					drop_from_inventory(get_equipped_item(SLOT_ID_R_HAND))

			if(!isbelly(loc))
				automatic_custom_emote(VISIBLE_MESSAGE, "drops what they were holding, their [E.name] malfunctioning!", check_stat = TRUE)

				var/datum/effect/effect/system/spark_spread/spark_system = new /datum/effect/effect/system/spark_spread()
				spark_system.set_up(5, 0, src)
				spark_system.attach(src)
				spark_system.start()
				spawn(10)
					qdel(spark_system)

//Handles chem traces
/mob/living/carbon/human/proc/handle_trace_chems()
	//New are added for reagents to random organs.
	for(var/datum/reagent/A in reagents.reagent_list)
		var/obj/item/organ/O = pick(organs)
		O.trace_chemicals[A.name] = 100

// Traitgenes Init genes based on the traits currently active
/mob/living/carbon/human/proc/sync_dna_traits(refresh_traits, hide_message = TRUE)
	SHOULD_NOT_OVERRIDE(TRUE) //Don't. Even. /Think/. About. It.
	if(!dna || !species)
		return
	// Traitgenes NO_DNA and Synthetics cannot be mutated
	if(isSynthetic())
		return
	if(species.flags & NO_DNA)
		return
	if(refresh_traits && species.traits)
		for(var/TR in species.traits)
			var/datum/trait/T = GLOB.all_traits[TR]
			if(!T)
				continue
			if(!T.linked_gene)
				continue
			var/datum/gene/trait/gene = T.linked_gene
			dna.SetSEState(gene.block, TRUE, TRUE)
			// testing("[gene.name] Setup activated!")
		dna.UpdateSE()
	var/flgs = MUTCHK_FORCED
	if(hide_message)
		flgs |= MUTCHK_HIDEMSG
	domutcheck( src, null, flgs)

/mob/living/carbon/human/proc/sync_organ_dna()
	var/list/all_bits = internal_organs|organs
	for(var/obj/item/organ/O in all_bits)
		O.set_dna(dna)

/mob/living/carbon/human/proc/set_gender(g)
	if(g != gender)
		gender = g

	if(dna.GetUIState(DNA_UI_GENDER) ^ gender == FEMALE) // XOR will catch both cases where they do not match
		dna.SetUIState(DNA_UI_GENDER, gender == FEMALE)
		sync_organ_dna(dna)

/// Runs the organs system now. `force` rebuilds the list of external organs needing processing.
/mob/living/carbon/human/proc/process_organs(force = FALSE)
	var/datum/life_system/organs/S = life_system_for(/datum/life_system/organs)
	S?.process_organs(src, force)
