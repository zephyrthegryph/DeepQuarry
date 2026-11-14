///////////////////////////////////////////////////////////////////////
//Shoes
/obj/item/clothing/shoes
	name = DEVELOPER_WARNING_NAME // "shoes"
	icon = 'icons/inventory/feet/item.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_shoes.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_shoes.dmi',
		)
	desc = "Comfortable-looking shoes."
	gender = PLURAL //Carn: for grammarically correct text-parsing
	blood_sprite_state = "shoeblood"

	var/can_hold_knife = 0
	var/obj/item/holding // owned: the knife tucked in the boot, kept in its contents

	var/shoes_under_pants = 0

	var/water_speed = 0		//Speed boost/decrease in water, lower/negative values mean more speed
	var/snow_speed = 0		//Speed boost/decrease on snow, lower/negative values mean more speed

	var/step_volume_mod = 1	//How quiet or loud footsteps in this shoe are
	// owned: the shoes worn under these (magboots), kept in their contents
	var/obj/item/clothing/shoes/shoes = null	//If we are wearing shoes in our shoes. Used primarily for magboots.
	var/blocks_footsteps = TRUE //Does this shoe block custom footstep sounds?

	var/overshoes = 0
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/feet/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/feet/mob_vox.dmi',
		SPECIES_WEREBEAST = 'icons/inventory/feet/mob_werebeast.dmi'
		)

	update_icon_define_digi = 'icons/inventory/feet/mob_digi.dmi'
	var/list/inside_emotes
	COOLDOWN_DECLARE(recent_squish)

MSG_DEF_SELF(shoes/layer_locked, "It cannot be worn above your suit.")

CAPABILITIES(/obj/item/clothing/shoes)
	configure(item_worn(worn_factors = alist(STAT_ITEM_ENCUMBRANCE = SHOES_SLOWDOWN)))
	fits_as(FIT_NO_TESHARI_VOX)
	configure(item_worn(covers = FEET, slots = SLOT_FEET))
	configure(item_combat(force = 2))
	configure(item_protection(siemens = 0.9, heat_parts = FEET, cold_parts = FEET, permeability = 0.50))
	configure(item_sounds(drop = SFX_ITEMS_DROP_SHOES, pickup = SFX_ITEMS_PICKUP_SHOES))
	// A micro climbing out of the shoes (container_resist()): they are inside them, so what is kept is that the shoes stay where they were and the micro stays put.
	op("micro_climb_out", ai(), needs(req_capable()), wait(5 SECONDS, keeps = HELD | TARGET_PRESENT | ALIVE | STAY), then(PROC_REF(micro_climbed_out)))
	op("micro_escape_macro", ai(), needs(req_capable()), takes("macro", "time"), wait(PROC_REF(micro_escape_time), keeps = HELD | TARGET_PRESENT | ALIVE | STAY), on_interrupt(PROC_REF(micro_pinned)), then(PROC_REF(micro_escaped_macro)))
	owns_one(nameof(shoes), /obj/item/clothing/shoes)
	owns_one(nameof(squeak), /datum/squeak)
	owns_one(nameof(holding), /obj/item)
	op("drag", item(/atom/movable), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 2), label("Drop onto"), then(PROC_REF(interaction_drag)))
	op("shoes_draw_knife_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 2), label("Shoes draw knife hand"), then(PROC_REF(shoes_draw_knife_hand)))
	op("shoes_shake_out_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 2), label("Shoes shake out self"), then(PROC_REF(shoes_shake_out_self)))
	op("shoes_stuff_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 2), label("Shoes stuff item"), then(PROC_REF(shoes_stuff_item)))
	op("shoes_toggle_layer_verb", menu(), label("Switch Shoe Layer"), needs(carried(), req_not(req_is(nameof(shoes_under_pants), -1), because = MSG(shoes/layer_locked))), then(PROC_REF(shoes_toggle_layer_verb)))
	op("shoes_draw_knife_verb", menu(), label("Draw Boot Knife"), needs(carried(), req(PROC_REF(pred_holding_knife_holds))), then(PROC_REF(shoes_draw_knife_verb)))
	setup(PROC_REF(set_inside_emotes))

/// Native requirement: return null or the component refusal.
/obj/item/clothing/shoes/proc/pred_holding_knife_holds(datum/act/op/A)
	return holding ? null : "there is no knife in it"

/// What a micro inside the shoes feels, naming the shoes.
/obj/item/clothing/shoes/proc/set_inside_emotes()
	inside_emotes = list(
		span_red("You feel weightless for a moment as \the [name] moves upwards."),
		span_red("\The [name] are a ride you've got no choice but to participate in as the wearer moves."),
		span_red("The wearer of \the [name] moves, pressing down on you."),
		span_red("More motion while \the [name] move, feet pressing down against you.")
	)

/// Old verb "Draw Boot Knife" (offered while a knife is held).
/obj/item/clothing/shoes/proc/shoes_draw_knife_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(isliving(user))
		draw_knife(user)

/obj/item/clothing/shoes/proc/draw_knife(mob/living/user)
	if(user.stat || user.restrained() || user.incapacitated())
		return

	holding.forceMove(get_turf(user))

	if(user.put_in_hands(holding))
		act_message(user, null, others = span_danger("%U% pulls a knife out of their boot!"))
		play_sfx(src, SFX_WEAPONS_HOLSTER_SHEATHOUT, 0.5, vary = FALSE)
		rel_take(src, nameof(holding))
	else
		to_chat(user, span_warning("Your need an empty, unbroken hand to do that."))
		holding.forceMove(src)

	return

/// Old attack_hand: draw the knife held in worn shoes.
/obj/item/clothing/shoes/proc/shoes_draw_knife_hand(datum/act/op/A)
	var/mob/living/M = A.actor
	if(can_hold_knife == 1 && holding && src.loc == M)
		draw_knife(M)
		return OP_OK
	return OP_DECLINE

/// Old verb "Switch Shoe Layer".
/obj/item/clothing/shoes/proc/shoes_toggle_layer_verb(datum/act/op/A)
	set_shoes_under_pants(!shoes_under_pants)

/obj/item/clothing/shoes/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if(holding)
		look.overlay("[drawn_state]_knife")

/obj/item/clothing/shoes/wash()
	. = ..()
	dq_set_blood_color(src, null)
	track_blood = 0

/obj/item/clothing/shoes/proc/handle_movement(turf/walking, running, mob/living/carbon/human/pred)
	if(COOLDOWN_FINISHED(src, recent_squish) && istype(pred))
		COOLDOWN_START(src, recent_squish, 4 SECONDS)
		for(var/mob/living/M in contents)
			if(pred.vore_prefs.step_mechanics_pref && M.vore_prefs.step_mechanics_pref)
				src.handle_inshoe_stepping(pred, M)
			else if (prob(1)) // Same old inshoe mechanics
				var/emote = DEFAULTPICK(inside_emotes, null)
				to_chat(M,emote)
	return

//In shoe steppies!
/obj/item/clothing/shoes/proc/handle_inshoe_stepping(mob/living/carbon/human/pred, mob/living/carbon/human/prey)
	if(!istype(pred)) return //Sorry, inshoe steppies only for carbon/human/ for now. Based on the regular stepping mechanics
	if(!istype(prey)) return
	if(!pred.canmove || pred?.buckled_to()) return //We can't be stepping on anyone if src?.buckled_to() or incapable of moving
	if(pred in src?.buckled_mob_list()) return
	if(pred.flying) return //If we're src.flying, can't really step.

	// I kept interactions very similar to normal steppies, and removed some attack logs unless harm intent:
	// I_HELP: No painful description, messages only sent to prey. Similar to inshoe steppies from before.
	// I_DISARM: Painful yet harmless descriptions, weaken on walk. Attack logs on weaken.
	// I_GRAB: Grabby/Squishing descriptions, weaken on walk. Attack logs on weaken.
	// I_HURT: Rand .5-1.5 multiplied by .25 min or 1.75 max, multiplied by 3.5 on walk. Ranges from .125 min to 9.1875 max damage to each limb
	var/message_pred = null
	var/message_prey = null

	// The wearer's held posture while walking (their state, not an input): the held Disarm/Grab variant, else combat mode.
	var/posture = pred.combat_mode ? I_HURT : I_HELP
	if(pred.attack_variant == ATTACK_VARIANT_DISARM)
		posture = I_DISARM
	else if(pred.attack_variant == ATTACK_VARIANT_GRAB)
		posture = I_GRAB
	switch(posture)
		if(I_HELP)
			if(prob(10)) //Reducing spam exclusively on I_HELP. Still more frequent than old pitiful prob(1)
				if(pred.m_intent == I_RUN)
					message_prey = pick(
						"You feel weightless for a brief moment as \the [name] move upwards.",
						"[pred]'s weight bears down on you with each of their steps.",
						"\The [name] are a ride you've got no choice but to participate in as the wearer moves.",
						"The wearer of \the [name] moves, and their feet press down on you with each step.",
						"With each step, you're sandwiched again between [pred]'s feet and the insole of their boots.",
						"As [pred] moves, their foot presses you tightly against the insole of their boots with each step.")
				else
					message_prey = pick(
						"You feel weightless for a brief moment as \the [name] move upwards.",
						"[pred]'s weight bears down on you with each of the calm steps of their walk.",
						"\The [name] are a ride you've got no choice but to participate in as the wearer walks.",
						"The wearer of \the [name] walks, and their feet press down on you heavily with each step.",
						"With each step of their unhurried walk, you're tightly sandwiched between [pred]'s feet and the insole of their boots.",
						"As [pred] walks, their foot presses you tightly against the insole of their boots with each step.")
				to_chat(prey, span_emote_subtle(span_italics("[message_prey]")))

			return  //No message for pred if I_HELP

		if(I_DISARM)
			if(pred.m_intent == I_RUN)
				message_pred = "You step on [prey], squishing and pinning them within your [name]!"
				message_prey = "[pred] steps on you, squishing and pinning you within their [name]!"
			else
				message_pred = "You firmly push your foot down on [prey], painfully but harmlessly pinning them to the insole of your [name]!"
				message_prey = "[pred] firmly pushes their foot down on you, painfully but harmlessly pinning you to the insole of their [name]!"
				prey.status_at_least(STAT_WEAKENED, 5) // For flavour, only noticed prey if tossed out of shoe
				add_attack_logs(pred, prey, "Pinned inshoe (walk, weaken(5))")

		if(I_GRAB)
			if(pred.m_intent == I_RUN)
				message_pred = "You step down onto [prey], squishing and trapping them inbetween your toes!"
				message_prey = "[pred] steps down on you, squishing and trapping you inbetween their toes!"
			else
				message_pred = "You pin [prey] down against the insole of your [name] with your foot, your toes curling up around their body, tightly trapping them inbetween them!"
				message_prey = "[pred] pins you down against the insole of their [name] with their foot, their toes curling up around your body, tighly trapping you inbetween them!"
				prey.status_at_least(STAT_WEAKENED, 5) // For flavour, only noticed prey if tossed out of shoe
				add_attack_logs(pred, prey, "Grabbed inshoe (walk, weaken(5))")

		if(I_HURT)
			var/size_damage_multiplier = pred.size_multiplier - prey.size_multiplier

			if(size_damage_multiplier < 0) // In case of odd situations such as wearing a shoe containing someone bigger than you.
				size_damage_multiplier = 0

			//Assuming regular micro pickup sizes outside dorms, size_damage multiplier should range from .25 to 1.75... right?
			var/damage = (rand(5, 15) * size_damage_multiplier) / 10 // This will sting, but not kill unless pred walks. Will range from .125 to 2.625 damage, randomly, to each limb

			if(pred.m_intent == I_RUN)
				message_pred = "You carelessly step down onto [prey], crushing them within your [name]!"
				message_prey = "[pred] steps carelessly on your body, crushing you within their [name]!"
				add_attack_logs(pred, prey, "Crushed inshoe (run, about [damage] damage per limb)")
			else
				message_pred = "You methodically place your foot down upon [prey]'s body, applying pressure, crushing them against the insole of your [name]!"
				message_prey = "[pred] methodically places their foot upon your body, applying pressure, crushing you against the insole of their [name]!"
				damage *= 3.5 //Walking damage multiplier
				add_attack_logs(pred, prey, "Crushed inshoe (walk, about [damage] damage per limb)")

			for(var/obj/item/organ/external/I in prey.organs)
				// Running Total: 1.50 damage min, 28.875 damage max, depending on size & RNG.
				// Walking Total: 5.25 damage min, 101.0625 damage max, depending on size & RNG. Ouch.
				prey.injure(INJURY_BLUNT, damage, I, src)

	if(message_pred != null)
		to_chat(pred, span_warning(message_pred))
	to_chat(prey, span_warning(message_prey))

	return

/// Old attack_self: shake micros out. Runs the clothing circuit first, as the old ..() did.
/obj/item/clothing/shoes/proc/shoes_shake_out_self(datum/act/op/A)
	var/mob/user = A.actor
	clothing_circuit_self(A)
	for(var/mob/M in contents_of(src))
		if(isvoice(M)) //Don't knock voices out!
			continue
		M.forceMove(get_turf(user))
		to_chat(M, span_warning("[user] shakes you out of \the [src]!"))
		to_chat(user, span_notice("You shake [M] out of \the [src]!"))

/obj/item/clothing/shoes/container_resist(mob/living/micro)
	var/mob/living/carbon/human/macro = loc
	if(isvoice(micro)) //Voices shouldn't be able to resist but we have this here just in case.
		return
	if(!istype(macro))
		to_chat(micro, span_notice("You start to climb out of [src]!"))
		perform_op(micro, src, "micro_climb_out", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)
		return

	var/escape_message_micro = "You start to climb out of [src]!"
	var/escape_message_macro = "Something is trying to climb out of your [src]!"
	var/escape_time = 60

	if(macro.get_equipped_item(SLOT_ID_SHOES) == src)
		escape_message_micro = "You start to climb around the larger creature's feet and ankles!"
		escape_time = 100

	to_chat(micro, span_notice("[escape_message_micro]"))
	to_chat(macro, span_danger("[escape_message_macro]"))
	perform_op(micro, src, "micro_escape_macro", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("macro" = macro, "time" = escape_time))

/obj/item/clothing/shoes/proc/micro_climbed_out(datum/act/op/A)
	var/mob/living/micro = A.actor
	to_chat(micro, span_notice("You climb out of [src]!"))
	micro.forceMove(loc)

/obj/item/clothing/shoes/proc/micro_escape_time(datum/act/op/A)
	return A.arg("time")

/obj/item/clothing/shoes/proc/micro_pinned(datum/act/op/A)
	var/mob/living/micro = A.actor
	var/mob/living/carbon/human/macro = A.arg("macro")
	to_chat(micro, span_danger("You're pinned underfoot!"))
	if(!QDELETED(macro))
		to_chat(macro, span_danger("You pin the escapee underfoot!"))

/obj/item/clothing/shoes/proc/micro_escaped_macro(datum/act/op/A)
	var/mob/living/micro = A.actor
	var/mob/living/carbon/human/macro = A.arg("macro")
	if(QDELETED(macro))
		return
	to_chat(micro, span_notice("You manage to escape [src]!"))
	to_chat(macro, span_danger("Someone has climbed out of your [src]!"))
	micro.forceMove(macro.loc)

/obj/item/clothing/shoes/equipped(mob/user, slot)
	. = ..()
	handle_digitigrade(user)

/// Old MouseDrop_T.
/obj/item/clothing/shoes/proc/interaction_drag(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/target = A.held
	if(!istype(user)) return OP_DECLINE // If the user passed in isn't a living mob, exit
	if(target != user) return OP_DECLINE // If the user didn't drag themselves, exit
	if(user.incapacitated() || user?.buckled_to()) return OP_DECLINE // If user is incapacitated or src?.buckled_to(), exit
	if(get_holder_of_type(src, /mob/living/carbon/human) == user) return OP_DECLINE // No jumping into your own equipment
	if(ishuman(user) && user.get_effective_size() > 0.25) return OP_DECLINE // Only micro characters

	var/full = 0
	for(var/mob/M in contents_of(src))
		if(istype(M,/mob/living/voice)) //Don't count voices as people!
			continue
		full++
	if(full >= 2)
		to_chat(user, span_warning("It doesn't seem like there is room in \the [src]!"))
	else
		to_chat(user, span_warning("You crawl into \the [src]!"))
		user.forceMove(src)

	return OP_DECLINE

/// Old attackby ("sideways" override): stuff a micro or a knife into the shoes.
/obj/item/clothing/shoes/proc/shoes_stuff_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I,/obj/item/holder/micro))
		var/full = 0
		for(var/mob/M in contents_of(src))
			if(isvoice(M)) //Don't count voices as people!
				continue
			full++
		if(full >= 2)
			to_chat(user, span_warning("You can't fit anyone else into \the [src]!"))
		else
			var/obj/item/holder/micro/holder = I
			if(holder.held_mob && (is_in_holder(holder.held_mob, holder)))
				var/mob/living/M = holder.held_mob
				holder.dump_mob()
				to_chat(M, span_warning("[user] stuffs you into \the [src]!"))
				M.forceMove(src)
				to_chat(user, span_notice("You stuff \the [M] into \the [src]!"))
		return OP_PASS
	if((can_hold_knife == 1) && (istype(I, /obj/item/material/shard) || \
		istype(I, /obj/item/material/butterfly) || \
		istype(I, /obj/item/material/kitchen/utensil) || \
		istype(I, /obj/item/material/knife/tacknife)))
		if(holding)
			to_chat(user, span_warning("\The [src] is already holding \a [holding]."))
			return OP_PASS
		if(!move_into(src, nameof(src.holding), I, user))
			return OP_PASS
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " shoves %I% into %T%."), item = I)
		return OP_PASS
	return OP_DECLINE

/obj/item/clothing/shoes/muffles_death_of(mob/occupant)
	return TRUE
