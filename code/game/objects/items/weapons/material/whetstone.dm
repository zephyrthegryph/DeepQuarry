//This is in the material folder because it's used by them...
//Actual name may need to change
//All of the important code is in material_weapons.dm
/obj/item/whetstone
	name = "whetstone"
	desc = "A simple, fine grit stone, useful for sharpening dull edges and polishing out dents."
	icon_state = "whetstone"
	force = 3
	w_class = ITEMSIZE_SMALL
	var/repair_amount = 5
	var/repair_time = 40

MSG_DEF_SELF(whetstone/refining, "You begin to refine %T% with %I%...")

CAPABILITIES(/obj/item/whetstone)
	op("refine", stack(/obj/item/stack/material, 5), label("Refine"), begins(MSG(whetstone/refining)), wait(7 SECONDS), then(PROC_REF(refined)))

/obj/item/whetstone/proc/refined(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/material/M = A.held
	var/obj/item/SK
	SK = new /obj/item/material/sharpeningkit(get_turf(user), M.material.name)
	to_chat(user, "You sharpen and refine the [src] into \a [SK].")
	consume(src, user)
	if(SK)
		user.put_in_hands(SK)

/obj/item/material/sharpeningkit
	name = "sharpening kit"
	desc = "A refined, fine grit whetstone, useful for sharpening dull edges, polishing out dents, and, with extra material, replacing an edge."
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "sharpener"
	hitsound = SFX_WEAPONS_GENHIT3
	force_divisor = 0.7
	thrown_force_divisor = 1
	var/repair_amount = 5
	var/repair_time = 40
	var/sharpen_time = 100
	var/uses = 0

/obj/item/material/sharpeningkit/examine(mob/user, distance)
	. = ..()
	. += "There [uses == 1 ? "is" : "are"] [uses] [material] [uses == 1 ? src.material.sheet_singular_name : src.material.sheet_plural_name] left for use."

/obj/item/material/sharpeningkit/Initialize(mapload)
	. = ..()
	setrepair()

/obj/item/material/sharpeningkit/proc/setrepair()
	repair_amount = material.hardness * 0.1
	repair_time = material.density * 0.5 // weight renamed to density.
	sharpen_time = material.density * 3 // weight renamed to density.

CAPABILITIES(/obj/item/material/sharpeningkit)
	op("sharpen", item(/obj/item), priority(OP_PRIORITY_PART + 1), then(PROC_REF(sharpeningkit_interaction_item)))

/// Old attackby. It never called ..(): any item stops here, but afterattack still follows.
/obj/item/material/sharpeningkit/proc/sharpeningkit_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	. = OP_PASS
	if(istype(W, /obj/item/stack/material))
		var/obj/item/stack/material/S = W
		if(S.material == material)
			S.use(1)
			uses += 1
			to_chat(user, "You add a [S.material.name] [S.material.sheet_singular_name] to [src].")
			return

	if(istype(W, /obj/item/material))
		if(istype(W, /obj/item/material/sharpeningkit))
			to_chat(user, "As much as you'd like to sharpen [W] with [src], the logistics just don't work out.")
			return
		var/obj/item/material/M = W
		if(uses >= M.w_class*2)
			if(M.sharpen(src.material.name, sharpen_time, src, user))
				uses -= M.w_class*2
				return
		else
			to_chat(user, "There's not enough spare sheets to sharpen [M]. You need [M.w_class*2] [M.material.sheet_plural_name].")
			return
	else
		to_chat(user, "You can't sharpen [W] with [src]!")
