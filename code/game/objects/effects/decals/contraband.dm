/obj/item/contraband/package
	name = "contraband"
	desc = "A tightly sealed package. Dare to look inside?"
	icon = 'icons/obj/storage.dmi'
	icon_state = "deliverycrate5"
	item_state = "table_parts"
	w_class = ITEMSIZE_HUGE

/obj/item/contraband/package/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	var/contraband = pick(
		/obj/item/reagent_containers/glass/beaker/vial/macrocillin,
		/obj/item/reagent_containers/glass/beaker/vial/microcillin,
		/obj/item/gun/energy/sizegun,
		/obj/item/clothing/mask/muzzle,
		/obj/item/pda/clown,
		/obj/item/pda/mime,
		/obj/item/storage/fancy/cigar/havana,
		/obj/item/card/emag_broken,
		/obj/item/sleevemate,
		/obj/item/disk/nifsoft/compliance,
		/obj/item/seeds/ambrosiadeusseed,
		/obj/item/seeds/ambrosiavulgarisseed,
		/obj/item/bodysnatcher)

	user.put_in_hands(new contraband(user.loc))
	to_chat(user, span_notice("You unwrap the package."))
	qdel(src)
