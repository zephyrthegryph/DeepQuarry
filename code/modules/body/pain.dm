/mob/proc/flash_pain()
	flick("pain",pain)

/datum/body
	/// The last pain message the person was shown (a repeat waits for its cooldown).
	var/last_pain_message = ""
	/// COOLDOWN: the next pain message.
	var/next_pain_time = 0
	/// COOLDOWN: the next message about a hurt limb, so several hurt limbs don't spam.
	var/multilimb_pain_time = 0


// message is the custom message to be displayed
// power decides how much painkillers will stop the message
// force means it ignores anti-spam timer
/mob/living/carbon/proc/custom_pain(message, power, force)
	if(!body)
		return 0
	if((!message || stat || !can_feel_pain() || factor(BF_ANALGESIA) > power) && !synth_cosmetic_pain)
		return 0
	message = span_danger("[message]")
	if(power >= 50)
		message = span_large("[message]")

	// Anti message spam checks
	// If multiple limbs are injured, cooldown is ignored to print all injuries until all limbs are iterated over
	if(client?.prefs?.read_preference(/datum/preference/toggle/pain_frequency))
		switch(power)
			if(0 to 5)
				force = 0
			if(6 to 20)
				force = prob(1)
		if(force || (message != body.last_pain_message) || (COOLDOWN_FINISHED(body, next_pain_time)))
			switch(power)
				if(0 to 5)
					COOLDOWN_START(body, next_pain_time, 300 SECONDS)
					COOLDOWN_START(body, multilimb_pain_time, 1 MINUTE)
				if(6 to 20)
					COOLDOWN_START(body, next_pain_time, clamp((100 - power) SECONDS, 80 SECONDS, 95 SECONDS))
					COOLDOWN_START(body, multilimb_pain_time, clamp((100 - power) SECONDS, 80 SECONDS, 95 SECONDS))
				if(21 to INFINITY)
					COOLDOWN_START(body, next_pain_time, clamp((200 - power) SECONDS, 100 SECONDS, 3 MINUTES))
					COOLDOWN_START(body, multilimb_pain_time, clamp((200 - power) SECONDS, 100 SECONDS, 3 MINUTES))
			body.last_pain_message = message
			to_chat(src,message)
			// Emote in pain for custom pain, too
			if(prob(power / 10) && !isbelly(loc)) // No pain noises inside bellies.
				emote("pain")

	else if(force || (message != body.last_pain_message) || (COOLDOWN_FINISHED(body, next_pain_time)))
		body.last_pain_message = message
		to_chat(src,message)
		COOLDOWN_START(body, next_pain_time, (10 SECONDS - power))
		COOLDOWN_START(body, multilimb_pain_time, (10 SECONDS - power))
		// Emote in pain for custom pain, too
		if(prob(power / 10) && !isbelly(loc)) // No pain noises inside bellies.
			emote("pain")

// Pain messages (doc/rewrite/body_migration.md, slice 4). How much a body hurts is derived in its vitals; what the
// person is told about it is periodic, so it is an every(LIFE_CYCLE) per human gated by STAT_PAIN_FELT, which the body
// holds while it carries afflictions and is alive.

/// TRUE while the body has afflictions to hurt from: the body holds it.
STAT(/mob/living/carbon/human, pain_felt, ANY)

/// The pain messages' entries, for the human's CAPABILITIES block: `active` is STAT_PAIN_FELT.
/proc/pain_clock(active)
	return every(LIFE_CYCLE, then(TYPE_PROC_REF(/mob/living/carbon/human, pain_tick)), when = active)

/mob/living/carbon/human/proc/pain_tick(datum/act/timer/A)
	pain_step()

/mob/living/carbon/human/proc/pain_refresh()
	if(QDELETED(src))
		return
	body_hold_flag(STAT_PAIN_FELT, is_alive() && LAZYLEN(body?.afflictions))

/// Pain messages from limbs and organs.
/mob/living/carbon/human/proc/pain_step()
	var/mob/living/carbon/human/self = src
	if(self.stat)
		return

	if(!self.can_feel_pain() && !self.synth_cosmetic_pain)
		return

	if(!COOLDOWN_FINISHED(self.body, multilimb_pain_time)) //prevents spam in case of multi-limb injuries.
		return
	var/maxdam = 0
	var/obj/item/organ/external/damaged_organ = null
	for(var/obj/item/organ/external/E in self.organs)
		if(!E.organ_can_feel_pain() && !self.synth_cosmetic_pain) continue
		var/dam = E.get_damage()
		// make the choice of the organ depend on damage,
		// but also sometimes use one of the less damaged ones
		if(dam > maxdam && (maxdam == 0 || prob(70)) )
			damaged_organ = E
			maxdam = dam
	// D22: the species scaling applies once, after the pick (inside the loop it compared scaled
	// against unscaled damage), and the level is rounded so fractions still hit a message band.
	maxdam = round(maxdam * (self.species ? self.species.trauma_mod : 1))
	if(damaged_organ && self.factor(BF_ANALGESIA) < maxdam)
		if(maxdam > 10 && self.has_status(STAT_PARALYZED))
			self.status_adjust(STAT_PARALYZED, -round(maxdam/10))
		if(maxdam > 50 && prob(maxdam / 5))
			self.drop_item()
		var/burning = damaged_organ.get_burn() > damaged_organ.get_trauma()
		var/msg
		switch(maxdam)
			if(1 to 10)
				msg =  "Your [damaged_organ.name] [burning ? "burns" : "hurts"]."
			if(11 to 90)
				self.flash_weak_pain()
				msg = span_normal("Your [damaged_organ.name] [burning ? "burns" : "hurts"] badly!")
			if(91 to 10000)
				self.flash_pain()
				msg = span_large("OH GOD! Your [damaged_organ.name] is [burning ? "on fire" : "hurting terribly"]!")
		self.custom_pain(msg, maxdam, prob(10))

	// Damage to internal organs hurts a lot.
	for(var/obj/item/organ/I in self.internal_organ_list())
		if((I.status & ORGAN_DEAD) || I.is_robotic()) continue
		if(I.damage > 2) if(prob(2))
			var/obj/item/organ/external/parent = self.get_organ(I.parent_organ)
			if(parent) // D22: the parent limb can be gone
				self.custom_pain("You feel a sharp pain in your [parent.name]", 50)

	if(prob(2))
		var/toxic = self.injury_load(INJURY_CATEGORY_TOXIC)
		switch(toxic)
			if(1 to 10)
				self.custom_pain("Your body stings slightly.", toxic)
			if(11 to 30)
				self.custom_pain("Your body hurts a little.", toxic)
			if(31 to 60)
				self.custom_pain("Your whole body hurts badly.", toxic)
			if(61 to INFINITY)
				self.custom_pain("Your body aches all over, it's driving you mad.", toxic)
