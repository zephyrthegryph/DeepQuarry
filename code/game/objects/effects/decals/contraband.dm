/obj/item/contraband/package
	name = "contraband"
	desc = "A tightly sealed package. Dare to look inside?"
	icon = 'icons/obj/storage.dmi'
	icon_state = "deliverycrate5"
	item_state = "table_parts"
	w_class = ITEMSIZE_HUGE

// The package's own unwrap replaces the parent's: the old override ran both and handed out two items.
CAPABILITIES(/obj/item/contraband/package)
	without("unwrap")
	op("unwrap_package", in_hand(), label("Unwrap"), then(PROC_REF(interaction_unwrap_package)))

/// Old attack_self.
/obj/item/contraband/package/proc/interaction_unwrap_package(datum/act/op/A)
	var/mob/user = A.actor
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

	// Used up first, as the parent's unwrap: what was inside goes into the hand that held it.
	if(!consume(src, user))
		return OP_REFUSED
	user.put_in_hands(new contraband(user.loc))
	to_chat(user, span_notice("You unwrap the package."))
