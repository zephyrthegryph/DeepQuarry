/obj/item/implant/neural
	name = "neural framework implant"
	desc = "A small metal casing with numerous wires stemming off of it."
	initialize_loc = BP_HEAD
	var/obj/item/organ/internal/brain/my_brain
	var/target_state = null
	var/robotic_brain = FALSE

/// TRUE while it assists a brain and watches for it being ripped out; a meltdown ends it.
/obj/item/implant/neural/var/monitoring_brain = FALSE
TRACKED(/obj/item/implant/neural, monitoring_brain)
CAPABILITIES(/obj/item/implant/neural)
	every(2 SECONDS, then(PROC_REF(neural_step)), when = nameof(monitoring_brain))
	extend(/datum/act/hit/emp, instead(then(PROC_REF(neural_implant_emp))))

/obj/item/implant/neural/post_implant(mob/source)
	if(ishuman(source))
		var/mob/living/carbon/human/H = source
		if(H.species.has_organ[O_BRAIN])
			var/obj/item/organ/internal/brain/possible_brain = H.organ_in(O_BRAIN)
			rel_set(src, nameof(my_brain), possible_brain) //Organs will take damage all the same.
			if(istype(possible_brain) && my_brain().can_assist())		//If the brain is infact a brain, and not something special like an MMI.
				my_brain().implant_assist(target_state)
		if(HAS_SYNTHETIC_BIOLOGY(H) && H.get_FBP_type() != FBP_CYBORG)		//If this on an FBP, it's just an extra inefficient attachment to whatever their brain is.
			robotic_brain = TRUE
	if(istype(my_brain(), /obj/item/organ/internal/brain) && my_brain().can_assist())
		set_monitoring_brain(TRUE)

// the brain's owner feels it ripped away.
/obj/item/implant/neural/on_destroy(force)
	if(my_brain()?.owner)
		to_chat(my_brain().owner, span_critical("You feel a pressure in your mind as something is ripped away."))
	..()

/obj/item/implant/neural/proc/neural_step(datum/act/timer/A)
	if(my_brain() && part)
		if(my_brain().loc != part.loc)
			to_chat(my_brain().owner, span_critical("You feel a pressure in your mind as something is ripped away."))
			meltdown()
	return 1

/obj/item/implant/neural/get_data()
	var/dat = {"<b>Implant Specifications:</b><BR>
<b>Name:</b> Neural Framework Implant<BR>
<b>Life:</b> Duration of Brain Function<BR>
<b>Important Notes:</b> None<BR>
<HR>
<b>Implant Details:</b> <BR>
<b>Function:</b> Maintains some function or structure of the target's brain.<BR>
<b>Special Features:</b><BR>
<i>Neuro-Safe</i>- Specialized shell absorbs excess voltages self-destructing the chip if
a malfunction occurs thereby attempting to secure the safety of subject.<BR>
<b>Integrity:</b> Gradient creates slight risk of being overcharged and frying the
circuitry. Resulting faults can cause damage to the host's brain.<HR>
Implant Specifics:<BR>"}
	return dat

/// An EMP makes the implant malfunction and hurt the brain it sits in.
/obj/item/implant/neural/proc/neural_implant_emp(datum/act/hit/emp/A)
	var/datum/damage_packet/packet = A.packet
	if(!my_brain() || malfunction)
		return HOOK_DECLINE
	malfunction = MALFUNCTION_TEMPORARY

	var/delay = 10 //Don't let it just get emped twice in a second to kill someone.
	var/brain_location = my_brain().owner.organs_by_name[my_brain().parent_organ]
	var/mob/living/L = my_brain().owner
	switch(packet.severity)
		if(1)
			if(prob(10))
				meltdown()
			else if(prob(80))
				L.injure(INJURY_NEURAL, 5, my_brain(), src)
				if(!robotic_brain)
					to_chat(L, span_critical("Something in your [brain_location] burns!"))
				else
					to_chat(L, span_warning("Severe fault detected in [brain_location]."))
		if(2)
			if(prob(80))
				L.injure(INJURY_NEURAL, 3, my_brain(), src)
				if(!robotic_brain)
					to_chat(L, span_danger("It feels like something is digging into your [brain_location]!"))
				else
					to_chat(L, span_warning("Fault detected in [brain_location]."))
		if(3)
			if(prob(60))
				L.injure(INJURY_NEURAL, 2, my_brain(), src)
				if(!robotic_brain)
					to_chat(L, span_warning("There is a stabbing pain in your [brain_location]!"))
		if(4)
			if(prob(40))
				L.injure(INJURY_NEURAL, 1, my_brain(), src)
				if(!robotic_brain)
					to_chat(L, span_warning("Your [brain_location] aches."))

	after(src, delay, PROC_REF(malfunction_recover))
	return HOOK_DECLINE

/obj/item/implant/neural/meltdown()
	..()
	set_monitoring_brain(FALSE)
	var/mob/living/carbon/human/H = null
	if(my_brain() && my_brain().owner)
		if(ishuman(my_brain().owner))
			H = my_brain().owner
			if(robotic_brain)
				to_chat(H, span_critical("WARNING. Fault dete-ct-- in the \the [src]."))
			H.status_at_least(STAT_CONFUSED, 30)
			H.status_adjust(STAT_BLINDED, 5)
		my_brain().owner?.injure(INJURY_NEURAL, 15, my_brain(), src)
		rel_clear(src, nameof(my_brain))
	return

/// Relation view: my brain (reads null once it is gone).
/obj/item/implant/neural/proc/my_brain() as /obj/item/organ/internal/brain
	return my_brain
