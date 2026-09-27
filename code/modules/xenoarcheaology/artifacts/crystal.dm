/obj/structure/crystal
	name = "large crystal"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "crystal"
	density = TRUE

/obj/structure/crystal/Initialize(mapload)
	. = ..()

	icon_state = pick("ano70","ano80")

	desc = pick(
	"It shines faintly as it catches the light.",
	"It appears to have a faint inner glow.",
	"It seems to draw you inward as you look it at.",
	"Something twinkles faintly as you look at it.",
	"It's mesmerizing to behold.")

// LIFECYCLE: the crystal shatters into shards.
/obj/structure/crystal/Destroy()
	src.visible_message(span_bolddanger("[src] shatters!"))
	for(var/chance in list(75, 50, 25))
		if(prob(chance))
			new /obj/item/material/shard/phoron(src.loc)
		if(prob(chance))
			new /obj/item/material/shard(src.loc)
	. = ..()

//todo: laser_act
