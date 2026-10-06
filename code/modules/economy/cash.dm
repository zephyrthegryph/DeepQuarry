/// How many scattered banknote layouts piles share (spacecash_note_layouts()).
#define SPACECASH_NOTE_LAYOUTS 50

/obj/item/spacecash
	name = "0 Thaler"
	var/initial_name = "Thaler"
	desc = "It's worth 0 Thalers."
	gender = PLURAL
	icon = 'icons/obj/economy.dmi'
	icon_state = "spacecash1"
	opacity = 0
	density = FALSE
	anchored = FALSE
	force = 1.0
	throwforce = 1.0
	throw_speed = 1
	throw_range = 2
	w_class = ITEMSIZE_SMALL
	var/access = ACCESS_CRATE_CASH
	var/worth = 0
	drop_sound = SFX_ITEMS_DROP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER
	///Var for attack_self chain
	var/special_handling = FALSE

/obj/item/spacecash/Initialize(mapload)
	. = ..()
	make_sellable(/datum/sellable/spacecash)
	note_seed = rand(0, SPACECASH_NOTE_LAYOUTS - 1)

/obj/item/spacecash
	/// Picked once at init: where this pile starts in the shared note layouts, so a redraw keeps
	/// every banknote where it was.
	var/note_seed = 0

/// The scattered note transforms, rolled once for the whole round and shared by every pile.
GLOBAL_LIST_INIT(spacecash_note_layouts, build_spacecash_note_layouts())

/proc/build_spacecash_note_layouts()
	. = list()
	for(var/i in 1 to SPACECASH_NOTE_LAYOUTS)
		var/matrix/M = matrix()
		M.Translate(rand(-6, 6), rand(-4, 8))
		M.Turn(pick(-45, -27.5, 0, 0, 0, 0, 0, 0, 0, 27.5, 45))
		. += M

/// The banknote image for the `index`th note of this pile.
/obj/item/spacecash/proc/banknote_image(denomination, index)
	var/list/layouts = GLOB.spacecash_note_layouts
	var/image/banknote = image('icons/obj/economy.dmi', "spacecash[denomination]")
	banknote.transform = layouts[((note_seed + index) % SPACECASH_NOTE_LAYOUTS) + 1]
	return banknote

/// Old attackby.
/obj/item/spacecash/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/spacecash))
		if(istype(W, /obj/item/spacecash/ewallet)) return INTERACTION_HANDLED_PASS

		var/obj/item/spacecash/SC = W

		SC.adjust_worth(src.worth)
		if(ishuman(user))
			var/mob/living/carbon/human/h_user = user

			h_user.drop_from_inventory(src)
			h_user.drop_from_inventory(SC)
			h_user.put_in_hands(SC)
		to_chat(user, span_notice("You combine the [initial_name]s to a bundle of [SC.worth] [initial_name]s."))
		consume(src, user)
	return INTERACTION_HANDLED_PASS

DECLARE_APPEARANCE_PROC(/obj/item/spacecash, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/spacecash/appearance_overlays()
	. = list()
	name = "[worth] [initial_name]\s"
	if(worth in list(1000,500,200,100,50,20,10,5,1))
		icon_state = "spacecash[worth]"
		desc = "It's worth [worth] [initial_name]s."
		return .
	var/sum = src.worth
	var/num = 0
	for(var/i in list(1000,500,200,100,50,20,10,5,1))
		while(sum >= i && num < 50)
			sum -= i
			num++
			. += banknote_image(i, num)
	if(num == 0) // Less than one thaler, let's just make it look like 1 for ease
		. += banknote_image(1, 0)
	src.desc = "They are worth [worth] [initial_name]s."

/obj/item/spacecash/proc/adjust_worth(adjust_worth = 0, update = 1)
	worth += adjust_worth
	if(worth > 0)
		if(update)
			update_icon()
		return worth
	else
		spent(src)
		return 0

/obj/item/spacecash/proc/set_worth(new_worth = 0, update = 1)
	worth = max(0, new_worth)
	if(update)
		update_icon()
	return worth

DECLARE_INTERACTIONS(/obj/item/spacecash, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/spacecash/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/amount = rerun_ask(user, "k92", PROC_REF(interaction_self), args, /datum/prompt/number, question = "How many [initial_name]s do you want to take? (0 to [src.worth])", title = "Take Money", default = 20, max_value = src.worth)
	if(isnull(amount))
		return TRUE
	if(!src || QDELETED(src))
		return TRUE
	amount = round(CLAMP(amount, 0, src.worth))

	if(!amount)
		return TRUE

	adjust_worth(-amount)
	var/obj/item/spacecash/SC = new (user.loc)
	SC.set_worth(amount)
	user.put_in_hands(SC)
	return TRUE

/obj/item/spacecash/c1
	name = "1 Thaler"
	icon_state = "spacecash1"
	desc = "It's worth 1 Thaler."
	worth = 1

/obj/item/spacecash/c5
	name = "5 Thaler"
	icon_state = "spacecash5"
	desc = "It's worth 5 Thalers."
	worth = 5

/obj/item/spacecash/c10
	name = "10 Thaler"
	icon_state = "spacecash10"
	desc = "It's worth 10 Thalers."
	worth = 10

/obj/item/spacecash/c20
	name = "20 Thaler"
	icon_state = "spacecash20"
	desc = "It's worth 20 Thalers."
	worth = 20

/obj/item/spacecash/c50
	name = "50 Thaler"
	icon_state = "spacecash50"
	desc = "It's worth 50 Thalers."
	worth = 50

/obj/item/spacecash/c100
	name = "100 Thaler"
	icon_state = "spacecash100"
	desc = "It's worth 100 Thalers."
	worth = 100

/obj/item/spacecash/c200
	name = "200 Thaler"
	icon_state = "spacecash200"
	desc = "It's worth 200 Thalers."
	worth = 200

/obj/item/spacecash/c500
	name = "500 Thaler"
	icon_state = "spacecash500"
	desc = "It's worth 500 Thalers."
	worth = 500

/obj/item/spacecash/c1000
	name = "1000 Thaler"
	icon_state = "spacecash1000"
	desc = "It's worth 1000 Thalers."
	worth = 1000

/proc/spawn_money(sum, spawnloc, mob/living/carbon/human/human_user as mob)
	var/obj/item/spacecash/SC = new (spawnloc)

	SC.set_worth(sum)
	if (ishuman(human_user) && !human_user.get_active_hand())
		human_user.put_in_hands(SC)
	return

/obj/item/spacecash/ewallet
	name = "charge card"
	initial_name = "charge card"
	icon_state = "efundcard"
	desc = "A card that holds an amount of money."
	drop_sound = SFX_ITEMS_DROP_CARD
	pickup_sound = SFX_ITEMS_PICKUP_CARD
	var/owner_name = "" //So the ATM can set it so the EFTPOS can put a valid name on transactions.
	special_handling = TRUE

EXTEND_INTERACTIONS(/obj/item/spacecash/ewallet, INTERACT_ITEM(null, TYPE_PROC_REF(/atom, interaction_pass)))

APPEARANCE_NONE(/obj/item/spacecash/ewallet)

/obj/item/spacecash/ewallet/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += span_notice("Charge card's owner: [src.owner_name]. Thalers remaining: [src.worth].")

#undef SPACECASH_NOTE_LAYOUTS
