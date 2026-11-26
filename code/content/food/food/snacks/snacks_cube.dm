// food cubes
/obj/item/reagent_containers/food/snacks/cube
	name = "protein cube"
	desc = "A colony of meat cells, Just add water!"
	icon = 'icons/obj/food.dmi'
	icon_state = "proteincube"
	w_class = ITEMSIZE_TINY
	flags = OPENCONTAINER
	bitesize = 12
	filling_color = "#ADAC7F"

	var/food_type = /obj/item/reagent_containers/food/snacks/proteinslab

CAPABILITIES(/obj/item/reagent_containers/food/snacks/cube)
	configure(item_handling(center_x = 16, center_y = 14))

/obj/item/reagent_containers/food/snacks/cube/proc/Expand()
	src.visible_message(span_infoplain(span_bold("\The [src]") + " expands!"))
	replace_with(src, food_type)

/obj/item/reagent_containers/food/snacks/cube/on_reagent_change()
	if(reagents.has_reagent(REAGENT_ID_WATER))
		Expand()

/obj/item/reagent_containers/food/snacks/cube/protein

CAPABILITIES(/obj/item/reagent_containers/food/snacks/cube/protein)
	configure(reagents(add = list(REAGENT_ID_MEATCOLONY = 5)))

/obj/item/reagent_containers/food/snacks/cube/nutriment
	name = "Nutriment cube"
	desc = "A colony of plant cells, Just add water!"
	icon_state = "nutrimentcube"
	food_type = /obj/item/reagent_containers/food/snacks/nutrimentslab

CAPABILITIES(/obj/item/reagent_containers/food/snacks/cube/nutriment)
	configure(reagents(add = list(REAGENT_ID_PLANTCOLONY = 5)))
