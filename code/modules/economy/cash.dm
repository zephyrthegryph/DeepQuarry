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
	return look_overlay_image('icons/obj/economy.dmi', "spacecash[denomination]", transform = layouts[((note_seed + index) % SPACECASH_NOTE_LAYOUTS) + 1])

/// Old attackby.
/obj/item/spacecash/proc/cash_combine(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/spacecash))
		if(istype(W, /obj/item/spacecash/ewallet)) return OP_PASS

		var/obj/item/spacecash/SC = W

		SC.adjust_worth(src.worth)
		if(ishuman(user))
			var/mob/living/carbon/human/h_user = user

			h_user.drop_from_inventory(src)
			h_user.drop_from_inventory(SC)
			h_user.put_in_hands(SC)
		to_chat(user, span_notice("You combine the [initial_name]s to a bundle of [SC.worth] [initial_name]s."))
		consume(src, user)
	return OP_PASS

TRACKED(/obj/item/spacecash, worth)
TRACKED(/obj/item/spacecash, note_seed)

/obj/item/spacecash/draw(datum/look/look)
	..()
	look_parts(look)

/// The pile's name, state or scattered notes (a charge card draws none of it).
/obj/item/spacecash/proc/look_parts(datum/look/look)
	look.identity(name = "[worth] [initial_name]\s")
	if(worth in list(1000,500,200,100,50,20,10,5,1))
		look.state("spacecash[worth]")
		look.identity(desc = "It's worth [worth] [initial_name]s.")
		return
	var/sum = worth
	var/num = 0
	for(var/i in list(1000,500,200,100,50,20,10,5,1))
		while(sum >= i && num < 50)
			sum -= i
			num++
			look.overlay(banknote_image(i, num))
	if(num == 0) // Less than one thaler, let's just make it look like 1 for ease
		look.overlay(banknote_image(1, 0))
	look.identity(desc = "They are worth [worth] [initial_name]s.")

/obj/item/spacecash/proc/adjust_worth(adjust_worth = 0)
	set_worth(worth + adjust_worth)
	if(worth > 0)
		return worth
	else
		spent(src)
		return 0

CAPABILITIES(/obj/item/spacecash)
	rolls(nameof(note_seed), range_of(0, 49))
	op("cash_take", in_hand(), label("Use"),
		asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(cash_take_question)), "title" = "Take Money", "default" = 20, "max_value" = nameof(worth), "timeout" = 0), step = "k92"),
		then(PROC_REF(cash_take)))
	op("cash_combine", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(cash_combine)))

/obj/item/spacecash/proc/cash_take_question(datum/act/op/A)
	return "How many [initial_name]s do you want to take? (0 to [src.worth])"

/// Old attack_self.
/obj/item/spacecash/proc/cash_take(datum/act/op/A)
	var/mob/user = A.actor
	var/amount = A.step_value("k92")
	if(!src || QDELETED(src))
		return OP_OK
	amount = round(CLAMP(amount, 0, src.worth))

	if(!amount)
		return OP_OK

	adjust_worth(-amount)
	var/obj/item/spacecash/SC = new (user.loc)
	SC.set_worth(amount)
	user.put_in_hands(SC)
	return OP_OK

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

CAPABILITIES(/obj/item/spacecash/ewallet)
	op("pass_item", item(/obj/item), label("Interaction pass"), passes())

/// A charge card keeps its mapped look and name.
/obj/item/spacecash/ewallet/look_parts(datum/look/look)
	return

/obj/item/spacecash/ewallet/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += span_notice("Charge card's owner: [src.owner_name]. Thalers remaining: [src.worth].")

#undef SPACECASH_NOTE_LAYOUTS
