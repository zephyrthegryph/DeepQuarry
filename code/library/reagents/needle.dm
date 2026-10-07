// needle(...) (doc/rewrite/final_api.html, section 11; section 16.5): what a syringe and a dropper do with a click, on top of reagent_container(): draw
// from a container, put into one, and, for a syringe (it has `modes`), draw a person's blood, inject a person, and switch between drawing and injecting.
//
//   CAPABILITIES(/obj/item/reagent_containers/syringe,
//       reagent_container(volume = nameof(volume), needle = TRUE, sealed = TRUE, settable = FALSE, ...),
//       needle(modes = nameof(mode), needle_time = nameof(time), draws_from = list(...), fills = TRUE))
//
// `modes` names the holder var that holds the mode (NEEDLE_DRAW, NEEDLE_INJECT, NEEDLE_BROKEN, NEEDLE_CAPPED); with none (a dropper) the container draws
// while it is empty and puts out while it holds something. `needle_time` is the time of one injection or blood draw (a number, or a var name of the holder).
// `draws_from` is the types a click draws from besides an open container; `fills` is the types it can put into besides an open container (TRUE: whatever
// atom/is_injectable_container() says).
//
// Ops (all "needle.<name>"):
//   mode        in hand: capped to draw, draw to inject, inject to draw (a broken one is refused)
//   settle      a click on anything that has reagents while the container is full (drawing) or empty (injecting): it switches to the other mode, and says so
//   jammed      a click while broken: it says so
//   draw        a click on a container or tank: one transfer is drawn
//   put_in      a click on a container: one transfer is put in
//   draw_blood  a click on a carbon that is drawn at once (yourself, or somebody with no heart organ); take_blood the same for another, after needle_time
//   inject      a click on a living thing (not in a hostile stance): after two thirds of needle_time, one transfer; then one every third of it until it is empty
//               (while both stand where they stood and it is in the hand)
//
// A refusal is a requirement and says why. What decides WHICH op a click is (the mode, a person or a thing, a full or an empty container) is a condition,
// so the other clicks fall through to the legacy handlers. The transfers are made by the op's effect, so what the person is told is what moved.

CAPABILITY_TYPE(needle, CAP_NEEDLE, /datum/capability/lib/needle, key = NONE, modes = null, needle_time = 30, draws_from = null, fills = null)

MSG_DEF_SELF(needle/broken, "It is broken!")
MSG_DEF_SELF(needle/target_empty, "It is empty.")
MSG_DEF_SELF(needle/target_full, "It is full.")
MSG_DEF_SELF(needle/cannot_remove, "You cannot directly remove reagents from this object.")
MSG_DEF_SELF(needle/cannot_fill, "You cannot directly fill this object.")
MSG_DEF_SELF(needle/blood_present, "There is already a blood sample in this syringe.")
MSG_DEF_SELF(needle/no_dna, "You are unable to locate any blood. (To be specific, your target seems to be missing their DNA datum).")
MSG_DEF_SELF(needle/no_blood, "You are unable to locate any blood.")
MSG_DEF_SELF(needle/synthetic, "You can't draw blood from a synthetic!")
MSG_DEF_SELF(needle/from_belly, "That contains something produced from a belly, and it won't be taken!")
MSG_DEF_SELF(needle/limb_missing, "They are missing that limb.")
MSG_DEF_SELF(needle/limb_robotic, "That limb is robotic.")
MSG_DEF_SELF(needle/limb_lifelike, "Your needle refuses to penetrate more than a short distance...")
MSG_DEF_SELF(needle/too_tough, "The needle can't get through.")
MSG_DEF(needle/begin_inject, "You begin injecting %T% with %I%.", "%U% is trying to inject %T% with %I%!")
MSG_DEF(needle/begin_hunt, "You begin hunting for an injection port on %T%'s suit!", "%U% begins hunting for an injection port on %T%'s suit!")

/datum/capability/lib/needle/entries()
	return list(
		modes ? op("mode", in_hand(), label("Change mode"),
			needs(req(CAP_PROC(not_broken), because = MSG(needle/broken))), then(CAP_PROC(cycled))) : null,
		modes ? op("jammed", at_target(), when(CAP_PROC(target_is_jammed)), priority(OP_PRIORITY_PART + 2), label("Jammed"), then(CAP_PROC(told_broken))) : null,
		modes ? op("settle", at_target(), when(CAP_PROC(target_settles)), priority(OP_PRIORITY_PART + 3), label("Settle"), then(CAP_PROC(settled))) : null,
		op("draw", at_target(), when(CAP_PROC(target_drawable)), priority(OP_PRIORITY_PART + 1), label("Draw"),
			needs(req(CAP_PROC(target_has_reagents), because = MSG(needle/target_empty)), req(CAP_PROC(target_gives), because = MSG(needle/cannot_remove))),
			then(CAP_PROC(drew))),
		op("put_in", at_target(), when(CAP_PROC(target_fillable)), priority(OP_PRIORITY_PART), label("Put in"),
			needs(req(CAP_PROC(target_takes), because = MSG(needle/cannot_fill)), req(CAP_PROC(target_has_room), because = MSG(needle/target_full))),
			then(CAP_PROC(put_in_done))),
		modes ? op("draw_blood", at_target(/mob/living/carbon), when(CAP_PROC(target_bleeds_at_once)), stance(I_HELP, I_DISARM, I_GRAB), priority(OP_PRIORITY_PART), label("Draw blood"),
			needs(req(CAP_PROC(blood_absent), because = MSG(needle/blood_present)), req(CAP_PROC(target_has_dna), because = MSG(needle/no_dna)),
				req(CAP_PROC(target_not_noclone), because = MSG(needle/no_blood)), req(CAP_PROC(target_not_synthetic), because = MSG(needle/synthetic))),
			then(CAP_PROC(blood_drawn))) : null,
		modes ? op("take_blood", at_target(/mob/living/carbon), when(CAP_PROC(target_bleeds_after_a_wait)), stance(I_HELP, I_DISARM, I_GRAB), priority(OP_PRIORITY_PART + 1), label("Take blood"),
			wait(CAP_PROC(blood_wait)),
			needs(req(CAP_PROC(blood_absent), because = MSG(needle/blood_present)), req(CAP_PROC(target_has_dna), because = MSG(needle/no_dna)),
				req(CAP_PROC(target_not_noclone), because = MSG(needle/no_blood)), req(CAP_PROC(target_not_synthetic), because = MSG(needle/synthetic))),
			then(CAP_PROC(blood_drawn))) : null,
		modes ? op("inject", at_target(/mob/living), when(CAP_PROC(target_injectable_person)), stance(I_HELP, I_DISARM, I_GRAB), priority(OP_PRIORITY_PART), label("Inject"),
			begins(CAP_PROC(begin_message)), wait(CAP_PROC(inject_wait)),
			needs(req(CAP_PROC(target_has_room), because = MSG(needle/target_full)), req(CAP_PROC(belly_free), because = MSG(needle/from_belly)),
				req(CAP_PROC(limb_there), because = MSG(needle/limb_missing)), req(CAP_PROC(limb_not_robotic), because = MSG(needle/limb_robotic)),
				req(CAP_PROC(limb_not_lifelike), because = MSG(needle/limb_lifelike)), req(CAP_PROC(skin_open), because = MSG(needle/too_tough))),
			then(CAP_PROC(injected))) : null)

// ---- the mode ----

/// The mode of the holder: its var, or (with none) drawing while it is empty and injecting while it holds something.
/datum/capability/lib/needle/proc/mode_of(atom/holder)
	if(isnull(modes))
		return holder.reagents?.total_volume ? NEEDLE_INJECT : NEEDLE_DRAW
	return holder.vars[modes]

/datum/capability/lib/needle/proc/mode_set(atom/holder, value)
	if(isnull(modes))
		return
	holder.vars[modes] = value // ALLOW(api): a needle's mode is the holder var its capability names, as a setting of the type
	holder.update_icon()

/// How long one injection or blood draw takes (a number, or the name of a var of the holder).
/datum/capability/lib/needle/proc/time_of(atom/holder)
	var/value = needle_time
	if(istext(value))
		value = holder.vars[value]
	return isnum(value) ? value : 30

// ---- conditions: which op a click is (x(datum/act/op/A), pure) ----

/datum/capability/lib/needle/proc/holder_has_room(atom/holder)
	return !!holder.reagents && holder.reagents.get_free_space() > 0

/datum/capability/lib/needle/proc/holder_holds(atom/holder)
	return !!holder.reagents && holder.reagents.total_volume > 0

/datum/capability/lib/needle/proc/target_is_jammed(datum/act/op/A)
	var/atom/target = A.target
	return mode_of(A.holder) == NEEDLE_BROKEN && !isnull(target?.reagents)

/// A full container that is drawing, or an empty one that is injecting, is clicked on anything with reagents: it switches.
/datum/capability/lib/needle/proc/target_settles(datum/act/op/A)
	var/atom/target = A.target
	if(isnull(target?.reagents))
		return FALSE
	switch(mode_of(A.holder))
		if(NEEDLE_DRAW)
			return !holder_has_room(A.holder)
		if(NEEDLE_INJECT)
			return !holder_holds(A.holder)
	return FALSE

/datum/capability/lib/needle/proc/target_drawable(datum/act/op/A)
	var/atom/target = A.target
	return !ismob(target) && !isnull(target?.reagents) && mode_of(A.holder) == NEEDLE_DRAW && holder_has_room(A.holder)

/datum/capability/lib/needle/proc/target_fillable(datum/act/op/A)
	var/atom/target = A.target
	return !ismob(target) && !isnull(target?.reagents) && mode_of(A.holder) == NEEDLE_INJECT && holder_holds(A.holder)

/datum/capability/lib/needle/proc/target_bleeds_at_once(datum/act/op/A)
	return target_bleeds(A) && !blood_needs_a_wait(A.target, A.actor)

/datum/capability/lib/needle/proc/target_bleeds_after_a_wait(datum/act/op/A)
	return target_bleeds(A) && blood_needs_a_wait(A.target, A.actor)

/datum/capability/lib/needle/proc/target_bleeds(datum/act/op/A)
	var/atom/target = A.target
	return !isnull(target?.reagents) && mode_of(A.holder) == NEEDLE_DRAW && holder_has_room(A.holder)

/datum/capability/lib/needle/proc/target_injectable_person(datum/act/op/A)
	var/atom/target = A.target
	return !isnull(target?.reagents) && mode_of(A.holder) == NEEDLE_INJECT && holder_holds(A.holder)

/// A person whose blood is not taken at once: anyone but yourself or a human with no heart to bleed from.
/datum/capability/lib/needle/proc/blood_needs_a_wait(mob/living/carbon/target, mob/user)
	if(!ishuman(target))
		return TRUE
	var/mob/living/carbon/human/H = target
	if(H.species && !H.should_have_organ(O_HEART))
		return FALSE
	return H != user

// ---- requirements: why not (x(datum/act/op/A), pure) ----

/datum/capability/lib/needle/proc/not_broken(datum/act/op/A)
	return mode_of(A.holder) != NEEDLE_BROKEN

/datum/capability/lib/needle/proc/target_has_reagents(datum/act/op/A)
	var/atom/target = A.target
	return !!target?.reagents?.total_volume

/// What the container may draw from: any open container, a tank or what else it was declared to draw from.
/datum/capability/lib/needle/proc/target_gives(datum/act/op/A)
	var/atom/target = A.target
	if(target.is_open_container())
		return TRUE
	for(var/type in draws_from)
		if(istype(target, type))
			return TRUE
	return FALSE

/// What the container may put into: any open container, and what it was declared to fill.
/datum/capability/lib/needle/proc/target_takes(datum/act/op/A)
	var/atom/target = A.target
	if(target.is_open_container())
		return TRUE
	if(fills == TRUE)
		var/atom/movable/thing = target
		return istype(thing) && thing.is_injectable_container()
	for(var/type in fills)
		if(istype(target, type))
			return TRUE
	return FALSE

/datum/capability/lib/needle/proc/target_has_room(datum/act/op/A)
	var/atom/target = A.target
	return !!target?.reagents && target.reagents.get_free_space() > 0

/datum/capability/lib/needle/proc/blood_absent(datum/act/op/A)
	var/atom/holder = A.holder
	return !holder.reagents.has_reagent(REAGENT_ID_BLOOD)

/datum/capability/lib/needle/proc/target_has_dna(datum/act/op/A)
	var/mob/living/carbon/target = A.target
	return !!target.dna

/datum/capability/lib/needle/proc/target_not_noclone(datum/act/op/A)
	var/mob/living/carbon/target = A.target
	return !target.has_mutation(NOCLONE)

/datum/capability/lib/needle/proc/target_not_synthetic(datum/act/op/A)
	var/mob/living/carbon/target = A.target
	return !HAS_SYNTHETIC_BIOLOGY(target)

/// Whatever the container holds was not produced from a belly, or the one injected takes such things.
/datum/capability/lib/needle/proc/belly_free(datum/act/op/A)
	var/mob/living/target = A.target
	return !ishuman(target) || target.consume_liquid_belly || !reagents_from_belly(A.holder)

/// The limb the injector aims at (a person other than the one injecting): the aimed organ, or null.
/datum/capability/lib/needle/proc/limb_aimed(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	var/mob/user = A.actor
	if(!ishuman(target) || target == user || !user?.zone_sel)
		return null
	return target.get_organ(user.zone_sel.selecting)

/datum/capability/lib/needle/proc/aimed_at_a_human(datum/act/op/A)
	var/mob/living/target = A.target
	var/mob/user = A.actor
	return ishuman(target) && target != user && !isnull(user?.zone_sel)

/datum/capability/lib/needle/proc/limb_there(datum/act/op/A)
	if(!aimed_at_a_human(A))
		return TRUE
	var/mob/living/carbon/human/target = A.target
	var/mob/user = A.actor
	return !!target.get_organ(user.zone_sel.selecting)

/datum/capability/lib/needle/proc/limb_not_robotic(datum/act/op/A)
	var/obj/item/organ/external/affected = limb_aimed(A)
	return isnull(affected) || affected.robotic != ORGAN_ROBOT

/datum/capability/lib/needle/proc/limb_not_lifelike(datum/act/op/A)
	var/obj/item/organ/external/affected = limb_aimed(A)
	return isnull(affected) || affected.robotic < ORGAN_LIFELIKE || affected.robotic == ORGAN_ROBOT

/// The needle can get into this one: a living thing that is not a person next to the injector says by its own can_inject() (armour, an armoured plating).
/datum/capability/lib/needle/proc/skin_open(datum/act/op/A)
	var/mob/living/target = A.target
	if(ishuman(target) || target == A.actor)
		return TRUE
	return !!target.can_inject(null, 0)

// ---- waits ----

/// The time before somebody else's blood comes.
/datum/capability/lib/needle/proc/blood_wait(datum/act/op/A)
	return time_of(A.holder)

/// The warmup of an injection: two thirds of the time for somebody else, a third for yourself.
/datum/capability/lib/needle/proc/inject_wait(datum/act/op/A)
	return time_of(A.holder) * (A.target == A.actor ? 0.33 : 0.66)

/// What the one who begins to inject is seen to do: a suit worn over the target (a space suit) is hunted through for a port.
/datum/capability/lib/needle/proc/begin_message(datum/act/op/A)
	var/mob/living/target = A.target
	if(target == A.actor)
		return null
	if(ishuman(target))
		var/mob/living/carbon/human/H = target
		if(istype(H.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/space))
			return MSG(needle/begin_hunt)
	return MSG(needle/begin_inject)

// ---- effects (x(datum/act/op/A) -> OP_*) ----

/// Used in hand: capped, draw, inject, draw.
/datum/capability/lib/needle/proc/cycled(datum/act/op/A)
	var/atom/holder = A.holder
	switch(mode_of(holder))
		if(NEEDLE_CAPPED)
			mode_set(holder, NEEDLE_DRAW)
			holder.balloon_alert(A.actor, "[holder] uncapped")
		if(NEEDLE_DRAW)
			mode_set(holder, NEEDLE_INJECT)
		if(NEEDLE_INJECT)
			mode_set(holder, NEEDLE_DRAW)
	return OP_OK

/datum/capability/lib/needle/proc/told_broken(datum/act/op/A)
	to_chat(A.actor, span_warning("[A.holder] is broken!"))
	return OP_OK

/datum/capability/lib/needle/proc/settled(datum/act/op/A)
	var/atom/holder = A.holder
	if(mode_of(holder) == NEEDLE_DRAW)
		to_chat(A.actor, span_warning("[holder] is full."))
		mode_set(holder, NEEDLE_INJECT)
	else
		to_chat(A.actor, span_notice("[holder] is empty."))
		mode_set(holder, NEEDLE_DRAW)
	return OP_OK

/// One transfer is drawn from the container or tank. A syringe that is full after it is set to inject.
/datum/capability/lib/needle/proc/drew(datum/act/op/A)
	var/atom/holder = A.holder
	var/atom/target = A.target
	var/mob/user = A.actor
	var/trans = target.reagents.trans_to_obj(holder, reagent_transfer_amount(holder), user = user)
	to_chat(user, span_notice("You fill [holder] with [trans] units of the solution."))
	holder.update_icon()
	if(!isnull(modes) && !holder.reagents.get_free_space())
		mode_set(holder, NEEDLE_INJECT)
	return OP_OK

/// One transfer is put into the container. A syringe that is empty after it is set to draw.
/datum/capability/lib/needle/proc/put_in_done(datum/act/op/A)
	var/atom/holder = A.holder
	var/atom/target = A.target
	var/mob/user = A.actor
	var/trans = holder.reagents.trans_to_obj(target, reagent_transfer_amount(holder), user = user)
	if(isnull(modes))
		to_chat(user, span_notice("You transfer [trans] units of the solution."))
		return OP_OK
	if(holder.reagents.total_volume <= 0 && mode_of(holder) == NEEDLE_INJECT)
		mode_set(holder, NEEDLE_DRAW)
	to_chat(user, span_notice("You inject [trans] units of the solution. [holder] now contains [holder.reagents.total_volume] units."))
	return OP_OK

/// Blood is taken: from the person's veins, or (a person with no heart) from what their holder has. A full syringe is set to inject.
/datum/capability/lib/needle/proc/blood_drawn(datum/act/op/A)
	var/atom/holder = A.holder
	var/mob/living/carbon/target = A.target
	var/mob/user = A.actor
	var/amount = holder.reagents.get_free_space()
	if(amount <= 0)
		return OP_REFUSED
	if(ishuman(target))
		var/mob/living/carbon/human/H = target
		if(H.species && !H.should_have_organ(O_HEART))
			H.reagents.trans_to_obj(holder, amount, user = user)
			return blood_taken(holder, target, user)
	var/datum/reagent/B = target.take_blood(holder, amount)
	if(B)
		holder.reagents.adopt_reagent(B)
		holder.reagents.update_total()
		holder.on_reagent_change()
		holder.reagents.handle_reactions()
	return blood_taken(holder, target, user)

/datum/capability/lib/needle/proc/blood_taken(atom/holder, mob/living/carbon/target, mob/user)
	to_chat(user, span_notice("You take a blood sample from [target]."))
	for(var/mob/O in viewers(4, user))
		O.show_message(span_notice("[user] takes a blood sample from [target]."), 1)
	if(!holder.reagents.get_free_space())
		mode_set(holder, NEEDLE_INJECT)
	return OP_OK

/// The needle goes in: the thick hide of some species turns it away (a roll, as the injector's old check made, for somebody else), else the first transfer
/// goes into the blood now and the rest follow, one every third of the time, as long as both stand where they stood and the container is in the hand.
/datum/capability/lib/needle/proc/injected(datum/act/op/A)
	var/atom/holder = A.holder
	var/mob/living/target = A.target
	var/mob/user = A.actor
	if(aimed_at_a_human(A))
		var/mob/living/carbon/human/H = target
		var/obj/item/organ/external/affected = H.get_organ(user.zone_sel.selecting)
		if(affected && H.thick_skin_holds(affected))
			to_chat(user, span_warning("Your needle fails to penetrate \the [affected]'s thick hide..."))
			return OP_REFUSED
	user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)
	var/contained = holder.reagents.get_reagents()
	var/trans = holder.reagents.trans_to_mob(target, reagent_transfer_amount(holder), CHEM_BLOOD) || 0
	holder.update_icon()
	if(holder.reagents.total_volume > 0)
		var/cycle = time_of(holder) * 0.33
		after(holder, cycle, GLOBAL_PROC_REF(needle_inject_cycle), key = "needle_inject:[REF(target)]", \
			with = list(holder, user, target, cycle, trans, contained, modes, user.loc, target.loc, user.get_active_hand()))
		return OP_OK
	needle_inject_finish(holder, user, target, trans, contained, modes)
	return OP_OK

/// A later cycle of an injection: one more transfer if the one injecting, the one injected and the container are where they were; the end of it otherwise.
/proc/needle_inject_cycle(atom/holder, mob/user, mob/living/target, cycle, trans, contained, modes, user_loc, target_loc, held)
	if(QDELETED(holder) || !holder.reagents)
		return
	if(QDELETED(user) || QDELETED(target) || user.loc != user_loc || target.loc != target_loc || user.get_active_hand() != held || !holder.reagents.total_volume)
		needle_inject_finish(holder, user, target, trans, contained, modes)
		return
	trans += holder.reagents.trans_to_mob(target, reagent_transfer_amount(holder), CHEM_BLOOD) || 0
	holder.update_icon()
	if(holder.reagents.total_volume > 0)
		after(holder, cycle, GLOBAL_PROC_REF(needle_inject_cycle), key = "needle_inject:[REF(target)]", with = list(holder, user, target, cycle, trans, contained, modes, user_loc, target_loc, held), keeps_dead = TRUE)
		return
	needle_inject_finish(holder, user, target, trans, contained, modes)

/// An injection is over (all of it gone in, or cut short): an emptied syringe is set to draw, and the one injecting is told what went in.
/proc/needle_inject_finish(atom/holder, mob/user, mob/living/target, trans, contained, modes)
	if(QDELETED(holder) || !holder.reagents)
		return
	if(!isnull(modes) && holder.reagents.total_volume <= 0 && holder.vars[modes] == NEEDLE_INJECT)
		holder.vars[modes] = NEEDLE_DRAW // ALLOW(api): a needle's mode is the holder var its capability names, as a setting of the type
		holder.update_icon()
	if(QDELETED(user))
		return
	if(trans)
		to_chat(user, span_notice("You inject [trans] units of the solution. [holder] now contains [holder.reagents.total_volume] units."))
		if(ismob(target))
			add_attack_logs(user, target, "Injected with [holder.name] containing [contained], trasferred [trans] units")
	else
		to_chat(user, span_notice("[holder] is empty."))
