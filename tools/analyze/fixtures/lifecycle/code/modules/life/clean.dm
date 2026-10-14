// The clean types: not latent-safe, but they register only in on_materialize().
/obj/item/pda/Initialize(mapload)
	GLOB.pda_list += src

/obj/item/radio/Initialize(mapload)
	set_frequency(1)

/obj/item/radio/proc/Initialize(mapload)
	START_PROCESSING(SSobj, src)

/obj/item/gps/Initialize(mapload)
	GLOB.gps_list += src

/obj/item/implant/tracking/Initialize(mapload)
	GLOB.tracking += src

/obj/item/card/id/Initialize(mapload)
	GLOB.ids += src

/obj/item/card/id/guest/Initialize(mapload)
	GLOB.guest_ids += src

/obj/item/card/id/other/Initialize(mapload)
	GLOB.other_ids += src

/obj/item/pda/sub/Initialize(mapload)
	GLOB.pda_sub += src

	GLOB.indented_head += src
