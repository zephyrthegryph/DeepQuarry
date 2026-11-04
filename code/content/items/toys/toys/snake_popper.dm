/*
 * Snake popper
 */
/obj/item/toy/snake_popper
	name = "bread tube"
	desc = "Bread in a tube. Chewy...and surprisingly tasty."
	icon = 'icons/obj/toy.dmi'
	icon_state = "tastybread"
	var/popped = 0
	var/real = 0

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/toy/snake_popper/proc/roll_real(datum/roller/R)
	return R.chance(0.1) ? 1 : real

CAPABILITIES(/obj/item/toy/snake_popper)
	configure(atom_rules(description_fluff = "This is the product that brought Centauri Provisions into the limelight. A product of the earliest extrasolar colony of Heaven, the Bread Tube, while bland, contains all the nutrients a spacer needs to get through the day and is decidedly edible when compared to some of its competitors. Due to the high-fructose corn syrup content of NanoTrasen's own-brand bread tubes, many jurisdictions classify them as a confectionary."))
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	rolls(nameof(real), PROC_REF(roll_real))

/// Old attack_self.
/obj/item/toy/snake_popper/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!popped)
		to_chat(user, span_warning("A snake popped out of [src]!"))
		if(real == 0)
			var/obj/item/toy/C = new /obj/item/toy/plushie/snakeplushie(get_turf(loc))
			C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

		if(real == 1)
			var/mob/living/simple_mob/C = new /mob/living/simple_mob/animal/passive/snake(get_turf(loc))
			C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

		if(real == 2)
			var/mob/living/simple_mob/C = new /mob/living/simple_mob/vore/aggressive/giant_snake(get_turf(loc))
			C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

		play_sfx(src, SFX_ITEMS_CONFETTI)
		set_icon_state("tastybread_popped")
		popped = 1
		user.status_at_least(STAT_STUNNED, 1)

		var/datum/effect/effect/system/confetti_spread/s = new /datum/effect/effect/system/confetti_spread
		s.set_up(5, 1, src)
		s.start()
	return TRUE

/// Old attackby.
/obj/item/toy/snake_popper/proc/interaction_item(datum/act/op/A)
	var/obj/O = A.held
	if(istype(O, /obj/item/toy/plushie/snakeplushie) || !real)
		if(popped && !real)
			consumed(O, src)
			popped = 0
			set_icon_state("tastybread")
	return OP_PASS

/obj/item/toy/snake_popper/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(ishuman(M))
		if(!popped)
			to_chat(user, span_warning("A snake popped out of [src]!"))
			if(real == 0)
				var/obj/item/toy/C = new /obj/item/toy/plushie/snakeplushie(get_turf(loc))
				C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

			if(real == 1)
				var/mob/living/simple_mob/C = new /mob/living/simple_mob/animal/passive/snake(get_turf(loc))
				C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

			if(real == 2)
				var/mob/living/simple_mob/C = new /mob/living/simple_mob/vore/aggressive/giant_snake(get_turf(loc))
				C.throw_at(get_step(src, pick(GLOB.alldirs)), 9, 1, src)

			play_sfx(src, SFX_ITEMS_CONFETTI)
			set_icon_state("tastybread_popped")
			popped = 1
			user.status_at_least(STAT_STUNNED, 1)

			var/datum/effect/effect/system/confetti_spread/s = new /datum/effect/effect/system/confetti_spread
			s.set_up(5, 1, src)
			s.start()
			return ITEM_INTERACT_SUCCESS
		return ITEM_INTERACT_FAILURE
	return NONE

/obj/item/toy/snake_popper/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(real != 2)
		set_real(2)
		to_chat(user, span_notice("You short out the bluespace refill system of [src]."))
	return OP_OK
