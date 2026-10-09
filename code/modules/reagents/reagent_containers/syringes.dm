////////////////////////////////////////////////////////////////////////////////
/// Syringes.
////////////////////////////////////////////////////////////////////////////////
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
	var/mode = NEEDLE_CAPPED
	var/visible_name = "a syringe"
	var/time = 30
	var/dirtiness = 0
	var/list/targets
	/// Owned list of /datum/syringe_contamination: the contagion copies picked up from each target. Lazy.
	var/list/viruses
	drop_sound = SFX_ITEMS_DROP_GLASS
	pickup_sound = SFX_ITEMS_PICKUP_GLASS

/// Set once it has been injected into someone: from then on it gets dirtier over time, until it is as dirty as it gets.
/obj/item/reagent_containers/syringe/var/used = FALSE
TRACKED(/obj/item/reagent_containers/syringe, used)
TRACKED(/obj/item/reagent_containers/syringe, mode)

/// Every 2 seconds while used: dirtier by one per person it went into, up to 75, where it stops (as dirty as it gets).
/obj/item/reagent_containers/syringe/proc/syringe_step(datum/act/timer/A)
	dirtiness = min(dirtiness + targets.len, 75)
	if(dirtiness >= 75)
		set_used(FALSE)

/obj/item/reagent_containers/syringe/pickup(mob/user)
	..()

/obj/item/reagent_containers/syringe/dropped(mob/user, equipping, slot)
	..()

// A syringe is a sealed container of its volume that draws from containers and tanks, puts into containers, takes blood, injects people and stabs them
// (needle(), code/library/reagents/needle.dm). Its mode (capped, draw, inject, broken) is the `mode` var, changed in hand. The giant syringe and the
// lethal injection syringe ask for more time and refuse blood and the stab.
CAPABILITIES(/obj/item/reagent_containers/syringe)
	reagent_container(
		volume = nameof(volume),
		needle = TRUE,
		sealed = TRUE,
		settable = FALSE,
		shows_contents = FALSE,
		transfer_default = nameof(amount_per_transfer_from_this))
	needle(
		modes = nameof(mode),
		needle_time = nameof(time),
		draws_from = list(/obj/structure/reagent_dispensers, /obj/item/slime_extract, /obj/item/reagent_containers/food, /obj/item/reagent_containers/blood),
		fills = TRUE)
	op("pick_up", hand(), priority(OP_PRIORITY_DEFAULT), label("Pick up"), then(PROC_REF(syringe_pick_up)))
	op("stab", at_target(/mob/living), hostile(), stance(I_HURT), label("Stab"),
		needs(req_not(req_is(nameof(mode), NEEDLE_BROKEN), because = MSG(needle/broken)), req_bool(PROC_REF(may_stab), because = MSG(syringe/too_big))),
		then(PROC_REF(stabbed)))
	owns_many(nameof(viruses))
	every(2 SECONDS, then(PROC_REF(syringe_step)), when = nameof(used))

MSG_DEF_SELF(syringe/too_big, "This syringe is too big to stab someone with it.")
MSG_DEF_SELF(syringe/no_blood, "This needle isn't designed for drawing blood.")

/// The syringe may be used to stab: the giant ones may not.
/obj/item/reagent_containers/syringe/proc/may_stab(datum/act/op/A)
	return TRUE

/// A hostile click on a person: a stab (a clumsy hand stabs its own).
/obj/item/reagent_containers/syringe/proc/stabbed(datum/act/op/A)
	var/mob/living/target = A.target
	var/mob/user = A.actor
	if(!target.reagents)
		return OP_REFUSED
	if(CLUMSY_HARM_CHANCE(user))
		target = user
	syringestab(target, user)
	return OP_OK

/// Picking the syringe up refreshes its look.
/obj/item/reagent_containers/syringe/proc/syringe_pick_up(datum/act/op/A)
	pick_up_by_hand(A.actor)
	return OP_OK

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
			rel_remove(src, nameof(viruses), old)
	var/datum/syringe_contamination/C = new
	C.hash = hash
	for(var/datum/affliction/contagion/D as anything in contagions)
		rel_add(C, nameof(C.contagions), D)
	rel_add(src, nameof(viruses), C)

/// The contagion copies a syringe carries from one target (keyed by that target's hash).
/datum/syringe_contamination
	var/hash
	/// Owned contagion copies.
	var/list/contagions

CAPABILITIES(/datum/syringe_contamination)
	owns_many(nameof(contagions))

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
	set_mode(NEEDLE_BROKEN)
	if(target)
		add_blood(target)
	if(user)
		add_fingerprint(user)

/obj/item/reagent_containers/syringe/ld50_syringe
	name = "Lethal Injection Syringe"
	desc = "A syringe used for lethal injections."
	amount_per_transfer_from_this = 50
	volume = 50
	visible_name = "a giant syringe"
	time = 300

// The lethal injection syringe draws no blood and does not stab.
CAPABILITIES(/obj/item/reagent_containers/syringe/ld50_syringe)
	extend("needle.draw_blood", needs(req_bool(PROC_REF(no_blood_draw), because = MSG(syringe/no_blood))))
	extend("needle.take_blood", needs(req_bool(PROC_REF(no_blood_draw), because = MSG(syringe/no_blood))))

/obj/item/reagent_containers/syringe/ld50_syringe/proc/no_blood_draw(datum/act/op/A)
	return FALSE

/obj/item/reagent_containers/syringe/ld50_syringe/may_stab(datum/act/op/A)
	return FALSE

////////////////////////////////////////////////////////////////////////////////
/// Syringes. END
////////////////////////////////////////////////////////////////////////////////

/obj/item/reagent_containers/syringe/inaprovaline
	name = "Syringe (inaprovaline)"
	desc = "Contains inaprovaline - used to stabilize patients."

CAPABILITIES(/obj/item/reagent_containers/syringe/inaprovaline)
	configure(reagents(add = list(REAGENT_ID_INAPROVALINE = 15)))

/obj/item/reagent_containers/syringe/antitoxin
	name = "Syringe (anti-toxin)"
	desc = "Contains anti-toxins."

CAPABILITIES(/obj/item/reagent_containers/syringe/antitoxin)
	configure(reagents(add = list(REAGENT_ID_ANTITOXIN = 15)))

/obj/item/reagent_containers/syringe/antiviral
	name = "Syringe (spaceacillin)"
	desc = "Contains antiviral agents."

CAPABILITIES(/obj/item/reagent_containers/syringe/antiviral)
	configure(reagents(add = list(REAGENT_ID_SPACEACILLIN = 15)))

/obj/item/reagent_containers/syringe/drugs
	name = "Syringe (drugs)"
	desc = "Contains aggressive drugs meant for torture."

CAPABILITIES(/obj/item/reagent_containers/syringe/drugs)
	configure(reagents(add = list(REAGENT_ID_BLISS = 5, REAGENT_ID_MINDBREAKER = 5, REAGENT_ID_CRYPTOBIOLIN = 5)))

CAPABILITIES(/obj/item/reagent_containers/syringe/ld50_syringe/choral)
	configure(reagents(add = list(REAGENT_ID_CHLORALHYDRATE = 50)))

/obj/item/reagent_containers/syringe/ld50_syringe/choral/Initialize(mapload)
	. = ..()
	set_mode(NEEDLE_INJECT)

/obj/item/reagent_containers/syringe/steroid
	name = "Syringe (anabolic steroids)"
	desc = "Contains drugs for muscle growth."

CAPABILITIES(/obj/item/reagent_containers/syringe/steroid)
	configure(reagents(add = list(REAGENT_ID_HYPERZINE = 10)))

/obj/item/reagent_containers/syringe/proc/dirty(mob/living/carbon/human/target, obj/item/organ/external/eo)
	if(!ishuman(loc))
		return //Avoid borg syringe problems.
	var/mob/living/carbon/human/user = loc
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
		log_and_message_admins("[loc] infected [target]'s [eo.name] with \the [src].", user)
		infect_limb(eo)

	//75% chance to spread a virus if we have one
	if(LAZYLEN(viruses) && prob(75))
		var/datum/syringe_contamination/old = pick(viruses)
		if(hash != old.hash) //Same virus you already had?
			for(var/datum/affliction/contagion/virus as anything in old.contagions)
				target.force_contagion(virus)

	set_used(TRUE)

/obj/item/reagent_containers/syringe/proc/infect_limb(obj/item/organ/external/eo)
	after(eo, rand(5 MINUTES,10 MINUTES), TYPE_PROC_REF(/obj/item/organ/external, syringe_infection))

//Allow for capped syringe mode

//Allow for capped syringes
/obj/item/reagent_containers/syringe/draw(datum/look/look)
	..()
	var/matrix/tf = matrix()
	if(isstorage(loc))
		tf.Turn(-90) //Vertical for storing compact-ly
		tf.Translate(-3,0)
	look.set_transform(tf)

	if(mode == NEEDLE_BROKEN)
		look.state("broken")
		return

	if(mode == NEEDLE_CAPPED)
		look.state("capped")
		return

	look.watch(reagents)
	var/rounded_vol = round(reagents.total_volume, round(reagents.maximum_volume / 3))
	if(reagents.total_volume)
		look.overlay(look_overlay_image(icon, "filler[rounded_vol]", color = reagents.tint))

	if(ismob(loc))
		switch(mode)
			if(NEEDLE_DRAW)
				look.overlay("draw")
			if(NEEDLE_INJECT)
				look.overlay("inject")

	look.state("[rounded_vol]")
	look.held_state("syringe_[rounded_vol]")

/obj/item/reagent_containers/syringe/old
	name = "old syringe"
	desc = "An old, broken syringe. Are you sure it's a good idea to pick it up without gloves?"
	mode = NEEDLE_BROKEN

// ALLOW(init/INSTANCE_STATE): rolls whether this old syringe is contaminated
/obj/item/reagent_containers/syringe/old/Initialize(mapload)
	. = ..()
	if(prob(75))
		var/datum/affliction/contagion/engineered/new_disease = new /datum/affliction/contagion/engineered/random(rand(1, 3), rand(7, 9), 2, infected = src)
		set_contamination("old", list(new_disease))

/// A dirty syringe's infection takes hold in the limb.
/obj/item/organ/external/proc/syringe_infection()
	germ_level += INFECTION_LEVEL_ONE+30
