/obj/structure/crystal
	name = "large crystal"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "crystal"
	density = TRUE

CAPABILITIES(/obj/structure/crystal)
	rolls(nameof(icon_state), pick_one(list("ano70", "ano80")))
	rolls(nameof(desc), PROC_REF(roll_desc))

/// Rolled before init (rolls()): how the crystal catches the eye.
/obj/structure/crystal/proc/roll_desc(datum/roller/R)
	return R.choose(list("It shines faintly as it catches the light.", "It appears to have a faint inner glow.", "It seems to draw you inward as you look it at.", "Something twinkles faintly as you look at it.", "It's mesmerizing to behold."))

// the crystal shatters into shards.
/obj/structure/crystal/on_destroy(force)
	src.visible_message(span_bolddanger("[src] shatters!"))
	for(var/chance in list(75, 50, 25))
		if(prob(chance))
			new /obj/item/material/shard/phoron(src.loc)
		if(prob(chance))
			new /obj/item/material/shard(src.loc)
	..()

//todo: laser_act
