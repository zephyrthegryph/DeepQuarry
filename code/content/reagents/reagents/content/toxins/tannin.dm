/datum/reagent/toxin/fertilizer/tannin
	name = REAGENT_TANNIN
	id = REAGENT_ID_TANNIN
	description = "A chemical found in some plants as a natural pesticide. It may also aid in regulating growth."
	taste_description = "puckering"
	taste_mult = 1.2
	reagent_state = LIQUID
	strength = 1.5
	color = "#e67819"

/datum/reagent/toxin/fertilizer/tannin/touch_obj(obj/O, volume)
	..()
	if(istype(O, /obj/item/stack/hairlesshide))
		var/obj/item/stack/hairlesshide/HH = O
		HH.rapidcure(round(volume))
	..()
