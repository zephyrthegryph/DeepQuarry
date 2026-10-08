/mob/living/carbon/resist_fire()
	adjust_fire_stacks(-1.2)
	status_at_least(STAT_WEAKENED, 3)
	spin(32,2)
	act_message(src, null, MSG_SELF(span_notice("You stop, drop, and roll!")), MSG_OTHERS(span_danger("%U% rolls on the floor, trying to put themselves out!")))
	after(src, 3 SECONDS, PROC_REF(resist_fire_done))
	return TRUE

/mob/living/carbon/proc/resist_fire_done()
	if(fire_stacks <= 0)
		act_message(src, null, MSG_SELF(span_notice("You extinguish yourself.")), MSG_OTHERS(span_danger("%U% has successfully extinguished themselves!")))
		extinguish_mob()
	return TRUE

/// The restraint the resisting job works on: the handcuffs, else the legcuffs.
/mob/living/carbon/proc/resist_cuffs()
	var/obj/item/I = get_equipped_item(SLOT_ID_HANDCUFFED)
	if(!I)
		I = get_equipped_item(SLOT_ID_LEGCUFFED)
	return I

/mob/living/carbon/resist_restraints()
	var/obj/item/I = resist_cuffs()
	if(I)
		setClickCooldown(100)
		perform_op(src, src, can_break_cuffs() ? "cuff_break" : "cuff_remove", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)

/mob/living/carbon/proc/reduce_cuff_time()
	return FALSE

/// Deciseconds the restraint takes to slip: its breakouttime, shortened by whatever helps (reduce_cuff_time()).
/mob/living/carbon/proc/cuff_breakout_time(datum/act/op/A)
	var/breakouttime = 1200
	var/obj/item/handcuffs/I = resist_cuffs()
	if(istype(I))
		breakouttime = I.breakouttime
	var/reduceCuffTime = reduce_cuff_time()
	if(reduceCuffTime)
		breakouttime /= reduceCuffTime
	return breakouttime

/mob/living/carbon/proc/cuff_break_text(datum/act/op/A)
	var/obj/item/I = resist_cuffs()
	return msg_text(span_warning("You attempt to break your [I]. (This will take around 5 seconds and you need to stand still)"), span_danger("%U% is trying to break [I]!"))

/mob/living/carbon/proc/cuff_remove_text(datum/act/op/A)
	var/obj/item/I = resist_cuffs()
	var/displaytime = cuff_breakout_time(A) / 10
	return msg_text(span_warning("You attempt to remove [I]. (This will take around [displaytime] seconds and you need to stand still)"), span_danger("%U% attempts to remove [I]!"))

/mob/living/carbon/proc/cuff_break_done(datum/act/op/A)
	var/obj/item/I = resist_cuffs()
	if(!I || src?.buckled_to())
		return
	act_message(src, null, MSG_SELF(span_warning("You successfully break your [I].")), MSG_OTHERS(span_danger("%U% manages to break [I]!")))
	say(pick(";RAAAAAAAARGH!", ";HNNNNNNNNNGGGGGGH!", ";GWAAAAAAAARRRHHH!", "NNNNNNNNGGGGGGGGHH!", ";AAAAAAARRRGH!" ))

	drop_from_inventory(I)

	var/obj/buckled = src?.buckled_to()
	if(buckled && buckled.buckle_require_restraints)
		buckled.unbuckle_mob()

	spent(I)

/mob/living/carbon/proc/cuff_break_failed(datum/act/op/A)
	to_chat(src, span_warning("You fail to break [resist_cuffs()]."))

/mob/living/carbon/proc/cuff_remove_done(datum/act/op/A)
	var/obj/item/I = resist_cuffs()
	if(!I)
		return
	act_message(src, null, MSG_SELF(span_notice("You successfully remove [I].")), MSG_OTHERS(span_danger("%U% manages to remove [I]!")))
	drop_from_inventory(I)

/mob/living/carbon/resist_buckle()
	if(!src?.buckled_to())
		return

	if(!restrained())
		return ..()

	setClickCooldown(100)
	perform_op(src, src, "buckle_escape", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)

/mob/living/carbon/proc/buckle_escape_text(datum/act/op/A)
	return msg_text(span_warning("You attempt to unbuckle yourself. (This will take around 2 minutes and you need to stand still)"), span_danger("%U% attempts to unbuckle themself!"))

/mob/living/carbon/proc/buckle_escape_done(datum/act/op/A)
	var/obj/buckled = src?.buckled_to()
	if(!buckled)
		return
	act_message(src, null, MSG_SELF(span_notice("You successfully unbuckle yourself.")), MSG_OTHERS(span_danger("%U% manages to unbuckle themself!")))
	buckled.user_unbuckle_mob(src, src)

/mob/living/carbon/proc/can_break_cuffs()
	if(has_mutation(HULK))
		return 1
