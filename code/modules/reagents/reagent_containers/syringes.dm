////////////////////////////////////////////////////////////////////////////////
/// Syringes.
////////////////////////////////////////////////////////////////////////////////
#define SYRINGE_DRAW 0
#define SYRINGE_INJECT 1
#define SYRINGE_BROKEN 2

#define SYRINGE_CAPPED 10

/obj/item/reagent_containers/syringe
	name = "syringe"
	desc = "A syringe."
	icon = 'icons/obj/syringe.dmi'
	icon = 'icons/goonstation/objects/syringe_vr.dmi'
	item_state = "syringe_0"
	icon_state = "0"
	center_of_mass_x = 16
	center_of_mass_y = 14
	material_template = /datum/material_template/container
	material_total = 150
	amount_per_transfer_from_this = 5
	max_transfer_amount = null
	volume = 15
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	sharp = TRUE
	injury_kind = INJURY_PIERCE
	unacidable = TRUE //glass
	var/mode = SYRINGE_CAPPED
	var/image/filling //holds a reference to the current filling overlay
	var/visible_name = "a syringe"
	var/time = 30
	var/drawing = FALSE
	var/dirtiness = 0
	var/list/targets
	/// Owned list of /datum/syringe_contamination: the contagion copies picked up from each target. Lazy.
	var/list/viruses
	drop_sound = SFX_ITEMS_DROP_GLASS
	pickup_sound = SFX_ITEMS_PICKUP_GLASS

/// Set once it has been injected into someone: from then on it gets dirtier over time.
OM_FIELD(/obj/item/reagent_containers/syringe, used, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/reagent_containers/syringe, PERIODIC_SLOW, "used")

/obj/item/reagent_containers/syringe/Initialize(mapload)
	. = ..()
	update_icon()


/obj/item/reagent_containers/syringe/periodic_step()
	dirtiness = min(dirtiness + targets.len,75)
	if(dirtiness >= 75)
		return PROCESS_KILL // as dirty as it gets
	return 1

/obj/item/reagent_containers/syringe/on_reagent_change()
	update_icon()

/obj/item/reagent_containers/syringe/pickup(mob/user)
	..()
	update_icon()

/obj/item/reagent_containers/syringe/dropped(mob/user, equipping, slot)
	..()
	update_icon()

DECLARE_INTERACTIONS(/obj/item/reagent_containers/syringe, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/reagent_containers/syringe/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	switch(mode)
		if(SYRINGE_CAPPED)
			mode = SYRINGE_DRAW
			balloon_alert(user, "[src] uncapped")
		if(SYRINGE_DRAW)
			mode = SYRINGE_INJECT
		if(SYRINGE_INJECT)
			mode = SYRINGE_DRAW
		if(SYRINGE_BROKEN)
			return TRUE
	update_icon()
	return TRUE

EXTEND_INTERACTIONS(/obj/item/reagent_containers/syringe, INTERACT_HAND_DEFAULT("Pick up", PROC_REF(syringe_pick_up)))

/// Picking the syringe up refreshes its look.
/obj/item/reagent_containers/syringe/proc/syringe_pick_up(mob/user, obj/item/held, datum/interaction/interaction)
	. = TRUE
	interaction_pick_up(user, held, interaction)
	update_icon()

/// Old attackby.
/obj/item/reagent_containers/syringe/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	return INTERACTION_HANDLED_PASS

/obj/item/reagent_containers/syringe/extrapolator_act(mob/living/user, obj/item/extrapolator/extrapolator, dry_run)
	. = ..()
	EXTRAPOLATOR_ACT_ADD_DISEASES(., carried_contagions())

/// Every contagion copy on the syringe, flattened.
/obj/item/reagent_containers/syringe/proc/carried_contagions()
	. = list()
	for(var/datum/syringe_contamination/C as anything in viruses)
		. += C.contagions

/// Replaces the contamination recorded for `hash` with `contagions` (unowned copies it adopts).
/obj/item/reagent_containers/syringe/proc/set_contamination(hash, list/contagions)
	for(var/datum/syringe_contamination/old as anything in viruses?.Copy())
		if(old.hash == hash)
			own_remove(src, "viruses", old)
	var/datum/syringe_contamination/C = new
	C.hash = hash
	for(var/datum/affliction/contagion/D as anything in contagions)
		own_add(C, "contagions", D)
	own_add(src, "viruses", C)

/// The contagion copies a syringe carries from one target (keyed by that target's hash).
/datum/syringe_contamination
	var/hash
	/// Owned contagion copies.
	var/list/contagions

/// Drawing `amount` of blood from the target.
/datum/om/task/timed/syringe_draw
	complete_proc = /obj/item/reagent_containers/syringe/proc/draw_blood_taken
	cancel_proc = /obj/item/reagent_containers/syringe/proc/draw_blood_stopped
	var/amount

/obj/item/reagent_containers/syringe/proc/draw_blood_stopped(datum/om/task/timed/syringe_draw/task)
	drawing = FALSE

/obj/item/reagent_containers/syringe/proc/draw_blood_taken(datum/om/task/timed/syringe_draw/task)
	draw_blood_done(task.actor, task.target, task.amount, TRUE)

/obj/item/reagent_containers/syringe/proc/draw_blood_done(mob/user, mob/living/carbon/T, amount, from_blood)
	drawing = FALSE
	if(from_blood)
		var/datum/reagent/B = T.take_blood(src, amount)
		if (B)
			reagents.adopt_reagent(B)
			reagents.update_total()
			on_reagent_change()
			reagents.handle_reactions()
	to_chat(user, span_notice("You take a blood sample from [T]."))
	for(var/mob/O in viewers(4, user))
		O.show_message(span_notice("[user] takes a blood sample from [T]."), 1)
	if(!reagents.get_free_space())
		mode = SYRINGE_INJECT
		update_icon()

/// Injecting a mob (the target): a warmup, then 5u per cycle while any is left.
/datum/om/task/timed/syringe_inject
	steps = list(/obj/item/reagent_containers/syringe/proc/inject_cycle = 0)
	complete_proc = /obj/item/reagent_containers/syringe/proc/inject_ended
	cancel_proc = /obj/item/reagent_containers/syringe/proc/inject_ended
	var/warmup = 0
	var/cycle_time = 0
	var/trans = 0
	var/contained
	var/warmed = FALSE

/obj/item/reagent_containers/syringe/proc/inject_cycle(datum/om/task/timed/syringe_inject/task)
	if(!task.warmed)
		task.warmed = TRUE
		return STEP_REPEAT(task.warmup)
	task.trans += reagents.trans_to_mob(task.target, amount_per_transfer_from_this, CHEM_BLOOD)
	update_icon()
	return reagents.total_volume ? STEP_REPEAT(task.cycle_time) : STEP_DONE

/obj/item/reagent_containers/syringe/proc/inject_ended(datum/om/task/timed/syringe_inject/task)
	if(task.warmed && (task.state == OM_TASK_DONE || task.trans))
		inject_finish(task.actor, task.target, task.trans, task.contained)

/obj/item/reagent_containers/syringe/proc/inject_finish(mob/user, atom/target, trans, contained)
	if (reagents.total_volume <= 0 && mode == SYRINGE_INJECT)
		mode = SYRINGE_DRAW
		update_icon()
	if(!user)
		return
	if(trans)
		to_chat(user, span_notice("You inject [trans] units of the solution. The syringe now contains [src.reagents.total_volume] units."))
		if(ismob(target))
			add_attack_logs(user,target,"Injected with [src.name] containing [contained], trasferred [trans] units")
	else
		to_chat(user, span_notice("The syringe is empty."))

/obj/item/reagent_containers/syringe/afterattack(obj/target, mob/user, proximity, click_parameters, stance = I_HURT)
	if(!proximity || !target.reagents)
		return

	if(mode == SYRINGE_BROKEN)
		to_chat(user, span_warning("This syringe is broken!"))
		return

	if(stance == I_HURT && ismob(target))
		if(CLUMSY_HARM_CHANCE(user))
			target = user
		syringestab(target, user)
		return

	var/injtime = time // Calculated 'true' injection time (as added to by hardsuits and whatnot), 66% of this goes to warmup, then every 33% after injects 5u
	switch(mode)
		if(SYRINGE_DRAW)
			if(!reagents.get_free_space())
				to_chat(user, span_warning("The syringe is full."))
				mode = SYRINGE_INJECT
				return

			if(ismob(target))//Blood!
				if(reagents.has_reagent(REAGENT_ID_BLOOD))
					to_chat(user, span_notice("There is already a blood sample in this syringe."))
					return

				if(istype(target, /mob/living/carbon))
					var/amount = reagents.get_free_space()
					var/mob/living/carbon/T = target
					if(!T.dna)
						to_chat(user, span_warning("You are unable to locate any blood. (To be specific, your target seems to be missing their DNA datum)."))
						return
					if(T.has_mutation(NOCLONE)) //target done been et, no more blood in him
						to_chat(user, span_warning("You are unable to locate any blood."))
						return

					if(HAS_SYNTHETIC_BIOLOGY(T))
						to_chat(user, span_warning("You can't draw blood from a synthetic!"))
						return

					if(drawing)
						to_chat(user, span_warning("You are already drawing blood from [T.name]."))
						return

					drawing = TRUE
					if(ishuman(T))
						var/mob/living/carbon/human/H = T
						if(H.species && !H.should_have_organ(O_HEART))
							H.reagents.trans_to_obj(src, amount)
							draw_blood_done(user, T, amount, FALSE)
						else if(H != user)
							om_task_start(/datum/om/task/timed/syringe_draw, user, T, duration = time, amount = amount)
							return
						else
							draw_blood_done(user, T, amount, TRUE)
					else
						om_task_start(/datum/om/task/timed/syringe_draw, user, T, duration = time, amount = amount)
						return

			else //if not mob
				if(!target.reagents.total_volume)
					to_chat(user, span_notice("[target] is empty."))
					return

				if(!target.is_open_container() && !istype(target, /obj/structure/reagent_dispensers) && !istype(target, /obj/item/slime_extract) && !istype(target, /obj/item/reagent_containers/food) && !istype(target, /obj/item/reagent_containers/blood))
					to_chat(user, span_notice("You cannot directly remove reagents from this object."))
					return

				var/trans = target.reagents.trans_to_obj(src, amount_per_transfer_from_this)
				to_chat(user, span_notice("You fill the syringe with [trans] units of the solution."))
				update_icon()

			if(!reagents.get_free_space())
				mode = SYRINGE_INJECT
				update_icon()

		if(SYRINGE_INJECT)
			if(!reagents.total_volume)
				to_chat(user, span_notice("The syringe is empty."))
				mode = SYRINGE_DRAW
				return
			if(istype(target, /obj/item/implantcase/chem))
				return

			// begin - Engineered organ training
			if(istype(target, /obj/item/organ/internal/malignant/engineered/lattice))
				var/datum/reagent/R = pick(reagents.reagent_list)
				if(R)
					var/obj/item/organ/internal/malignant/engineered/lattice/LAT = target
					var/success = LAT.make_mutoid(R.id)
					to_chat(user, span_notice("You inject \the [target] with \the [src], and [success ? "it begins to mutate!" : "nothing seems to happen."]"))
					reagents.clear_reagents()
					mode = SYRINGE_DRAW
					update_icon()
				return
			// end

			if(!target.is_injectable_container() && !ismob(target))
				to_chat(user, span_notice("You cannot directly fill this object."))
				return
			if(!target.reagents.get_free_space())
				to_chat(user, span_notice("[target] is full."))
				return

			var/mob/living/carbon/human/H = target
			var/obj/item/organ/external/affected // Moved this outside this if
			if(istype(H))
				if(!H.consume_liquid_belly)
					if(liquid_belly_check())
						to_chat(user, span_infoplain("[user == H ? "You can't" : "\The [H] can't"] take that, it contains something produced from a belly!"))
						return
				affected = H.get_organ(user.zone_sel.selecting) // See above comment.
				if(!affected)
					to_chat(user, span_danger("\The [H] is missing that limb!"))
					return

			var/cycle_time = injtime*0.33 //33% of the time slept between 5u doses
			var/warmup_time = 0	//0 for containers
			if(ismob(target))
				warmup_time = cycle_time //If the target is another mob, this gets overwritten

			if(ismob(target) && target != user)
				warmup_time = injtime*0.66 //66% of the time is warmup

				if(istype(H))
					// B22: humans go through can_inject() like every other target (missing
					// limb, thick hide, sealed prosthetics). A suit only slows the needle down:
					// the user hunts for an injection port instead of being refused.
					if(!H.can_inject(user, 1, affected?.organ_tag, TRUE))
						return
					if(H.get_equipped_item(SLOT_ID_SUIT))
						if(istype(H.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/space))
							injtime = injtime * 2

				else if(isliving(target))

					var/mob/living/M = target
					if(!M.can_inject(user, 1))
						return

				if(injtime == time)
					act_message(user, target, MSG_SELF(span_notice("You begin injecting %T% with [visible_name].")), \
						MSG_OTHERS(span_warning("%U% is trying to inject %T% with [visible_name]!")))
				else
					act_message(user, target, MSG_SELF(span_notice("You begin hunting for an injection port on %T%'s suit!")), \
						MSG_OTHERS(span_warning("%U% begins hunting for an injection port on %T%'s suit!")))

			//The warmup
			user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)
			var/contained = reagentlist()
			if(ismob(target))
				// Then 5u per cycle, each cycle a timed action.
				om_task_start(/datum/om/task/timed/syringe_inject, user, target, warmup = warmup_time, cycle_time = cycle_time, contained = contained)
				return
			var/trans = reagents.trans_to_obj(target, amount_per_transfer_from_this)
			inject_finish(user, target, trans, contained)

	return

/// Units a harm-intent stab forces in out of `volume`: 5-10 short of the barrel, never below 0.
/obj/item/reagent_containers/syringe/proc/syringestab_amount(volume)
	return rand(max(volume - 10, 0), max(volume - 5, 0))

/obj/item/reagent_containers/syringe/proc/syringestab(mob/living/carbon/target as mob, mob/living/carbon/user as mob)
	if(ishuman(target))

		var/mob/living/carbon/human/H = target

		var/target_zone = get_zone_with_miss_chance(user.zone_sel.selecting, target, attacker = user)
		var/obj/item/organ/external/affecting = H.get_organ(target_zone)

		if (!affecting || affecting.is_stump())
			balloon_alert(user, "they are missing that limb!")
			return

		var/hit_area = affecting.name

		if((user != target) && H.check_shields(7, src, user, "\the [src]"))
			return

		var/armor_val = H.injury_armor(INJURY_BLUNT, target_zone)
		if(target != user && armor_val >= 5 && prob(50+armor_val)) // High armor can deflect syringe stabs
			for(var/mob/O in viewers(world.view, user))
				O.show_message(span_bolddanger("[user] tries to stab [target] in \the [hit_area] with [src.name], but the attack is deflected by armor!"), 1)
			consume(src, user)

			add_attack_logs(user,target,"Syringe harmclick")

			return

		balloon_alert_visible("stabs [target] in \the [hit_area] with [src.name]!")

		H.injure(INJURY_PIERCE, 3, target_zone, source = src)

	else
		balloon_alert_visible("stabs [user] in \the [target] with [src.name]!")
		target.injure(INJURY_PIERCE, 3, source = src)// 7 is the same as crowbar punch

	// B22: never negative, however little is left in the barrel.
	var/syringestab_amount_transferred = syringestab_amount(reagents.total_volume) //nerfed by popular demand
	var/contained = reagents.get_reagents()
	var/trans = reagents.trans_to_mob(target, syringestab_amount_transferred, CHEM_BLOOD)
	if(isnull(trans)) trans = 0
	add_attack_logs(user,target,"Stabbed with [src.name] containing [contained], trasferred [trans] units")
	if(!issilicon(user))
		break_syringe(target, user)

/obj/item/reagent_containers/syringe/proc/break_syringe(mob/living/carbon/target, mob/living/carbon/user)
	desc += " It is broken."
	mode = SYRINGE_BROKEN
	if(target)
		add_blood(target)
	if(user)
		add_fingerprint(user)
	update_icon()

/obj/item/reagent_containers/syringe/ld50_syringe
	name = "Lethal Injection Syringe"
	desc = "A syringe used for lethal injections."
	amount_per_transfer_from_this = 50
	volume = 50
	visible_name = "a giant syringe"
	time = 300

/obj/item/reagent_containers/syringe/ld50_syringe/afterattack(obj/target, mob/user, flag, click_parameters, stance = I_HURT)
	if(mode == SYRINGE_DRAW && ismob(target)) // No drawing 50 units of blood at once
		to_chat(user, span_notice("This needle isn't designed for drawing blood."))
		return
	if(stance == I_HURT && ismob(target)) // No instant injecting
		to_chat(user, span_notice("This syringe is too big to stab someone with it."))
		return
	..()

////////////////////////////////////////////////////////////////////////////////
/// Syringes. END
////////////////////////////////////////////////////////////////////////////////

/obj/item/reagent_containers/syringe/inaprovaline
	name = "Syringe (inaprovaline)"
	desc = "Contains inaprovaline - used to stabilize patients."

DECLARE_REAGENTS(/obj/item/reagent_containers/syringe/inaprovaline, null, list(REAGENT_ID_INAPROVALINE = 15))

/obj/item/reagent_containers/syringe/antitoxin
	name = "Syringe (anti-toxin)"
	desc = "Contains anti-toxins."

DECLARE_REAGENTS(/obj/item/reagent_containers/syringe/antitoxin, null, list(REAGENT_ID_ANTITOXIN = 15))

/obj/item/reagent_containers/syringe/antiviral
	name = "Syringe (spaceacillin)"
	desc = "Contains antiviral agents."

DECLARE_REAGENTS(/obj/item/reagent_containers/syringe/antiviral, null, list(REAGENT_ID_SPACEACILLIN = 15))

/obj/item/reagent_containers/syringe/drugs
	name = "Syringe (drugs)"
	desc = "Contains aggressive drugs meant for torture."

DECLARE_REAGENTS(/obj/item/reagent_containers/syringe/drugs, null, list(REAGENT_ID_BLISS = 5, REAGENT_ID_MINDBREAKER = 5, REAGENT_ID_CRYPTOBIOLIN = 5))

DECLARE_REAGENTS(/obj/item/reagent_containers/syringe/ld50_syringe/choral, null, list(REAGENT_ID_CHLORALHYDRATE = 50))

/obj/item/reagent_containers/syringe/ld50_syringe/choral/Initialize(mapload)
	. = ..()
	mode = SYRINGE_INJECT
	update_icon()

/obj/item/reagent_containers/syringe/steroid
	name = "Syringe (anabolic steroids)"
	desc = "Contains drugs for muscle growth."

DECLARE_REAGENTS(/obj/item/reagent_containers/syringe/steroid, null, list(REAGENT_ID_HYPERZINE = 10))

/obj/item/reagent_containers/syringe/proc/dirty(mob/living/carbon/human/target, obj/item/organ/external/eo)
	if(!ishuman(loc))
		return //Avoid borg syringe problems.
	LAZYINITLIST(targets)

	//We can't keep a mob reference, that's a bad idea, so instead name+ref should suffice.
	var/name_to_use = ismob(target) ? target.real_name : target.name
	var/hash = md5(name_to_use + "\ref[target]")

	//Just once!
	targets |= hash

	//Grab any viruses they have
	if(iscarbon(target) && target.has_contagions())
		set_contamination(hash, contagion_copies(target.get_spreadable_contagions()))

	//Dirtiness should be very low if you're the first injectee. If you're spam-injecting 4 people in a row around you though,
	//This gives the last one a 30% chance of infection.
	var/infect_chance = dirtiness        //Start with dirtiness
	if(infect_chance <= 10 && (hash in targets)) //Extra fast uses on target is free
		infect_chance = 0
	infect_chance += (targets.len-1)*10    //Extra 10% per extra target
	if(prob(infect_chance))
		log_and_message_admins("[loc] infected [target]'s [eo.name] with \the [src].", usr)
		infect_limb(eo)

	//75% chance to spread a virus if we have one
	if(LAZYLEN(viruses) && prob(75))
		var/datum/syringe_contamination/old = pick(viruses)
		if(hash != old.hash) //Same virus you already had?
			for(var/datum/affliction/contagion/virus as anything in old.contagions)
				target.force_contagion(virus)

	set_used(TRUE)

/obj/item/reagent_containers/syringe/proc/infect_limb(obj/item/organ/external/eo)
	om_after(eo, rand(5 MINUTES,10 MINUTES), TYPE_PROC_REF(/obj/item/organ/external, syringe_infection))

//Allow for capped syringe mode

//Allow for capped syringes
/obj/item/reagent_containers/syringe/update_icon()
	cut_overlays()

	var/matrix/tf = matrix()
	if(isstorage(loc))
		tf.Turn(-90) //Vertical for storing compact-ly
		tf.Translate(-3,0) //Could do this with pixel_x but let's just update the appearance once.
	transform = tf

	if(mode == SYRINGE_BROKEN)
		icon_state = "broken"
		return

	if(mode == SYRINGE_CAPPED)
		icon_state = "capped"
		return

	var/rounded_vol = round(reagents.total_volume, round(reagents.maximum_volume / 3))
	if(reagents.total_volume)
		filling = image(icon, src, "filler[rounded_vol]")
		filling.color = reagents.get_color()
		add_overlay(filling)

	if(ismob(loc))
		var/injoverlay
		switch(mode)
			if (SYRINGE_DRAW)
				injoverlay = "draw"
			if (SYRINGE_INJECT)
				injoverlay = "inject"
		add_overlay(injoverlay)

	icon_state = "[rounded_vol]"
	item_state = "syringe_[rounded_vol]"

/obj/item/reagent_containers/syringe/old
	name = "old syringe"
	desc = "An old, broken syringe. Are you sure it's a good idea to pick it up without gloves?"
	mode = SYRINGE_BROKEN

/obj/item/reagent_containers/syringe/old/Initialize(mapload)
	. = ..()
	if(prob(75))
		var/datum/affliction/contagion/engineered/new_disease = new /datum/affliction/contagion/engineered/random(rand(1, 3), rand(7, 9), 2, infected = src)
		set_contamination("old", list(new_disease))

#undef SYRINGE_DRAW
#undef SYRINGE_INJECT
#undef SYRINGE_BROKEN

#undef SYRINGE_CAPPED

/// A dirty syringe's infection takes hold in the limb.
/obj/item/organ/external/proc/syringe_infection()
	germ_level += INFECTION_LEVEL_ONE+30
