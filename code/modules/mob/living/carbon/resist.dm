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

/mob/living/carbon/resist_restraints()
	var/obj/item/I = null
	if(get_equipped_item(SLOT_ID_HANDCUFFED))
		I = get_equipped_item(SLOT_ID_HANDCUFFED)
	else if(get_equipped_item(SLOT_ID_LEGCUFFED))
		I = get_equipped_item(SLOT_ID_LEGCUFFED)

	if(I)
		setClickCooldown(100)
		cuff_resist(I, cuff_break = can_break_cuffs())

/mob/living/carbon/proc/reduce_cuff_time()
	return FALSE

/mob/living/carbon/proc/cuff_resist(obj/item/handcuffs/I, breakouttime = 1200, cuff_break = 0)

	if(istype(I))
		breakouttime = I.breakouttime

	var/displaytime = breakouttime / 10

	var/reduceCuffTime = reduce_cuff_time()
	if(reduceCuffTime)
		breakouttime /= reduceCuffTime
		displaytime /= reduceCuffTime

	if(cuff_break)
		act_message(src, null, MSG_SELF(span_warning("You attempt to break your [I]. (This will take around 5 seconds and you need to stand still)")), \
			MSG_OTHERS(span_danger("%U% is trying to break [I]!")))

		task_timed(src, 5 SECONDS, target = src, timed_action_flags = IGNORE_INCAPACITATED, receiver = src, on_done = PROC_REF(cuff_resist_carbon_done), done_args = list(I), on_fail = PROC_REF(cuff_resist_carbon_failed), fail_args = list(I))
		return

	act_message(src, null, MSG_SELF(span_warning("You attempt to remove [I]. (This will take around [displaytime] seconds and you need to stand still)")), \
		MSG_OTHERS(span_danger("%U% attempts to remove [I]!")))
	task_timed(src, breakouttime, target = src, timed_action_flags = IGNORE_INCAPACITATED, receiver = src, on_done = PROC_REF(cuff_resist_carbon_done2), done_args = list(I))

/mob/living/carbon/proc/cuff_resist_carbon_done(obj/item/handcuffs/I)
	if(!I || src?.buckled_to())
		return
	act_message(src, null, MSG_SELF(span_warning("You successfully break your [I].")), MSG_OTHERS(span_danger("%U% manages to break [I]!")))
	say(pick(";RAAAAAAAARGH!", ";HNNNNNNNNNGGGGGGH!", ";GWAAAAAAAARRRHHH!", "NNNNNNNNGGGGGGGGHH!", ";AAAAAAARRRGH!" ))

	drop_from_inventory(I)

	var/obj/buckled = src?.buckled_to()
	if(buckled && buckled.buckle_require_restraints)
		buckled.unbuckle_mob()

	spent(I)

/mob/living/carbon/proc/cuff_resist_carbon_failed(obj/item/handcuffs/I)
	to_chat(src, span_warning("You fail to break [I]."))
/mob/living/carbon/proc/cuff_resist_carbon_done2(obj/item/handcuffs/I)
	act_message(src, null, MSG_SELF(span_notice("You successfully remove [I].")), MSG_OTHERS(span_danger("%U% manages to remove [I]!")))
	drop_from_inventory(I)

/mob/living/carbon/resist_buckle()
	if(!src?.buckled_to())
		return

	if(!restrained())
		return ..()

	setClickCooldown(100)
	act_message(src, null, MSG_SELF(span_warning("You attempt to unbuckle yourself. (This will take around 2 minutes and you need to stand still)")), \
		MSG_OTHERS(span_danger("%U% attempts to unbuckle themself!")))

	task_timed(src, 2 MINUTES, target = src, timed_action_flags = IGNORE_INCAPACITATED, receiver = src, on_done = PROC_REF(resist_buckle_carbon_done), done_args = list())

/mob/living/carbon/proc/resist_buckle_carbon_done()
	var/obj/buckled = src?.buckled_to()
	if(!buckled)
		return
	act_message(src, null, MSG_SELF(span_notice("You successfully unbuckle yourself.")), MSG_OTHERS(span_danger("%U% manages to unbuckle themself!")))
	buckled.user_unbuckle_mob(src, src)

/mob/living/carbon/proc/can_break_cuffs()
	if(has_mutation(HULK))
		return 1
