/obj/item/clothing/mask/chewable
	name = "chewable item master"
	desc = "If you are seeing this, ahelp it."
	icon = 'icons/inventory/face/item.dmi'
	drop_sound = SFX_ITEMS_DROP_FOOD
	body_parts_covered = 0

	var/type_butt = null
	var/chem_volume = 0
	var/chewtime = 0
	var/brand
	var/wrapped = FALSE

TRACKED(/obj/item/clothing/mask/chewable, wrapped)


/// TRUE while worn in the mask slot by a mob with a mouth.
/obj/item/clothing/mask/chewable/var/chewing = FALSE
TRACKED(/obj/item/clothing/mask/chewable, chewing)
CAPABILITIES(/obj/item/clothing/mask/chewable)
	reagents(nameof(chem_volume))
	every(1 SECOND, then(PROC_REF(chewable_step)), when = nameof(chewing))
	op("unwrap", in_hand(), label("Unwrap"), then(PROC_REF(unwrapped)))

/// Using it in the hand unwraps it; the clothing's own self-use still follows, as the old ..() did.
/obj/item/clothing/mask/chewable/proc/unwrapped(datum/act/op/A)
	var/mob/user = A.actor
	if(wrapped)
		set_wrapped(FALSE)
		to_chat(user, span_notice("You unwrap \the [name]."))
		play_sfx(src.loc, SFX_ITEMS_DROP_WRAPPER)
		slot_flags = SLOT_EARS | SLOT_MASK
	return OP_DECLINE

/obj/item/clothing/mask/chewable/draw(datum/look/look)
	..()
	if(wrapped)
		look.overlay("[initial(icon_state)]_wrapper")

/obj/item/clothing/mask/chewable/Initialize(mapload)
	. = ..()
	flags |= NOREACT // so it doesn't react until you light it
	if(wrapped)
		slot_flags = null

/obj/item/clothing/mask/chewable/equipped(mob/living/user, slot)
	..()
	if(slot == SLOT_ID_MASK)
		var/mob/living/carbon/human/C = user
		if(C.check_has_mouth())
			set_chewing(TRUE)
		else
			to_chat(user, span_notice("You don't have a mouth, and can't make much use of \the [src]."))

/obj/item/clothing/mask/chewable/dropped(mob/user, equipping, slot)
	set_chewing(FALSE)
	..()

/obj/item/clothing/mask/chewable/proc/chew()
	chewtime--
	if(reagents && reagents.total_volume)
		if(ishuman(loc))
			var/mob/living/carbon/human/C = loc
			if (src == C.get_equipped_item(SLOT_ID_MASK) && C.check_has_mouth())
				reagents.trans_to_mob(C, REM, CHEM_INGEST, 0.2)
		else
			set_chewing(FALSE)

/obj/item/clothing/mask/chewable/proc/chewable_step(datum/act/timer/A)
	chew()
	if(chewtime < 1)
		spitout()

/obj/item/clothing/mask/chewable/tobacco
	name = "wad"
	desc = "A chewy wad of tobacco. Cut in long strands and treated with syrup so it doesn't taste like an ash-tray when you stuff it into your face."
	throw_speed = 0.5
	icon_state = "chew"
	type_butt = /obj/item/trash/spitwad
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS | SLOT_MASK
	chem_volume = 50
	chewtime = 300
	brand = "tobacco"

/obj/item/clothing/mask/chewable/proc/spitout(transfer_color = 1, no_message = 0)
	if(type_butt)
		var/obj/item/butt = new type_butt(src.loc)
		transfer_fingerprints_to(butt)
		if(transfer_color)
			butt.color = color
		if(brand)
			butt.desc += " This one is \a [brand]."
		if(ismob(loc))
			var/mob/living/M = loc
			if(!no_message)
				to_chat(M, span_notice("The [name] runs out of flavor."))
			if(M.get_equipped_item(SLOT_ID_MASK))
				M.remove_from_mob(src) //un-equip it so the overlays can update
				M.update_inv_wear_mask(0)
				if(!M.equip_to_slot_if_possible(butt, SLOT_ID_MASK))
					M.update_inv_l_hand(0)
					M.update_inv_r_hand(1)
					M.put_in_hands(butt)
	consume(src)

/obj/item/clothing/mask/chewable/tobacco/cheap
	name = "chewing tobacco"
	desc = "A chewy wad of tobacco. Cut in long strands and treated with syrup so it tastes less like an ash-tray when you stuff it into your face."

CAPABILITIES(/obj/item/clothing/mask/chewable/tobacco/cheap)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 2)))

/obj/item/clothing/mask/chewable/tobacco/fine
	name = "deluxe chewing tobacco"
	desc = "A chewy wad of fine tobacco. Cut in long strands and treated with syrup so it doesn't taste like an ash-tray when you stuff it into your face."

CAPABILITIES(/obj/item/clothing/mask/chewable/tobacco/fine)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 3)))

/obj/item/clothing/mask/chewable/tobacco/nico
	name = "nicotine gum"
	desc = "A chewy wad of synthetic rubber, laced with nicotine. Possibly the least disgusting method of nicotine delivery."
	icon_state = "nic_gum"
	type_butt = /obj/item/trash/spitgum
	wrapped = TRUE

CAPABILITIES(/obj/item/clothing/mask/chewable/tobacco/nico)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 2), tint = TRUE))

/obj/item/storage/chewables
	name = "box of chewing wads master"
	desc = "A generic brand of Waffle Co Wads, unflavored chews. Why do these exist?"
	icon = 'icons/obj/cigarettes.dmi'
	icon_state = "cigpacket"
	item_state = "cigpacket"
	drop_sound = SFX_ITEMS_DROP_SHOVEL
	use_sound = SFX_ITEMS_STORAGE_PILLBOTTLE
	w_class = ITEMSIZE_SMALL
	throwforce = 2
	slot_flags = SLOT_BELT
	starts_with = list(/obj/item/clothing/mask/chewable/tobacco = 6)

/obj/item/storage/chewables/Initialize(mapload)
	. = ..()
	make_exact_fit()

//Tobacco Tins

/obj/item/storage/chewables/tobacco
	name = "tin of Al Mamun Smooth chewing tobacco"
	desc = "Packaged and shipped straight from Kishar, popularised by the biosphere farmers of Kanondaga."
	icon_state = "chew_generic"
	item_state = "cigpacket"
	starts_with = list(/obj/item/clothing/mask/chewable/tobacco/cheap = 6)
	storage_slots = 6

/obj/item/storage/chewables/tobacco/fine
	name = "tin of Suamalie chewing tobacco"
	desc = "Once reserved for the first-class tourists of Oasis, this premium blend has been released for the public to enjoy."
	icon_state = "chew_fine"
	item_state = "Dpacket"
	starts_with = list(/obj/item/clothing/mask/chewable/tobacco/fine = 6)

/obj/item/storage/box/fancy/chewables/tobacco/nico
	name = "box of Nico-Tine gum"
	desc = "A government doctor approved brand of nicotine gum. Cut out the middleman for your addiction fix."
	icon = 'icons/obj/cigarettes.dmi'
	icon_state = "chew_nico"
	item_state = "Epacket"
	starts_with = list(/obj/item/clothing/mask/chewable/tobacco/nico = 6)
	storage_slots = 6
	drop_sound = SFX_ITEMS_DROP_BOX
	use_sound = SFX_ITEMS_STORAGE_BOX
	var/open = 0
	var/open_state
	var/closed_state

/obj/item/storage/box/fancy/chewables/tobacco/nico/Initialize(mapload)
	if(!open_state)
		open_state = "[initial(icon_state)]0"
	if(!closed_state)
		closed_state = "[initial(icon_state)]"
	. = ..()

TRACKED(/obj/item/storage/box/fancy/chewables/tobacco/nico, open)

/obj/item/storage/box/fancy/chewables/tobacco/nico/draw(datum/look/look)
	. = ..()
	if(open)
		look.state(held_count() == 0 ? "[initial(icon_state)]_empty" : open_state)
		if(held_count() >= 1)
			look.overlay("chew_nico[held_count()]")
	else
		look.state(held_count() == 0 ? "[initial(icon_state)]_empty" : closed_state)

/obj/item/storage/box/fancy/chewables/tobacco/nico/open(mob/user as mob)
	if(open)
		return
	set_open(TRUE)
	..()

/obj/item/storage/box/fancy/chewables/tobacco/nico/close(mob/user as mob)
	set_open(FALSE)
	..()

/obj/item/clothing/mask/chewable/candy
	name = "wad"
	desc = "A chewy wad of wadding material."
	throw_speed = 0.5
	icon_state = "chew"
	type_butt = /obj/item/trash/spitgum
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS | SLOT_MASK
	chem_volume = 50
	chewtime = 300

CAPABILITIES(/obj/item/clothing/mask/chewable/candy)
	configure(reagents(add = list(REAGENT_ID_SUGAR = 2)))

/obj/item/clothing/mask/chewable/candy/gum
	name = "chewing gum"
	desc = "A chewy wad of fine synthetic rubber and artificial flavoring. Be sure to unwrap it, genius."
	icon_state = "gum"
	item_state = "gum"
	wrapped = TRUE

/obj/item/clothing/mask/chewable/candy/gum/Initialize(mapload)
	. = ..()
	reagents.add_reagent(pick(REAGENT_ID_BANANA,REAGENT_ID_BERRYJUICE,REAGENT_ID_GRAPEJUICE,REAGENT_ID_LEMONJUICE,REAGENT_ID_LIMEJUICE,REAGENT_ID_ORANGEJUICE,REAGENT_ID_WATERMELONJUICE),10) // ALLOW(decl): Initialize rolls a random flavour per instance; a declaration has no random form
	color = reagents.get_color()

/obj/item/storage/box/gum
	name = "\improper Frooty-Choos flavored gum"
	desc = "A small pack of chewing gum in various flavors."
	description_fluff = "Frooty-Choos is NanoTrasen's top-selling brand of artificially flavoured fruit-adjacent non-swallowable chew-product. This extremely specific definition places sales figures safely away from competing 'gum' brands."
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "gum_pack"
	item_state = "candy"
	slot_flags = SLOT_EARS
	w_class = ITEMSIZE_TINY
	starts_with = list(/obj/item/clothing/mask/chewable/candy/gum = 5)
	use_sound = SFX_ITEMS_DROP_PAPER
	drop_sound = SFX_ITEMS_DROP_WRAPPER
	max_storage_space = 5
	foldable = null
	trash = /obj/item/trash/gumpack


CAPABILITIES(/obj/item/storage/box/gum)
	configure(storage(accepts = list(
		/obj/item/clothing/mask/chewable/candy/gum,
		/obj/item/trash/spitgum)))

/obj/item/clothing/mask/chewable/candy/lolli
	name = "lollipop"
	desc = "A simple artificially flavored sphere of sugar on a handle, colloquially known as a sucker. Allegedly one is born every minute. Make sure to unwrap it, genius."
	type_butt = /obj/item/trash/lollibutt
	icon_state = "lollipop"
	item_state = "lollipop"
	wrapped = TRUE
	var/list/victims = null

/obj/item/clothing/mask/chewable/candy/lolli/chewable_step(datum/act/timer/A)
	chew()
	if(chewtime < 1)
		spitout(0)

/obj/item/clothing/mask/chewable/candy/lolli/container_resist(mob/living/M)
	if(istype(M, /mob/living/voice)) return
	if(victims)
		own_take_member(src, nameof(victims), M)
	to_chat(M, span_warning("You manage to pull yourself free of \the [src]."))
	M.forceMove(get_turf(src))

/obj/item/clothing/mask/chewable/candy/lolli/chew()
	if(victims && victims.len && prob(2))
		for(var/mob/living/F in victims)
			var/message = pick(
				"The tongue swishes you around and presses you against the candy!",
				"You get tossed about in the mouth, between candy and tongue!",
				"The sweet drool of your captor permeates you...",
				"The candy sticks to you, not allowing you to leave the mouth at all!",
				"You get squeezed under the candy, against the tongue!")
			to_chat(F, span_notice(message))
	return ..()

/obj/item/clothing/mask/chewable/candy/lolli/spitout()
	if(victims && victims.len)
		var/mob/living/M = loc
		if(!isliving(M))
			return ..()
		if(M.can_be_drop_pred && M.food_vore && M.vore_selected)
			for(var/mob/living/F in victims)
				if(!F.can_be_drop_prey || !F.food_vore)
					to_chat(F, span_warning("You manage to pull yourself free of \the [src] at the last second!"))
					to_chat(M, span_notice("[F] barely escapes from your mouth!"))
					F.forceMove(get_turf(src))
				else if(!move_into(M.vore_selected, BELLY_SLOT_INTERIOR, F, M))
					F.forceMove(get_turf(src))
				own_take_member(src, nameof(victims), F)
	return ..()

CAPABILITIES(/obj/item/clothing/mask/chewable/candy/lolli)
	op("stick_on", item(/obj/item/holder), passes(), then(PROC_REF(stuck_on)))

/// A small living thing in a holder can be stuck to the lollipop (unwrapped); the click goes on.
/obj/item/clothing/mask/chewable/candy/lolli/proc/stuck_on(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/holder))
		if(!(istype(W, /obj/item/holder/micro) || istype(W, /obj/item/holder/mouse)))
			return OP_DECLINE

		if(wrapped)
			to_chat(user, span_warning("You cannot stick [W] to \the [src] without unwrapping it!"))
			return OP_OK

		var/obj/item/holder/H = W

		if(!victims)
			rel_set(src, nameof(victims), list())

		var/mob/living/M = H.held_mob

		move_into(src, nameof(src.victims), M, user) // out of the holder
		rel_clear(H, nameof(H.held_mob))
		consume(H, user)

		to_chat(user, span_notice("You stick [M] to \the [src]."))
		to_chat(M, span_warning("[user] sticks you to \the [src]!"))
		return OP_OK
	return OP_OK

/obj/item/clothing/mask/chewable/candy/lolli/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		if(victims && victims.len)
			. += span_notice("It has [english_list(victims)] stuck on it.")

/obj/item/clothing/mask/chewable/candy/lolli/Initialize(mapload)
	. = ..()
	reagents.add_reagent(pick(REAGENT_ID_BANANA,REAGENT_ID_BERRYJUICE,REAGENT_ID_GRAPEJUICE,REAGENT_ID_LEMONJUICE,REAGENT_ID_LIMEJUICE,REAGENT_ID_ORANGEJUICE,REAGENT_ID_WATERMELONJUICE),20) // ALLOW(decl): Initialize rolls a random flavour per instance; a declaration has no random form
	color = reagents.get_color()

/obj/item/storage/box/pocky
	name = "\improper Totemo yoi Pocky"
	desc = "A bundle of chocolate-coated bisquit sticks."
	icon = 'icons/obj/food_snacks.dmi'
	icon_state = "pockys"
	item_state = "pocky"
	w_class = ITEMSIZE_TINY
	starts_with = list(/obj/item/clothing/mask/chewable/candy/pocky = 8)
	use_sound = SFX_ITEMS_DROP_PAPER
	drop_sound = SFX_ITEMS_DROP_WRAPPER
	max_storage_space = 8
	foldable = null
	trash = /obj/item/trash/pocky


CAPABILITIES(/obj/item/storage/box/pocky)
	configure(storage(accepts = list(/obj/item/clothing/mask/chewable/candy/pocky)))

/obj/item/clothing/mask/chewable/candy/pocky
	name = "chocolate pocky"
	desc = "A chocolate-coated biscuit stick."
	icon_state = "pockystick"
	item_state = "pocky"
	type_butt = null

CAPABILITIES(/obj/item/clothing/mask/chewable/candy/pocky)
	configure(reagents(add = list(REAGENT_ID_CHOCOLATE = 5)))

/obj/item/clothing/mask/chewable/candy/pocky/chewable_step(datum/act/timer/A)
	chew()
	if(chewtime < 1)
		if(ismob(loc))
			to_chat(loc, span_notice("There's no more of \the [name] left!"))
		spitout(0)

/obj/item/clothing/mask/chewable/candy/lolli/ownership()
	. = ..()
	. += owns(nameof(victims), policy = OWN_SPILL, is_list = TRUE)
