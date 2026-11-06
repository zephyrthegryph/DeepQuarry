/obj/item/storage/box/glass_extras
	name = "box of cocktail garnishings"
	storage_slots = 14
	starts_with = list(/obj/item/glass_extra = 14)


CAPABILITIES(/obj/item/storage/box/glass_extras)
	configure(storage(accepts = list(/obj/item/glass_extra)))

/obj/item/storage/box/glass_extras/straws
	name = "box of straws"
	starts_with = list(/obj/item/glass_extra/straw = 14)

/obj/item/storage/box/glass_extras/sticks
	name = "box of drink sticks"
	starts_with = list(/obj/item/glass_extra/stick = 14)
