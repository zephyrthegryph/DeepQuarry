
//Original Casino Code created by Shadowfire117#1269 - Ported from CHOMPstation
//Modified by GhostActual#2055 for use with VOREstation

/obj/machinery/chipmachine
	name = "Casino Chip Exchange"
	desc = "Converts thalers to casino chips at a ratio of 5 thalers to 1 chip! It can also convert chips back to thalers at the same rate."
	icon = 'icons/obj/casino_ch.dmi'
	icon_state ="casino_atm"
	anchored = 1

// Cap the worth used in the *5 / /5 conversion so the result stays within BYOND's
// exact-integer float range (2**24 - 1) and can't lose precision or overflow.
#define CHIPMACHINE_MAX_WORTH 16777215

CAPABILITIES(/obj/machinery/chipmachine)
	op("exchange", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Exchange"), then(PROC_REF(interaction_exchange)))

/obj/machinery/chipmachine/proc/interaction_exchange(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/spacecash))
		var/obj/item/spacecash/cash = I
		var/worth = clamp(cash.worth, 0, CHIPMACHINE_MAX_WORTH)
		if(worth >= 5)
			//consume the money
			if(prob(50))
				play_sfx(loc, SFX_ITEMS_POLAROID1)
			else
				play_sfx(loc, SFX_ITEMS_POLAROID2)

			to_chat(user, span_info("You insert [I] into [src]."))
			spawn_casinochips(round(worth / 5), src.loc)
			src.attack_hand(user)
			consume(I, user)

	if(istype(I, /obj/item/spacecasinocash))
		var/obj/item/spacecasinocash/chips = I
		//consume the chips
		if(prob(50))
			play_sfx(loc, SFX_ITEMS_POLAROID1)
		else
			play_sfx(loc, SFX_ITEMS_POLAROID2)

		to_chat(user, span_info("You insert [I] into [src]."))
		// Bound the input worth so worth*5 stays exactly representable.
		var/worth = clamp(chips.worth, 0, round(CHIPMACHINE_MAX_WORTH / 5))
		spawn_money(round(worth * 5), src.loc)
		src.attack_hand(user)
		consume(I, user)
	return TRUE

/obj/item/spacecasinocash
	name = "broken casino chip"
	desc = "It's worth nothing in a casino."
	gender = PLURAL
	icon = 'icons/obj/casino.dmi'
	icon_state = "spacecasinocash1"
	opacity = 0
	density = 0
	anchored = 0.0
	force = 1.0
	throwforce = 1.0
	throw_speed = 1
	throw_range = 2
	w_class = ITEMSIZE_SMALL
	var/access = ACCESS_CRATE_CASH
	var/worth = 0

/// Old attackby.
/obj/item/spacecasinocash/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/spacecasinocash))

		var/obj/item/spacecasinocash/SC = W

		SC.adjust_worth(src.worth)
		if(ishuman(user))
			var/mob/living/carbon/human/h_user = user

			h_user.drop_from_inventory(src)
			h_user.drop_from_inventory(SC)
			h_user.put_in_hands(SC)
		to_chat(user, span_notice("You combine the casino chips to a stack of [SC.worth] casino credits."))
		consume(src, user)
	return INTERACTION_HANDLED_PASS

DECLARE_APPEARANCE_PROC(/obj/item/spacecasinocash, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/spacecasinocash/appearance_overlays()
	. = list()
	name = "[worth] casino credit\s"
	if(worth in list(1000,500,200,100,50,20,10,1))
		icon_state = "spacecasinocash[worth]"
		desc = "It's a stack of casino chips with a combined value of [worth] casino credits."
		return .
	var/sum = src.worth
	var/num = 0
	for(var/i in list(1000,500,200,100,50,20,10,1))
		while(sum >= i && num < 50)
			sum -= i
			num++
			var/image/banknote = image('icons/obj/casino.dmi', "spacecasinocash[i]")
			var/matrix/M = matrix()
			M.Translate(rand(-6, 6), rand(-4, 8))
			M.Turn(pick(-45, 0, 0, 0, 0, 0, 0, 0, 45))
			banknote.transform = M
			. += banknote
	if(num == 0) // Less than one credit, let's just make it look like 1 for ease
		var/image/banknote = image('icons/obj/casino.dmi', "spacecasinocash1")
		var/matrix/M = matrix()
		M.Translate(rand(-6, 6), rand(-4, 8))
		M.Turn(pick(-45, 0, 0, 0, 0, 0, 0, 0, 45))
		banknote.transform = M
		. += banknote
	src.desc = "They are worth [worth] casino credits."

/obj/item/spacecasinocash/proc/adjust_worth(adjust_worth = 0, update = 1)
	worth += adjust_worth
	if(worth > 0)
		if(update)
			update_icon()
			changed(src)
		return worth
	else
		spent(src)
		return 0

/obj/item/spacecasinocash/proc/set_worth(new_worth = 0, update = 1)
	worth = max(0, new_worth)
	if(update)
		update_icon()
		changed(src)
	return worth

DECLARE_INTERACTIONS(/obj/item/spacecasinocash, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/spacecasinocash/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/amount = rerun_ask(user, "k142", PROC_REF(interaction_self), args, /datum/om/prompt/number, message = "How much credits worth of chips do you want to take? (0 to [src.worth])", title = "Take chips", default = 20, max = src.worth)
	if(isnull(amount))
		return TRUE
	if(!src || QDELETED(src))
		return TRUE
	amount = round(CLAMP(amount, 0, src.worth))

	if(!amount)
		return TRUE

	adjust_worth(-amount)
	var/obj/item/spacecasinocash/SC = new (user.loc)
	SC.set_worth(amount)
	user.put_in_hands(SC)
	return TRUE

/obj/item/spacecasinocash/c1
	name = "1 credit casino chip"
	icon_state = "spacecasinocash1"
	desc = "It's worth 1 credit."
	worth = 1

/obj/item/spacecasinocash/c10
	name = "10 credit casino chip"
	icon_state = "spacecasinocash10"
	desc = "It's worth 10 credits."
	worth = 10

/obj/item/spacecasinocash/c20
	name = "20 credit casino chip"
	icon_state = "spacecasinocash20"
	desc = "It's worth 20 credits."
	worth = 20

/obj/item/spacecasinocash/c50
	name = "50 credit casino chip"
	icon_state = "spacecasinocash50"
	desc = "It's worth 50 credits."
	worth = 50

/obj/item/spacecasinocash/c100
	name = "100 credit casino chip"
	icon_state = "spacecasinocash100"
	desc = "It's worth 100 credits."
	worth = 100

/obj/item/spacecasinocash/c200
	name = "200 credit casino chip"
	icon_state = "spacecasinocash200"
	desc = "It's worth 200 credits."
	worth = 200

/obj/item/spacecasinocash/c500
	name = "500 credit casino chip"
	icon_state = "spacecasinocash500"
	desc = "It's worth 500 credits."
	worth = 500

/obj/item/spacecasinocash/c1000
	name = "1000 credit casino chip"
	icon_state = "spacecasinocash1000"
	desc = "It's worth 1000 credits."
	worth = 1000

/proc/spawn_casinochips(sum, spawnloc, mob/living/carbon/human/human_user as mob)
	var/obj/item/spacecasinocash/SC = new (spawnloc)

	SC.set_worth(sum, TRUE)
	if (ishuman(human_user) && !human_user.get_active_hand())
		human_user.put_in_hands(SC)
	return

/obj/item/casino_platinum_chip
	name = "platinum chip"
	desc = "Ringa-a-Ding-Ding!"
	icon = 'icons/obj/casino.dmi'
	icon_state = "platinum_chip"
	var/sides = 2
	opacity = 0
	density = 0
	anchored = 0.0
	force = 1.0
	throwforce = 1.0
	throw_speed = 1
	throw_range = 2
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/casino_platinum_chip)
	op("flip", in_hand(), label("Flip chip"), then(PROC_REF(platinum_chip_flip_requested)))

/obj/item/casino_platinum_chip/proc/platinum_chip_flip_requested(datum/act/op/A)
	var/mob/user = A.actor
	var/result = rand(1, sides)
	var/comment = ""
	if(result == 1)
		comment = "Ace"
	else if(result == 2)
		comment = "Joker"
	act_message(user, src, MSG_SELF(span_notice("You throw %T%. It lands on [comment]! ")), \
		MSG_OTHERS(span_notice("%U% has thrown %T%. It lands on [comment]! ")))
	return OP_OK


//Fake casino chips that can be ordered at any time

/obj/item/spacecasinocash_fake
	name = "broken replica casino chip"
	desc = "It's worth nothing in a casino."
	gender = PLURAL
	icon = 'icons/obj/casino.dmi'
	icon_state = "spacecasinocash1"
	opacity = 0
	density = 0
	anchored = 0.0
	force = 1.0
	throwforce = 1.0
	throw_speed = 1
	throw_range = 2
	w_class = ITEMSIZE_SMALL
	var/access = ACCESS_CRATE_CASH
	var/worth = 0

/// Old attackby.
/obj/item/spacecasinocash_fake/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/spacecasinocash_fake))

		var/obj/item/spacecasinocash_fake/SC = W

		SC.adjust_worth(src.worth)
		if(ishuman(user))
			var/mob/living/carbon/human/h_user = user

			h_user.drop_from_inventory(src)
			h_user.drop_from_inventory(SC)
			h_user.put_in_hands(SC)
		to_chat(user, span_notice("You combine the casino chips to a stack of [SC.worth] replica casino credits."))
		consume(src, user)
	return INTERACTION_HANDLED_PASS

DECLARE_APPEARANCE_PROC(/obj/item/spacecasinocash_fake, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/spacecasinocash_fake/appearance_overlays()
	. = list()
	name = "[worth] replica casino chip\s"
	if(worth in list(1000,500,200,100,50,20,10,1))
		icon_state = "spacecasinocash[worth]"
		desc = "It's a stack of replica casino chips with a combined value of [worth] imaginary points."
		return .
	var/sum = src.worth
	var/num = 0
	for(var/i in list(1000,500,200,100,50,20,10,1))
		while(sum >= i && num < 50)
			sum -= i
			num++
			var/image/banknote = image('icons/obj/casino.dmi', "spacecasinocash[i]")
			var/matrix/M = matrix()
			M.Translate(rand(-6, 6), rand(-4, 8))
			banknote.transform = M
			. += banknote
	if(num == 0) // Less than one credit, let's just make it look like 1 for ease
		var/image/banknote = image('icons/obj/casino.dmi', "spacecasinocash1")
		var/matrix/M = matrix()
		M.Translate(rand(-6, 6), rand(-4, 8))
		banknote.transform = M
		. += banknote
	src.desc = "They are worth [worth] replica casino credits."

/obj/item/spacecasinocash_fake/proc/adjust_worth(adjust_worth = 0, update = 1)
	worth += adjust_worth
	if(worth > 0)
		if(update)
			update_icon()
			changed(src)
		return worth
	else
		spent(src)
		return 0

/obj/item/spacecasinocash_fake/proc/set_worth(new_worth = 0, update = 1)
	worth = max(0, new_worth)
	if(update)
		update_icon()
		changed(src)
	return worth

DECLARE_INTERACTIONS(/obj/item/spacecasinocash_fake, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/spacecasinocash_fake/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/amount = rerun_ask(user, "k323", PROC_REF(interaction_self), args, /datum/om/prompt/number, message = "How much credits worth of chips do you want to take? (0 to [src.worth])", title = "Take chips", default = 20, max = src.worth)
	if(isnull(amount))
		return TRUE
	if(!src || QDELETED(src))
		return TRUE
	amount = round(CLAMP(amount, 0, src.worth))

	if(!amount)
		return TRUE

	adjust_worth(-amount)
	var/obj/item/spacecasinocash_fake/SC = new (user.loc)
	SC.set_worth(amount)
	user.put_in_hands(SC)
	return TRUE

/obj/item/spacecasinocash_fake/c1
	name = "1 replica casino chip"
	icon_state = "spacecasinocash1"
	desc = "It's worth 1 credit."
	worth = 1

/obj/item/spacecasinocash_fake/c10
	name = "10 replica casino chip"
	icon_state = "spacecasinocash10"
	desc = "It's worth 10 credits."
	worth = 10

/obj/item/spacecasinocash_fake/c20
	name = "20 replica casino chip"
	icon_state = "spacecasinocash20"
	desc = "It's worth 20 credits."
	worth = 20

/obj/item/spacecasinocash_fake/c50
	name = "50 replica casino chip"
	icon_state = "spacecasinocash50"
	desc = "It's worth 50 credits."
	worth = 50

/obj/item/spacecasinocash_fake/c100
	name = "100 replica casino chip"
	icon_state = "spacecasinocash100"
	desc = "It's worth 100 credits."
	worth = 100

/obj/item/spacecasinocash_fake/c200
	name = "200 replica casino chip"
	icon_state = "spacecasinocash200"
	desc = "It's worth 200 credits."
	worth = 200

/obj/item/spacecasinocash_fake/c500
	name = "500 replica casino chip"
	icon_state = "spacecasinocash500"
	desc = "It's worth 500 credits."
	worth = 500

/obj/item/spacecasinocash_fake/c1000
	name = "1000 replica casino chip"
	icon_state = "spacecasinocash1000"
	desc = "It's worth 1000 credits."
	worth = 1000

#undef CHIPMACHINE_MAX_WORTH
