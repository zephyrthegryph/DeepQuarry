/obj/item/trash/material
	icon = 'icons/obj/material_trash.dmi'
	MATERIAL_NONE
	var/list/matter_chances	//List of lists: list(mat_name, chance, amount)
	/// The sprite family it rolls a variant of (rolls()): "[scrap_icon][0 to scrap_variants]".
	var/scrap_icon
	var/scrap_variants = 0

CAPABILITIES(/obj/item/trash/material)
	setup(PROC_REF(add_scrap_materials))
	rolls(nameof(icon_state), PROC_REF(roll_scrap_icon), when = nameof(scrap_icon))

/// Rolled before init (rolls()): one of the family's sprites.
/obj/item/trash/material/proc/roll_scrap_icon(datum/roller/R)
	return "[scrap_icon][R.number(0, scrap_variants)]"

/// Declared setup: add scrap materials, after its parents initialize.
/obj/item/trash/material/proc/add_scrap_materials()
	for(var/list/L in matter_chances)
		if(prob(L[2]))
			var/list/added = list()
			added[L[1]] = max(0, L[3] + rand(-2,2))
			add_materials(added)

/obj/item/trash/material/metal
	name = "scrap metal"
	desc = "A piece of metal that can be recycled in an autolathe."
	icon_state = "metal0"
	scrap_icon = "metal"
	scrap_variants = 4
	matter_chances = list(
		list(MAT_STEEL, 100, 15),
		list(MAT_STEEL, 50, 10),
		list(MAT_STEEL, 10, 20),
		list(MAT_PLASTEEL, 10, 5),
		list(MAT_PLASTEEL, 5, 10)
	)

/obj/item/trash/material/circuit
	name = "burnt circuit"
	desc = "A burnt circuit that can be recycled in an autolathe."
	w_class = ITEMSIZE_SMALL
	icon_state = "circuit0"
	scrap_icon = "circuit"
	scrap_variants = 3
	matter_chances = list(
		list(MAT_GLASS, 100, 4),
		list(MAT_GLASS, 50, 3),
		list(MAT_PLASTIC, 40, 3),
		list(MAT_SILVER, 18, 3),
		list(MAT_GOLD, 17, 3),
		list(MAT_DIAMOND, 4, 2),
	)

/obj/item/trash/material/device
	name = "broken device"
	desc = "A broken device that can be recycled in an autolathe."
	w_class = ITEMSIZE_SMALL
	icon_state = "device0"
	scrap_icon = "device"
	scrap_variants = 3
	matter_chances = list(
		list(MAT_STEEL, 100, 10),
		list(MAT_GLASS, 90, 7),
		list(MAT_PLASTIC, 100, 10),
		list(MAT_SILVER, 16, 7),
		list(MAT_GOLD, 15, 5),
		list(MAT_DIAMOND, 5, 2),
	)

