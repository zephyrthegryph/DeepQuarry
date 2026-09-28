/obj/item/contraband/package
	name = "contraband"
	desc = "A tightly sealed package. Dare to look inside?"
	icon = 'icons/obj/storage.dmi'
	icon_state = "deliverycrate5"
	item_state = "table_parts"
	w_class = ITEMSIZE_HUGE

// The package's own unwrap replaces the parent's: the old override ran both and handed out two items.
// ALLOW(interactions): its Unwrap replaces the parent's (both ran and handed out two items)
DECLARE_INTERACTIONS(/obj/item/contraband/package, INTERACT_USE("Unwrap", PROC_REF(interaction_unwrap_package)))

/// Old attack_self.
/obj/item/contraband/package/proc/interaction_unwrap_package(mob/user, obj/item/held, datum/interaction/interaction)
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
	consume(src, user)
