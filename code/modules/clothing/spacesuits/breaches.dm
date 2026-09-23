//A 'wound' system for space suits.
//Breaches greatly increase the amount of lost gas and decrease the armour rating of the suit.
//They can be healed with plastic or metal sheeting.

/datum/breach
	var/class = 0                           // Size. Lower is smaller. Uses floating point values!
	var/descriptor                          // 'gaping hole' etc.
	var/breach_type = BURN                      // Punctured or melted
	var/obj/item/clothing/suit/space/holder // Suit containing the list of breaches holding this instance.

/obj/item/clothing/suit/space

	var/can_breach = 1                      // Set to 0 to disregard all breaching.
	var/list/breaches                       // Breach datum container (lazylist; empty for an undamaged suit).
	var/resilience = 0.2                    // Multiplier that turns damage into breach class. 1 is 100% of damage to breach, 0.1 is 10%. 0.2 -> 50 brute/burn damage to cause 10 breach damage
	var/breach_threshold = 3                // Min damage before a breach is possible. Damage is subtracted by this amount, it determines the "hardness" of the suit.
	var/damage = 0                          // Current total damage
	var/brute_damage = 0                    // Specifically brute damage.
	var/burn_damage = 0                     // Specifically burn damage.
	var/base_name                           // Used to keep the original name safe while we apply modifiers.
	resistance_flags = FIRE_PROOF | ACID_PROOF

/obj/item/clothing/suit/space/Initialize(mapload)
	. = ..()
	base_name = "[name]"

/datum/breach/proc/update_descriptor()

	//Sanity...
	class = between(1, round(class), 5)
	//Apply the correct descriptor.
	if(breach_type == BURN)
		descriptor = GLOB.breach_burn_descriptors[class]
	else if(breach_type == BRUTE)
		descriptor = GLOB.breach_brute_descriptors[class]

//Repair a certain amount of brute or burn damage to the suit.
/obj/item/clothing/suit/space/proc/repair_breaches(breach_type, amount, mob/user)

	if(!can_breach || !LAZYLEN(breaches) || !damage)
		to_chat(user, "There are no breaches to repair on \the [src].")
		return

	var/list/valid_breaches = list()

	for(var/datum/breach/B in breaches)
		if(B.breach_type == breach_type)
			valid_breaches += B

	if(!valid_breaches.len)
		to_chat(user, "There are no breaches to repair on \the [src].")
		return

	var/amount_left = amount
	for(var/datum/breach/B in valid_breaches)
		if(!amount_left) break

		if(B.class <= amount_left)
			amount_left -= B.class
			valid_breaches -= B
			LAZYREMOVE(breaches, B)
		else
			B.class	-= amount_left
			amount_left = 0
			B.update_descriptor()

	user.visible_message(span_infoplain(span_bold("[user]") + " patches some of the damage on \the [src]."))
	calc_breach_damage()

/obj/item/clothing/suit/space/proc/create_breaches(breach_type, amount)

	amount -= src.breach_threshold
	amount *= src.resilience

	if(!can_breach || amount <= 0)
		return

	if(damage > 25) return //We don't need to keep tracking it when it's at 250% pressure loss, really.

	if(!loc) return
	var/turf/T = get_turf(src)
	if(!T) return

	//Increase existing breaches.
	for(var/datum/breach/existing in breaches)

		if(existing.breach_type != breach_type)
			continue

		//keep in mind that 10 breach damage == full pressure loss.
		//a breach can have at most 5 breach damage
		if (existing.class < 5)
			var/needs = 5 - existing.class
			if(amount < needs)
				existing.class += amount
				amount = 0
			else
				existing.class = 5
				amount -= needs

			if(existing.breach_type == BRUTE)
				T.visible_message(span_warning("\The [existing.descriptor] on [src] gapes wider!"))
			else if(existing.breach_type == BURN)
				T.visible_message(span_warning("\The [existing.descriptor] on [src] widens!"))

	if (amount)
		//Spawn a new breach.
		var/datum/breach/B = new()
		LAZYADD(breaches, B)

		B.class = min(amount,5)

		B.breach_type = breach_type
		B.update_descriptor()
		B.holder = src

		if(B.breach_type == BRUTE)
			T.visible_message(span_warning("\A [B.descriptor] opens up on [src]!"))
		else if(B.breach_type == BURN)
			T.visible_message(span_warning("\A [B.descriptor] marks the surface of [src]!"))

	calc_breach_damage()

//Calculates the current extent of the damage to the suit.
/obj/item/clothing/suit/space/proc/calc_breach_damage()

	damage = 0
	brute_damage = 0
	burn_damage = 0

	if(!can_breach || !LAZYLEN(breaches))
		name = base_name
		return 0

	for(var/datum/breach/B in breaches)
		if(!B.class)
			LAZYREMOVE(breaches, B)
			qdel(B)
		else
			damage += B.class
			if(B.breach_type == BRUTE)
				brute_damage += B.class
			else if(B.breach_type == BURN)
				burn_damage += B.class

	if(damage >= 3)
		if(brute_damage >= 3 && brute_damage > burn_damage)
			name = "punctured [base_name]"
		else if(burn_damage >= 3 && burn_damage > brute_damage)
			name = "scorched [base_name]"
		else
			name = "damaged [base_name]"
	else
		name = "[base_name]"

	return damage

//Handles repairs (and also upgrades).

/obj/item/clothing/suit/space/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W,/obj/item/stack/material))
		var/repair_power = 0
		switch(W.get_material_name())
			if(MAT_STEEL)
				repair_power = 2
			if(MAT_PLASTIC)
				repair_power = 1

		if(!repair_power)
			return

		if(isliving(src.loc))
			to_chat(user, span_warning("How do you intend to patch a hardsuit while someone is wearing it?"))
			return

		if(!damage || !burn_damage)
			to_chat(user, "There is no surface damage on \the [src] to repair.")
			return

		var/obj/item/stack/P = W
		var/use_amt = min(P.get_amount(), 3)
		if(use_amt && P.use(use_amt))
			repair_breaches(BURN, use_amt * repair_power, user)
		return

	..()

/obj/item/clothing/suit/space/welder_act(mob/user, obj/item/tool)
	if(isliving(src.loc))
		to_chat(user, span_red("How do you intend to patch a hardsuit while someone is wearing it?"))
		return ITEM_INTERACT_SUCCESS

	if (!damage || ! brute_damage)
		to_chat(user, "There is no structural damage on \the [src] to repair.")
		return ITEM_INTERACT_SUCCESS

	var/obj/item/weldingtool/WT = tool.get_welder()
	if(!WT.remove_fuel(5))
		to_chat(user, span_red("You need more welding fuel to repair this suit."))
		return ITEM_INTERACT_SUCCESS

	repair_breaches(BRUTE, 3, user)
	return ITEM_INTERACT_SUCCESS

/obj/item/clothing/suit/space/examine(mob/user)
	. = ..()
	if(can_breach && LAZYLEN(breaches))
		for(var/datum/breach/B in breaches)
			. += span_red(span_bold("It has \a [B.descriptor]."))
