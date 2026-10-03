//NEVER USE THIS IT SUX	-PETETHEGOAT
//THE GOAT WAS RIGHT - RKF

/obj/item/reagent_containers/glass/paint
	desc = "It's a paint bucket."
	name = "paint bucket"
	icon = 'icons/obj/items.dmi'
	icon_state = "paint_neutral"
	item_state = "paintcan"
	MATERIAL_BULK(MAT_STEEL, 200)
	w_class = ITEMSIZE_NORMAL
	amount_per_transfer_from_this = 10
	max_transfer_amount = 60
	volume = 60
	unacidable = FALSE
	flags = NONE
	var/paint_type = "red"

// A paint can paints a floor, 5 units at a time while it has more than that (in any stance: it is not splashed over it); everything else is the glass
// container's.
CAPABILITIES(/obj/item/reagent_containers/glass/paint, \
	glass_container(), \
	op("paint", at_target(/turf/simulated), answers(INTENT_ATTACK, INTENT_USE), priority(OP_PRIORITY_ATTACK), priority(above("reagent_container.splash")), when(req_reagents(5, more = TRUE)), \
		label("Paint"), then(PROC_REF(painted))))

/obj/item/reagent_containers/glass/paint/proc/painted(datum/act/op/A)
	act_message(A.actor, A.target, others = span_warning("%T% has been splashed with something by %U%!"))
	reagents.trans_to_turf(A.target, 5)
	return OP_OK

/obj/item/reagent_containers/glass/paint/Initialize(mapload)
	.=..()
	if(paint_type)
		reagents.add_reagent(REAGENT_ID_PAINT, volume, paint_type) // ALLOW(decl): the reagent's data argument (the paint type) differs per instance, which a declaration cannot carry

/obj/item/reagent_containers/glass/paint/red
	icon_state = "paint_red"
	paint_type = "#FF0000"

/obj/item/reagent_containers/glass/paint/yellow
	icon_state = "paint_yellow"
	paint_type = "#FFFF00"

/obj/item/reagent_containers/glass/paint/green
	icon_state = "paint_green"
	paint_type = "#00FF00"

/obj/item/reagent_containers/glass/paint/blue
	icon_state = "paint_blue"
	paint_type = "#0000FF"

/obj/item/reagent_containers/glass/paint/violet
	icon_state = "paint_violet"
	paint_type = "#FF00FF"

/obj/item/reagent_containers/glass/paint/black
	icon_state = "paint_black"
	paint_type = "#000000"

/obj/item/reagent_containers/glass/paint/grey
	icon_state = "paint_neutral"
	paint_type = "#808080"

/obj/item/reagent_containers/glass/paint/orange
	icon_state = "paint_orange"
	paint_type = "#FFA500"

/obj/item/reagent_containers/glass/paint/purple
	icon_state = "paint_purple"
	paint_type = "#A500FF"

/obj/item/reagent_containers/glass/paint/cyan
	icon_state = "paint_cyan"
	paint_type = "#00FFFF"

/obj/item/reagent_containers/glass/paint/white
	name = "paint remover bucket"
	icon_state = "paint_white"
	paint_type = "#FFFFFF"
