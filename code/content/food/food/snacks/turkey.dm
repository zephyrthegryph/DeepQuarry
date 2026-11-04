/* OLD RECIPE
/obj/item/reagent_containers/food/snacks/sliceable/turkey
	name = "turkey"
	desc = "Tastes like chicken."
	icon = 'icons/obj/food.dmi'
	icon_state = "turkey"
	slice_path = /obj/item/reagent_containers/food/snacks/turkeyslice
	slices_num = 6
	w_class = ITEMSIZE_SMALL
	nutriment_amt = 20
	nutriment_desc = list("turkey" = 20)
	bitesize = 5
	trash = /obj/item/trash/tray

DECLARE_REAGENTS(/obj/item/reagent_containers/food/snacks/sliceable/turkey, null, list(REAGENT_ID_BLACKPEPPER = 1, REAGENT_ID_SODIUMCHLORIDE = 1, REAGENT_ID_COOKINGOIL = 1))

/obj/item/reagent_containers/food/snacks/turkeyslice
	name = "turkey drumstick"
	desc = "Forsooth!"
	icon = 'icons/obj/food.dmi'
	icon_state = "turkey_drumstick"
	trash = /obj/item/trash/plate
	bitesize = 2
*/

/obj/item/reagent_containers/food/snacks/sliceable/turkey
	name = "turkey"
	desc = "Tastes like chicken."
	icon = 'icons/obj/food.dmi'
	icon_state = "roastturkey"
	slice_path = /obj/item/reagent_containers/food/snacks/turkeyslice
	slices_num = 6
	w_class = ITEMSIZE_SMALL
	nutriment_amt = 20
	nutriment_desc = list("turkey" = 20)
	bitesize = 5
	trash = /obj/item/trash/turkeybones
	var/static/list/extra_product = list(/obj/item/reagent_containers/food/snacks/turkeydrumstick = 2,
									/obj/item/trash/turkeybones = 1)

CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/turkey)
	configure(reagents(add = list(REAGENT_ID_BLACKPEPPER = 1, REAGENT_ID_SODIUMCHLORIDE = 1, REAGENT_ID_COOKINGOIL = 1)))

/obj/item/reagent_containers/food/snacks/sliceable/turkey/on_slice_extra()
	for(var/i in extra_product)
		for(var/j=1 to extra_product[i])
			new i(src.loc)
