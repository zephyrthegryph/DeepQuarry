// -----------------------------
//       Quickdraw storage
// -----------------------------
//These items are pouches and cases made to be kept in belts or pockets to quickly draw objects from
//Largely inspired by the vest pouches on Colonial Marines

/obj/item/storage/quickdraw
	name = "quickdraw"
	desc = "This object should not appear"
	icon = 'icons/obj/storage_vr.dmi'

	//Quickmode, as the case starts out (the mode itself is the quickdraw() capability's state QUICKDRAW_DRAWS)
	//When set to 0, this storage will operate as a regular storage, and clicking on it while equipped will open it as a storage
	//When set to 1, a click while it is equipped will instead move the first item inside it to your hand
	var/quickmode = 0

CAPABILITIES(/obj/item/storage/quickdraw, \
	quickdraw(starts = nameof(/obj/item/storage/quickdraw::quickmode)))

// If we start adding more of these, we'll need to make them their own folder. 'til then, this one should be fine.

// -----------------------------
//       Syringe case
// -----------------------------

/obj/item/storage/quickdraw/syringe_case
	name = "syringe case"
	desc = "A small case for safely carrying sharps around."
	icon_state = "syringe_case"

	w_class = ITEMSIZE_SMALL
	max_storage_space = ITEMSIZE_TINY * 6 //Capable of holding six syringes

	//Can hold syringes and autoinjectors, but also pills if you really wanted. Syringe-shaped objects like pens and cigarettes also fit, but why would you do that?

	quickmode = 1 //Starts in quickdraw mode
	//Preloaded for your convenience!
	starts_with = list(
		/obj/item/reagent_containers/syringe,
		/obj/item/reagent_containers/syringe,
		/obj/item/reagent_containers/syringe,
		/obj/item/reagent_containers/syringe,
		/obj/item/reagent_containers/syringe,
		/obj/item/reagent_containers/syringe
	)


CAPABILITIES(/obj/item/storage/quickdraw/syringe_case, \
	configure(storage(accepts = list( \
		/obj/item/reagent_containers/syringe, \
		/obj/item/reagent_containers/hypospray/autoinjector, \
		/obj/item/reagent_containers/pill, \
		/obj/item/pen, \
		/obj/item/flashlight/pen, \
		/obj/item/clothing/mask/smokable/cigarette), max_size = ITEMSIZE_TINY)))

/obj/item/storage/quickdraw/syringe_case/clotting
	desc = "A small case for safely carrying sharps around. This one is deluxe!"
	starts_with = list(
		/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting,
		/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting,
		/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting
	)


CAPABILITIES(/obj/item/storage/quickdraw/syringe_case/clotting, \
	configure(storage(accepts = list( \
		/obj/item/reagent_containers/syringe, \
		/obj/item/reagent_containers/hypospray/autoinjector, \
		/obj/item/reagent_containers/pill, \
		/obj/item/pen, \
		/obj/item/flashlight/pen, \
		/obj/item/clothing/mask/smokable/cigarette), max_size = ITEMSIZE_SMALL)))

/obj/item/storage/quickdraw/syringe_case/bonemed
	desc = "A small case for safely carrying sharps around. This one is deluxe!"
	starts_with = list(
		/obj/item/reagent_containers/hypospray/autoinjector/bonemed,
		/obj/item/reagent_containers/hypospray/autoinjector/bonemed,
		/obj/item/reagent_containers/hypospray/autoinjector/bonemed
	)


CAPABILITIES(/obj/item/storage/quickdraw/syringe_case/bonemed, \
	configure(storage(accepts = list( \
		/obj/item/reagent_containers/syringe, \
		/obj/item/reagent_containers/hypospray/autoinjector, \
		/obj/item/reagent_containers/pill, \
		/obj/item/pen, \
		/obj/item/flashlight/pen, \
		/obj/item/clothing/mask/smokable/cigarette), max_size = ITEMSIZE_SMALL)))

/obj/item/storage/quickdraw/syringe_case/clonemed
	desc = "A small case for safely carrying sharps around. This one is deluxe!"
	starts_with = list(
		/obj/item/reagent_containers/hypospray/autoinjector/clonemed,
		/obj/item/reagent_containers/hypospray/autoinjector/clonemed,
		/obj/item/reagent_containers/hypospray/autoinjector/clonemed
	)


CAPABILITIES(/obj/item/storage/quickdraw/syringe_case/clonemed, \
	configure(storage(accepts = list( \
		/obj/item/reagent_containers/syringe, \
		/obj/item/reagent_containers/hypospray/autoinjector, \
		/obj/item/reagent_containers/pill, \
		/obj/item/pen, \
		/obj/item/flashlight/pen, \
		/obj/item/clothing/mask/smokable/cigarette), max_size = ITEMSIZE_SMALL)))
