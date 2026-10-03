
/*
 * Patches. A subtype of pills, in order to inherit the possible future produceability within chem-masters, and dissolving.
 */

/obj/item/reagent_containers/pill/patch
	name = "patch"
	desc = "A patch."
	icon = 'icons/obj/chemical.dmi'
	icon_state = null
	item_state = "pill"

	base_state = "patch"

	max_transfer_amount = null
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	volume = 60

	var/pierce_material = FALSE	// If true, the patch can be used through thick material.

// A patch is a pill that goes on the skin: on the limb aimed at, at once on yourself and in three seconds on somebody else. A missing or robotic limb refuses
// it, and so does thick material (unless it pierces).
CAPABILITIES(/obj/item/reagent_containers/pill/patch, \
	configure(dose(route = CHEM_TOUCH, pierces = nameof(pierce_material))))
