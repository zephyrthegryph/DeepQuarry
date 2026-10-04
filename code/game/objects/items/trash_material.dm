#define SCRAP_ICON_METAL 1
#define SCRAP_ICON_CIRCUIT 2
#define SCRAP_ICON_DEVICE 3

/obj/item/trash/material
	icon = 'icons/obj/material_trash.dmi'
	MATERIAL_NONE
	var/list/matter_chances	//List of lists: list(mat_name, chance, amount)


TYPE_TABLE_DECLARE(/obj/item/trash/material, scrap_icon_kind, null)

/obj/item/trash/material/Initialize(mapload)
	. = ..()
	for(var/list/L in matter_chances)
		if(prob(L[2]))
			var/list/added = list()
			added[L[1]] = max(0, L[3] + rand(-2,2))
			add_materials(added)

	switch(TYPE_TABLE_GET(src, scrap_icon_kind))
		if(SCRAP_ICON_METAL)
			icon_state = "metal[rand(4)]" // ALLOW(decl): Initialize rolls a random pick per instance; a declaration has no random form
		if(SCRAP_ICON_CIRCUIT)
			icon_state = "circuit[rand(3)]" // ALLOW(decl): Initialize rolls a random pick per instance; a declaration has no random form
		if(SCRAP_ICON_DEVICE)
			icon_state = "device[rand(3)]" // ALLOW(decl): Initialize rolls a random pick per instance; a declaration has no random form




/obj/item/trash/material/metal
	name = "scrap metal"
	desc = "A piece of metal that can be recycled in an autolathe."
	icon_state = "metal0"
	matter_chances = list(
		list(MAT_STEEL, 100, 15),
		list(MAT_STEEL, 50, 10),
		list(MAT_STEEL, 10, 20),
		list(MAT_PLASTEEL, 10, 5),
		list(MAT_PLASTEEL, 5, 10)
	)

TYPE_TABLE(/obj/item/trash/material/metal, scrap_icon_kind, SCRAP_ICON_METAL)


/obj/item/trash/material/circuit
	name = "burnt circuit"
	desc = "A burnt circuit that can be recycled in an autolathe."
	w_class = ITEMSIZE_SMALL
	icon_state = "circuit0"
	matter_chances = list(
		list(MAT_GLASS, 100, 4),
		list(MAT_GLASS, 50, 3),
		list(MAT_PLASTIC, 40, 3),
		list(MAT_SILVER, 18, 3),
		list(MAT_GOLD, 17, 3),
		list(MAT_DIAMOND, 4, 2),
	)

TYPE_TABLE(/obj/item/trash/material/circuit, scrap_icon_kind, SCRAP_ICON_CIRCUIT)


/obj/item/trash/material/device
	name = "broken device"
	desc = "A broken device that can be recycled in an autolathe."
	w_class = ITEMSIZE_SMALL
	icon_state = "device0"
	matter_chances = list(
		list(MAT_STEEL, 100, 10),
		list(MAT_GLASS, 90, 7),
		list(MAT_PLASTIC, 100, 10),
		list(MAT_SILVER, 16, 7),
		list(MAT_GOLD, 15, 5),
		list(MAT_DIAMOND, 5, 2),
	)

TYPE_TABLE(/obj/item/trash/material/device, scrap_icon_kind, SCRAP_ICON_DEVICE)

#undef SCRAP_ICON_METAL
#undef SCRAP_ICON_CIRCUIT
#undef SCRAP_ICON_DEVICE
