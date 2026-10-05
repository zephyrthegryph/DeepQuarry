/obj/item/stamp
	name = "rubber stamp"
	desc = "A rubber stamp for stamping important documents."
	icon = 'icons/obj/bureaucracy_yw.dmi'
	icon_state = "stamp-qm"
	item_state = "stamp"
	throwforce = 0
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_HOLSTER
	throw_speed = 7
	throw_range = 15
	MATERIAL_BULK(MAT_STEEL, 60)
	pressure_resistance = 2
	attack_verb = list("stamped")
	drop_sound = SFX_ITEMS_DROP_DEVICE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	var/stamptext = null

/obj/item/stamp/captain
	name = "site manager's rubber stamp"
	icon_state = "stamp-cap"

/obj/item/stamp/hop
	name = "head of personnel's rubber stamp"
	icon_state = "stamp-hop"

/obj/item/stamp/hos
	name = "head of security's rubber stamp"
	icon_state = "stamp-hos"

/obj/item/stamp/ward
	name = "warden's rubber stamp"
	icon_state = "stamp-ward"

/obj/item/stamp/ce
	name = "chief engineer's rubber stamp"
	icon_state = "stamp-ce"

/obj/item/stamp/rd
	name = "research director's rubber stamp"
	icon_state = "stamp-rd"

/obj/item/stamp/cmo
	name = "chief medical officer's rubber stamp"
	icon_state = "stamp-cmo"

/obj/item/stamp/talon
	name = "talon's rubber stamp"
	icon_state = "stamp-tal"

/obj/item/stamp/denied
	name = "\improper DENIED rubber stamp"
	icon_state = "stamp-deny"
	attack_verb = list("DENIED")

/obj/item/stamp/accepted
	name = "\improper ACCEPTED rubber stamp"
	icon_state = "stamp-ok"

/obj/item/stamp/clown
	name = "clown's rubber stamp"
	icon_state = "stamp-clown"

/obj/item/stamp/internalaffairs
	name = "internal affairs rubber stamp"
	icon_state = "stamp-intaff"

/obj/item/stamp/centcomm
	name = "\improper CentCom rubber stamp"
	icon_state = "stamp-cent"

/obj/item/stamp/qm
	name = "quartermaster's rubber stamp"
	icon_state = "stamp-qm"

/obj/item/stamp/cargo
	name = "cargo rubber stamp"
	icon_state = "stamp-cargo"

/obj/item/stamp/solgov
	name = "\improper Sol Government rubber stamp"
	icon_state = "stamp-sg"

/obj/item/stamp/solgov
	name = "\improper Sol Government rubber stamp"
	icon_state = "stamp-sg"

/obj/item/stamp/solgovlogo
	name = "\improper Sol Government logo stamp"
	icon_state = "stamp-sol"

/obj/item/stamp/solgovlogo
	name = "\improper Sol Government logo stamp"
	icon_state = "stamp-sol"

/obj/item/stamp/einstein
	name = "\improper Einstein Engines rubber stamp"
	icon_state = "stamp-einstein"

/obj/item/stamp/hephaestus
	name = "\improper Hephaestus Industries rubber stamp"
	icon_state = "stamp-heph"

/obj/item/stamp/zeng_hu
	name = "\improper Zeng-Hu Pharmaceuticals rubber stamp"
	icon_state = "stamp-zenghu"

// Syndicate stamp to forge documents.
CAPABILITIES(/obj/item/stamp/chameleon)
	op("disguise", in_hand(), label("Disguise"),
		asks(/datum/prompt/choice, fields = list("question" = "Choose a stamp to disguise as:", "title" = "Stamp Choice", "choices" = computed(PROC_REF(stamp_choice_names)), "timeout" = 0), step = "k124"),
		then(PROC_REF(interaction_self)))

/// Stamp metadata is immutable; enumerating choices must not construct temporary items.
/obj/item/stamp/chameleon/proc/stamp_choice_types()
	var/list/stamps = list()
	for(var/stamp_type in typesof(/obj/item/stamp) - src.type)
		var/obj/item/stamp/S = stamp_type
		stamps[capitalize(initial(S.name))] = stamp_type
	return stamps

/// Old attack_self.
/// The names the disguise question lists (EXIT first: picking it changes nothing).
/obj/item/stamp/chameleon/proc/stamp_choice_names(datum/act/op/A)
	. = list("EXIT")
	for(var/name in sortList(stamp_choice_types()))
		. += name

/obj/item/stamp/chameleon/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/list/stamps = stamp_choice_types()
	var/input_stamp = A.step_value("k124")

	if(user && (src?.loc == user)) // Er, how necessary is this in attack_self?

		var/obj/item/stamp/chosen_stamp = stamps[capitalize(input_stamp)]

		if(chosen_stamp)
			name = initial(chosen_stamp.name)
			icon_state = initial(chosen_stamp.icon_state)

	return TRUE
