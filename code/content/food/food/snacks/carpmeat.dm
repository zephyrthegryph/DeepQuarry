/obj/item/reagent_containers/food/snacks/carpmeat
	name = "fillet"
	desc = "A fillet of carp meat"
	icon_state = "fishfillet"
	filling_color = "#FFDEFE"
	bitesize = 6

	var/toxin_type = REAGENT_ID_CARPOTOXIN
	var/toxin_amount = 3

CAPABILITIES(/obj/item/reagent_containers/food/snacks/carpmeat)
	configure(atom_rules(price_tag = 5))
	configure(item_handling(center_x = 17, center_y = 13))
	configure(reagents(contents_from = PROC_REF(toxin_contents)))
	configure(reagents(add = list(REAGENT_ID_SEAFOOD = 3)))

/// Its toxin, when the type names one.
/obj/item/reagent_containers/food/snacks/carpmeat/proc/toxin_contents()
	return (toxin_type && toxin_amount) ? list("[toxin_type]" = toxin_amount) : null

/obj/item/reagent_containers/food/snacks/carpmeat/fish
	desc = "A fillet of fish meat."

/obj/item/reagent_containers/food/snacks/carpmeat/fish/sif
	desc = "A fillet of sivian fish meat."
	filling_color = "#2c2cff"
	color = "#2c2cff"

/obj/item/reagent_containers/food/snacks/carpmeat/ray
	desc = "A fillet of space ray meat."
	toxin_type = REAGENT_ID_STOXIN

/obj/item/reagent_containers/food/snacks/carpmeat/gnat
	desc = "A paltry sample of space-gnat meat. It looks pretty stringy and unpleasant, honestly."
	toxin_amount = 1

/obj/item/reagent_containers/food/snacks/carpmeat/shark
	desc = "A fillet of space shark meat. It looks rather tough and chewy."
	toxin_amount = 5

/obj/item/reagent_containers/food/snacks/carpmeat/fish/sharkmeat
	name = "slice of sharkmeat"
	desc = "Now it's small enough to cook with."
	icon = 'icons/obj/food.dmi'
	icon_state = "sharkmeat"
	nutriment_amt = 2
	toxin_amount = null
	bitesize = 3

CAPABILITIES(/obj/item/reagent_containers/food/snacks/carpmeat/fish/sharkmeat)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 2)))

/obj/item/reagent_containers/food/snacks/carpmeat/sif //Making fish meat non-toxic!  As advised by Ascian!
	toxin_type = null
	toxin_amount = null

/obj/item/reagent_containers/food/snacks/carpmeat/sif/murkfish
	toxin_type = null

/obj/item/reagent_containers/food/snacks/carpmeat/fish
	toxin_type = null
	toxin_amount = null
