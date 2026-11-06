/obj/item/reagent_containers/food/snacks/egg
	name = "egg"
	desc = "An egg!"
	icon_state = "egg"
	filling_color = "#FDFFD1"
	volume = 10
	opens_into = /datum/msg/snack/crack

/obj/item/reagent_containers/food/snacks/egg/throw_impact(atom/hit_atom)
	. = ..()
	src.reagents.splash(hit_atom, reagents.total_volume)
	src.visible_message(span_red("[src.name] has been squashed."),span_red("You hear a smack."))
	replace_with(src, /obj/effect/decal/cleanable/egg_smudge)

// A crayon of the colours an egg takes colours it.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/egg)
	configure(item_handling(center_x = 16, center_y = 13))
	every(2 SECONDS, then(PROC_REF(grow_step)), when = nameof(growing))
	configure(reagents(add = list(REAGENT_ID_EGG = 3)))
	op("colour", item(/obj/item/pen/crayon), priority(OP_PRIORITY_PART), label("Colour it"),
		needs(req(PROC_REF(takes_colour))), then(PROC_REF(coloured)))

MSG_DEF_SELF(snack/egg_refuses, "The egg refuses to take on this color!")

/// The crayon is one of the colours an egg takes.
/obj/item/reagent_containers/food/snacks/egg/proc/takes_colour(datum/act/op/A)
	var/static/list/colours = list("blue", "green", "mime", "orange", "purple", "rainbow", "red", "yellow")
	var/obj/item/pen/crayon/C = A.held
	return ((C.colourName in colours)) ? null : /datum/msg/snack/egg_refuses

/obj/item/reagent_containers/food/snacks/egg/proc/coloured(datum/act/op/A)
	var/obj/item/pen/crayon/C = A.held
	var/clr = C.colourName
	to_chat(A.actor, span_blue("You color \the [src] [clr]"))
	set_icon_state("egg-[clr]")
	return OP_OK

/obj/item/reagent_containers/food/snacks/egg/blue
	icon_state = "egg-blue"

/obj/item/reagent_containers/food/snacks/egg/green
	icon_state = "egg-green"

/obj/item/reagent_containers/food/snacks/egg/mime
	icon_state = "egg-mime"

/obj/item/reagent_containers/food/snacks/egg/orange
	icon_state = "egg-orange"

/obj/item/reagent_containers/food/snacks/egg/purple
	icon_state = "egg-purple"

/obj/item/reagent_containers/food/snacks/egg/rainbow
	icon_state = "egg-rainbow"

/obj/item/reagent_containers/food/snacks/egg/red
	icon_state = "egg-red"

/obj/item/reagent_containers/food/snacks/egg/yellow
	icon_state = "egg-yellow"
