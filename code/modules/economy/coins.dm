/*****************************Coin********************************/

/obj/item/coin
	icon = 'icons/obj/coins.dmi'
	name = "Coin"
	desc = "A simple coin you can flip."
	icon_state = "coin"
	randpixel = 8
	force = 0.0
	throwforce = 0.0
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	var/string_attached
	var/sides = 2
	drop_sound = 'sound/items/drop/ring.ogg'
	pickup_sound = 'sound/items/pickup/ring.ogg'

/obj/item/coin/Initialize(mapload)
	. = ..()
	randpixel_xy()

/obj/item/coin/gold
	name = MAT_GOLD + " coin"
	desc = "A shiny " + MAT_GOLD + " coin. Just like in the old movies with pirates!"
	icon_state = "coin_gold"
	matter = list(MAT_GOLD = 250)

/obj/item/coin/silver
	name = MAT_SILVER + " coin"
	desc = "A shiny " + MAT_SILVER + " coin. You can almost see your reflection in it. Unless you're a vampire."
	icon_state = "coin_silver"
	matter = list(MAT_SILVER = 250)

/obj/item/coin/copper
	name = MAT_COPPER + " coin"
	desc = "A sturdy " + MAT_COPPER + " coin. The preferred tender of people who like to make other people count a lot."
	icon_state = "coin_copper"
	matter = list(MAT_COPPER = 250)

/obj/item/coin/diamond
	name = MAT_DIAMOND + " coin"
	desc = "A coin made of solid " + MAT_DIAMOND + ". Carbon, really, but who's counting?" // me, I'm counting
	icon_state = "coin_diamond"
	matter = list(MAT_DIAMOND = 250)

/obj/item/coin/graphite
	name = MAT_GRAPHITE + " coin"
	desc = "A small pressed plaque of " + MAT_GRAPHITE + ". This seems... impractical. Maybe you could use it as a pencil in a pinch?"
	icon_state = "coin_graphite"
	matter = list(MAT_GRAPHITE = 250)

/obj/item/coin/iron
	name = MAT_IRON + " coin"
	desc = "A dull " + MAT_IRON + " coin. Not that it's boring, it's just a bit plain."
	icon_state = "coin_iron"
	matter = list(MAT_IRON = 250)

/obj/item/coin/steel
	name = MAT_STEEL + " coin"
	desc = "A plain " + MAT_STEEL + " coin. You'd think they'd make more coins out of this, considering how plentiful it is."
	icon_state = "coin_steel"
	matter = list(MAT_STEEL = 250)

/obj/item/coin/durasteel
	name = MAT_DURASTEEL + " coin"
	desc = "A shiny " + MAT_DURASTEEL + " coin. Keep it in your breast pocket, maybe it'll stop a bullet someday."
	icon_state = "coin_durasteel"
	matter = list(MAT_DURASTEEL = 250)

/obj/item/coin/plasteel
	name = MAT_PLASTEEL + " coin"
	desc = "Someone made a coin out of " + MAT_PLASTEEL + ". Now why would they do that?"
	icon_state = "coin_plasteel"
	matter = list(MAT_PLASTEEL = 250)

/obj/item/coin/titanium
	name = MAT_TITANIUM + " coin"
	desc = "A shiny " + MAT_TITANIUM + " coin with some commemorative markings."
	icon_state = "coin_titanium"
	matter = list(MAT_TITANIUM = 250)

/obj/item/coin/lead
	name = MAT_LEAD + " coin"
	desc = "A heavy coin indeed. Shame it's worthless as anything other than a paperweight."
	icon_state = "coin_lead"
	matter = list(MAT_LEAD = 250)

/obj/item/coin/phoron
	name = "solid " + MAT_PHORON + " coin"
	desc = "Solid " + MAT_PHORON + ", pressed into a coin and laminated for safety. Go ahead, lick it."
	icon_state = "coin_phoron"
	matter = list(MAT_PHORON = 250)

/obj/item/coin/uranium
	name = MAT_URANIUM + " coin"
	desc = "A " + MAT_URANIUM + " coin. You probably don't want to store this in your pants pocket..."
	icon_state = "coin_uranium"
	matter = list(MAT_URANIUM = 250)
	var/last_event = 0
	var/active = 0

/obj/item/coin/uranium/Initialize(mapload)
	. = ..()
	START_PROCESSING(SSobj, src)

/obj/item/coin/uranium/Destroy()
	STOP_PROCESSING(SSobj, src)
	. = ..()

/obj/item/coin/uranium/process()
	radiate()
	..()

/obj/item/coin/uranium/proc/radiate()
	SIGNAL_HANDLER
	if(active)
		return
	if(world.time <= last_event + 1.5 SECONDS)
		return
	active = TRUE
	radiation_pulse(
		src,
		max_range = 1,
		threshold = RAD_LIGHT_INSULATION,
		chance = URANIUM_IRRADIATION_CHANCE,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = 2
	)
	last_event = world.time
	active = FALSE

/obj/item/coin/platinum
	name = MAT_PLATINUM + " coin"
	desc = "A shiny " + MAT_PLATINUM + " coin. Truth is, the game was rigged from the start."
	icon_state = "coin_platinum"
	matter = list(MAT_GOLD = 250)

/obj/item/coin/morphium
	name = MAT_MORPHIUM + " coin"
	desc = "Solid " + MAT_MORPHIUM + ", made into a coin. Extravagant is putting it lightly."
	icon_state = "coin_morphium"
	matter = list(MAT_MORPHIUM = 250)

/obj/item/coin/aluminium
	name = MAT_ALUMINIUM + " coin"
	desc = "Someone decided to make a coin out of" + MAT_ALUMINIUM + ". Now your wallet can be lighter than ever."
	icon_state = "coin_aluminium"
	matter = list(MAT_ALUMINIUM = 250)

/obj/item/coin/verdantium
	name = MAT_VERDANTIUM + " coin"
	desc = "Shiny green " + MAT_VERDANTIUM + ", pressed into a coin. It almost seems to glimmer under starlight."
	icon_state = "coin_verdantium"
	matter = list(MAT_VERDANTIUM = 250)

/obj/item/coin/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W,/obj/item/stack/cable_coil))
		var/obj/item/stack/cable_coil/CC = W
		if(string_attached)
			balloon_alert(user, "there is a string already attached to \the [src]")
			return
		if (CC.use(1))
			add_overlay("coin_string_overlay")
			string_attached = 1
			balloon_alert(user, "string attached to \the [src]")
		else
			balloon_alert(user, "the coil seems to be empty...")
		return
	else if(W.has_tool_quality(TOOL_WIRECUTTER))
		if(!string_attached)
			..()
			return

		var/obj/item/stack/cable_coil/CC = new (user.loc, 1)
		CC.update_icon()
		cut_overlays()
		string_attached = null
		balloon_alert(user, "string detached")
	else ..()

/obj/item/coin/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	var/result = rand(1, sides)
	var/comment = ""
	if(result == 1)
		comment = "tails"
	else if(result == 2)
		comment = "heads"
	user.visible_message(span_notice("[user] has thrown \the [src]. It lands on [comment]!"), \
							span_notice("You throw \the [src]. It lands on [comment]!"))
	balloon_alert_visible("\the [src] lands on [comment]!", "\the [src] lands on [comment]!")


// === merged from coins_vr.dm during hard-fork de-suffix (verified no override-order change) ===
//Weird coins that I would prefer didn't work with normal vending machines. Might use them to make weird vending machines later.

/obj/item/aliencoin
	icon = 'icons/obj/aliencoins.dmi'
	name = "curious coin"
	desc = "A curious triangular coin made primarily of some kind of dark, smooth metal. "
	icon_state = "triangle"
	randpixel = 8
	force = 0.5
	throwforce = 0.5
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	var/sides = 2
	var/value = 1
	drop_sound = 'sound/items/drop/ring.ogg'
	pickup_sound = 'sound/items/pickup/ring.ogg'

/obj/item/aliencoin/Initialize(mapload)
	. = ..()
	randpixel_xy()

/obj/item/aliencoin/basic

/obj/item/aliencoin/gold
	name = "curious coin"
	icon_state = "triangle-g"
	desc = "A curious triangular coin made primarily of some kind of dark, smooth metal. This one's markings appear to reveal a golden material underneath."
	value = 10

/obj/item/aliencoin/silver
	name = "curious coin"
	icon_state = "triangle-s"
	desc = "A curious triangular coin made primarily of some kind of dark, smooth metal. This one's markings appear to reveal a silver material underneath."
	value = 5

/obj/item/aliencoin/phoron
	name = "curious coin"
	icon_state = "triangle-p"
	desc = "A curious triangular coin made primarily of some kind of dark, smooth metal. This one's markings appear to reveal a purple material underneath."
	value = 20


/obj/item/aliencoin/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	var/result = rand(1, sides)
	var/comment = ""
	if(result == 1)
		comment = "tails"
	else if(result == 2)
		comment = "heads"
	user.visible_message(span_notice("[user] has thrown [src]. It lands on [comment]! "), runemessage = "[src] landed on [comment]")
	if(rand(1,20) == 1)
		user.visible_message(span_notice("[user] fumbled the [src]!"), runemessage = "fumbles [src]")
		user.remove_from_mob(src)

/obj/item/aliencoin/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += span_notice("It has some writing along its edge that seems to be some language that you are not familiar with. The face of the coin is very smooth, with what appears to be some kind of angular logo along the left side, and a couple of lines of the alien text along the opposite side. The reverse side is similarly smooth, the top of it features what appears to be some kind of vortex, surrounded by six stars, three on either side, with further swirls and intricate patterns along the bottom sections of this face. Looking closely, you can see that there is more text hidden among the swirls.")
