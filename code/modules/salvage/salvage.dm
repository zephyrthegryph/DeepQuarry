/obj/item/salvage
	name = "salvage"
	desc = "A tonne of salvage from bad mapping practices. Who spawned the base type? Report this on GitHub"
	icon = 'icons/obj/salvage/sellable.dmi'
	force = 5
	throwforce = 5
	throw_speed = 1
	throw_range = 4
	hitsound = SFX_ITEMS_SALVAGE_SALVAGEPICKUP
	drop_sound = SFX_ITEMS_SALVAGE_SALVAGEDROP
	w_class = ITEMSIZE_NORMAL
	var/worth = 100

CAPABILITIES(/obj/item/salvage)
	after_init(0, then(PROC_REF(become_sellable)))

/// Salvage with a worth can be sold.
/obj/item/salvage/proc/become_sellable(datum/act/timer/A)
	if(worth)
		make_sellable(/datum/sellable/salvage)

/obj/item/salvage/examine(mob/user)
	. = ..()
	. += span_notice("This could fetch a good price...")

/obj/item/salvage/ruin
	desc = "A tonne of salvage recovered from an abandoned ruin. Who spawned the base type? Report this on GitHub"

/obj/item/salvage/ruin/pirate
	name = "rum keg"
	desc = "A highly valued keg of aged space rum. Limited edition and sure to be a collector's item."
	icon_state = "barrel"
	color = "#7e5c00"

/obj/item/salvage/ruin/russian
	name = "armaments cache"
	desc = "A crate of old disused Belastrav ballistic firearms clearly long past their usability. This crate would make good scrap metal for shuttle construction."
	icon_state = "weapon_crate"

/obj/item/salvage/ruin/brick
	name = "mysterious brick"
	desc = "A peculier brick formed out of what appears to be plastic. This would make a fantastic collector's item."
	icon_state = "lego_brick"
	hitsound = SFX_ITEMS_SMOLESMALLBUILD
	drop_sound = SFX_ITEMS_DROP_SMOLEMATERIAL

/obj/item/salvage/ruin/nanotrasen
	name = "lost research notes"
	desc = "A collection of research notes penned by old Nanotrasen scientists from decades past, technology lost in time- until you found them. It is a mystery what technology Central Command will push if they could just get their hands on these notes."
	icon_state = "research_doc"
	hitsound = SFX_ITEMS_PICKUP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER
	drop_sound = SFX_ITEMS_DROP_PAPER

CAPABILITIES(/obj/item/salvage/ruin/nanotrasen)
	after_init(0, then(PROC_REF(turn_anomalous)))

/// The notes carry an anomalous effect from the start.
/obj/item/salvage/ruin/nanotrasen/proc/turn_anomalous(datum/act/timer/A)
	become_anomalous()

/obj/item/salvage/ruin/carp
	name = "carp scales"
	desc = "A collection of scales shed from a corrupted space carp. Their culinary potential could mean untold riches for Nanotrasen."
	icon_state = "dragon_scales"
	hitsound = SFX_EFFECTS_GLASS_STEP
	pickup_sound = SFX_EFFECTS_GLASS_STEP
	drop_sound = SFX_EFFECTS_GLASS_STEP

/obj/item/salvage/loot
	desc = "A tonne of salvage looted from a fallen foe. Who spawned the base type? Report this on the github."

/obj/item/salvage/loot/pirate
	name = "stolen jewellery"
	desc = "A collection of stolen jewellery, fashioned from pilfered bluespace crystals and gems. Rumour has it, local pirates have been known to use these accessories to avoid capture."
	icon_state = "pirate_treasure"
	hitsound = SFX_ITEMS_TAPERECORDER_DROP
	pickup_sound = SFX_ITEMS_TAPERECORDER_PICKUP
	drop_sound = SFX_ITEMS_TAPERECORDER_DROP

/obj/item/salvage/loot/russian
	name = "siosp manual"
	desc = "A small manual, written in Neo-Russkyia, detailing the manifesto of Malfoy Ames, father of The Cygni Rebellion. Central Command may wish to share this with their allies in the Trans-Solar Federation."
	icon_state = "ussp_manual"
	hitsound = SFX_ITEMS_PICKUP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER
	drop_sound = SFX_ITEMS_DROP_PAPER

/obj/item/salvage/loot/syndicate
	name = "syndicate intel"
	desc = "A folder detailing Syndicate plans to infiltrate and sabotage operations in the Vir system. Central Command may find use of this to aid them in counter-intelligence."
	icon_state = "syndie_doc"
	hitsound = SFX_ITEMS_PICKUP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER
	drop_sound = SFX_ITEMS_DROP_PAPER
