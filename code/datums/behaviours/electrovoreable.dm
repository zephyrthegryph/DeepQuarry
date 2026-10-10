/// Electrovore interaction for power cells (was /datum/element/electrovoreable, added to
/// every cell). A self-use interaction declared on /obj/item/cell (power/cell.dm); FALSE
/// moves on to the next self-use, so non-electrovores fall through.
/obj/item/cell/proc/electrovore_charge(datum/act/op/A)
	return (electrovore_attack_self(A.actor, I_HELP) & COMPONENT_CANCEL_ATTACK_CHAIN) ? OP_OK : OP_DECLINE

/obj/item/cell/proc/electrovore_drain(datum/act/op/A)
	return (electrovore_attack_self(A.actor, I_HURT) & COMPONENT_CANCEL_ATTACK_CHAIN) ? OP_OK : OP_DECLINE

/// Electrovores charge (help, obligate) or drain (harm) the cell by hand.
/obj/item/cell/proc/electrovore_attack_self(mob/user, stance)
	var/obj/item/source = src

	if(!isliving(user))
		return
	var/mob/living/living_user = user

	// Must be some kind of electrovore to interact at all
	if(!has_trait(living_user, TRAIT_ELECTROVORE))
		return

	// Only cells should have special electrovore behavior
	if(!istype(source, /obj/item/cell))
		return
	var/obj/item/cell/source_cell = source

	// HELP: obligate electrovores only (charge the cell)
	if(stance == I_HELP && has_trait(living_user, TRAIT_ELECTROVORE_OBLIGATE))
		if(source_cell.charge >= source_cell.maxcharge)
			return COMPONENT_CANCEL_ATTACK_CHAIN

		if(!living_user.nutrition)
			living_user.show_message(span_warning("You feel too drained to charge [source_cell]."))
			return COMPONENT_CANCEL_ATTACK_CHAIN

		var/todrain = max(100, (living_user.nutrition * 0.2))
		if(living_user.nutrition < todrain)
			living_user.show_message(span_warning("You don't have enough energy to charge [source_cell]."))
			return COMPONENT_CANCEL_ATTACK_CHAIN

		living_user.show_message(span_warning("Power surges from you and flows into [source_cell], increasing its charge!"))
		act_message(living_user, null, others = span_notice("%U% squeezes [source_cell] tightly, charging it!"))

		var/totransfer = min(todrain, ((source_cell.maxcharge - source_cell.charge) / 15))

		living_user.adjust_nutrition(-todrain)
		source_cell.give(min((totransfer * 15), (source_cell.maxcharge - source_cell.charge)))

		return COMPONENT_CANCEL_ATTACK_CHAIN

	// HURT: drain energy for nutrition (obligate + freeform)
	if(stance == I_HURT)
		if(!source_cell.charge)
			living_user.show_message(span_warning("You take a look at [source_cell] and notice it has nothing in it!"))
			return COMPONENT_CANCEL_ATTACK_CHAIN

		living_user.show_message(span_warning("Sparks fly from [source_cell] as you drain energy from it!"))
		act_message(living_user, null, others = span_danger("%U% causes sparks to emit from [source_cell] as it loses its charge!"))

		var/coefficient = 0.9
		var/totransfer = min(source_cell.charge, 1500)

		living_user.adjust_nutrition((totransfer / 15) * coefficient)
		source_cell.use(totransfer)

		fx_sparks(source_cell, 3, FALSE)

		return COMPONENT_CANCEL_ATTACK_CHAIN
