//Items for the entrepreneurs

/obj/item/entrepreneur
	name = "crystal ball"
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "crystal_ball"
	desc = "A perfect sphere that is partially translucent, allowing one to see into it's mysterious depths."

/obj/item/entrepreneur/crystal_ball

////// Exercise mat, yoga and trainer stuff

/obj/item/bedsheet/pillow/exercise
	name = "exercise mat"
	desc = "A thick, flexible but tough mat designed for people to exercise on."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "exercise_mat"

CAPABILITIES(/obj/item/bedsheet/pillow/exercise)
	op("use_item", item(/obj/item), passes(), then(PROC_REF(exercise_item_passes)))

/// An item used on an exercise mat does nothing to it: the click goes on (the old interaction_pass).
/obj/item/bedsheet/pillow/exercise/proc/exercise_item_passes(datum/act/op/A)
	return OP_PASS

// Spirit Healer stuff

/obj/item/entrepreneur/crystal
	name = "healing crystal"
	desc = "A crystal with a powerful energy, apparantly, and is capable of healing the soul, apparantly."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "crystal_pink"
	w_class = ITEMSIZE_TINY

CAPABILITIES(/obj/item/entrepreneur/crystal)
	rolls(nameof(icon_state), PROC_REF(roll_look))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/entrepreneur/crystal/proc/roll_look(datum/roller/R)
	return R.choose(list("crystal_pink","crystal_blue","crystal_green","crystal_orange","crystal_dblue","crystal_purple"))

/obj/item/reagent_containers/glass/bottle/essential_oil
	name = "essential oils"
	desc = "A small bottle of various plant extracts said to improve upon a person's health as an alternative form of medicine."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "oil"
	prefill = list(REAGENT_ID_ESSENTIALOIL = 60)

// Masseuse

/obj/item/roller/massage
	name = "massage bed"
	desc = "A collapsed roller massage bed that can be carried around. When deployed, it can be locked in place (with alt-click)."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "folded_rollerbed"
	rollertype = /obj/item/roller/massage
	bedtype = /obj/structure/bed/roller/massage

//Magnifying glass

/obj/item/entrepreneur/magnifying_glass
	name = "magnifying glass"
	desc = "A curved lense for looking at things a little closer."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "magnifying_glass"
	w_class = ITEMSIZE_SMALL

/obj/item/entrepreneur/magnifying_glass/afterattack(atom/T, mob/living/user as mob)
	if(!T.desc)
		return
	act_message(user, T, others = span_notice("%U% examines %T% with \the [src]!"))
	to_chat(user, span_huge("[T.desc]"))

// Streamer and influencer

/obj/item/tvcamera/streamer
	name = "streamer camera drone"
	channel = "Virgo Live Stream"

/obj/item/camera/selfie
	name = "selfie stick"
	desc = "A long stick with a camera on the end, designed for taking pictures of one's self, but could awkwardly be turned to take pictures of other things too!"
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "selfie"
	item_state = "selfie"
	icon_on = "selfie"
	icon_off = "selfie_off"

// Containers

/obj/item/storage/box/fortune_teller
	name = "fortune teller kit"
	desc = "A kit containing everything that a fortune teller needs."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "fortune_teller"
	starts_with = list(/obj/item/entrepreneur/horoscope, /obj/item/deck/tarot, /obj/item/entrepreneur/crystal_ball, /obj/item/ticket_printer/train)

/obj/item/storage/box/dentist
	name = "dentist kit"
	desc = "A kit containing everything that a dentist needs."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "dentist"
	starts_with = list(/obj/item/entrepreneur/dentist_mirror, /obj/item/entrepreneur/dentist_probe, /obj/item/entrepreneur/dentist_sickle, /obj/item/entrepreneur/dentist_scaler, /obj/item/flashlight/pen, /obj/item/ticket_printer/train)

/obj/item/storage/box/fitness_trainer
	name = "exercise kit"
	desc = "A kit containing everything that a fitness trainer needs."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "fitness_trainer"
	starts_with = list(/obj/item/bedsheet/pillow/exercise, /obj/item/entrepreneur/dumbbell, /obj/item/entrepreneur/dumbbell, /obj/item/reagent_containers/food/snacks/candy/proteinbar, /obj/item/ticket_printer/train)

/obj/item/storage/box/yoga_teacher
	name = "yoga kit"
	desc = "A kit containing everything that a yoga teacher needs."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "yoga_teacher"
	starts_with = list(/obj/item/bedsheet/pillow/exercise, /obj/item/bedsheet/pillow/exercise, /obj/item/reagent_containers/food/snacks/fruitbar, /obj/item/ticket_printer/train)

/obj/item/storage/box/paranormal_investigator
	name = "ghost hunting kit"
	desc = "A kit containing everything that a paranormal investigator needs."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "paranormal_investigator"
	starts_with = list(/obj/item/entrepreneur/emf, /obj/item/entrepreneur/spirit_board, /obj/item/reagent_containers/food/drinks/glass2/shot, /obj/item/ticket_printer/train)

/obj/item/storage/box/spirit_healer
	name = "exercise kit"
	desc = "A kit containing everything that a spirit healer needs."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "spirit_healer"
	starts_with = list(/obj/item/entrepreneur/crystal, /obj/item/entrepreneur/crystal, /obj/item/entrepreneur/crystal, /obj/item/entrepreneur/crystal, /obj/item/entrepreneur/crystal, /obj/item/reagent_containers/glass/bottle/essential_oil, /obj/item/ticket_printer/train)

/obj/item/storage/box/private_investigator
	name = "investigator kit"
	desc = "A kit containing everything that a private eye needs."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "private_investigator"
	starts_with = list(/obj/item/taperecorder, /obj/item/tape, /obj/item/tape, /obj/item/camera, /obj/item/sticky_pad, /obj/item/entrepreneur/magnifying_glass, /obj/item/ticket_printer/train)

/obj/item/storage/box/stylist
	name = "stylist kit"
	desc = "A kit containing everything that a stylist needs."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "stylist"
	starts_with = list(/obj/item/makeover, /obj/item/lipstick/random, /obj/item/nailpolish,  /obj/item/nailpolish_remover, /obj/item/haircomb, /obj/item/clothing/head/hairnet, /obj/item/ticket_printer/train)
