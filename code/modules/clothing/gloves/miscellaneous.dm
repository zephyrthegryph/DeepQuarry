/obj/item/clothing/gloves/captain
	desc = "Regal blue gloves, with a nice gold trim. Swanky."
	name = "site manager's gloves"
	icon_state = "captain"
	item_state_slots = list(slot_r_hand_str = "blue", slot_l_hand_str = "blue")

/obj/item/clothing/gloves/cyborg
	desc = "beep boop borp"
	name = "cyborg gloves"
	icon_state = "black"
	item_state = "r_hands"
	siemens_coefficient = 1.0

/obj/item/clothing/gloves/forensic
	desc = "Specially made gloves for forensic technicians. The luminescent threads woven into the material stand out under scrutiny."
	name = "forensic gloves"
	icon_state = "forensic"
	item_state = "black"
	permeability_coefficient = 0.05

	min_cold_protection_temperature = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE
	resistance_flags = FIRE_PROOF

/obj/item/clothing/gloves/swat
	desc = "These tactical gloves are somewhat fire and impact-resistant."
	name = "\improper SWAT Gloves"
	icon_state = "swat"
	item_state = "swat"
	siemens_coefficient = 0.50
	permeability_coefficient = 0.05
	min_cold_protection_temperature = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE
	armor = list(melee = 15, bullet = 10, laser = 10, energy = 10, bomb = 5, bio = 0, rad = 0) // CHOMPedit: Now protective.
	resistance_flags = FIRE_PROOF

/obj/item/clothing/gloves/combat //CHOMPedit: Combined effect of SWAT gloves and insulated gloves, with better protective stats.
	desc = "These military-grade tactical gloves protect the user from electrical shocks, fire, high-velocity impacts and varying temperatures." // CHOMPedit: Updated description.
	name = "combat gloves"
	icon_state = "swat"
	item_state = "swat"
	siemens_coefficient = 0
	permeability_coefficient = 0.05
	min_cold_protection_temperature = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE
	armor = list(melee = 20, bullet = 15, laser = 15, energy = 15, bomb = 10, bio = 0, rad = 0) // CHOMPedit: Now protective.
	resistance_flags = FIRE_PROOF

/obj/item/clothing/gloves/sterile
	name = "sterile gloves"
	desc = "Sterile gloves."
	icon_state = "latex"
	item_state_slots = list(slot_r_hand_str = "white", slot_l_hand_str = "white")
	siemens_coefficient = 1.0 //thin latex gloves, much more conductive than fabric gloves (basically a capacitor for AC)
	permeability_coefficient = 0.01
	germ_level = 0
	fingerprint_chance = 25
	drop_sound = 'sound/items/drop/rubber.ogg'
	pickup_sound = 'sound/items/pickup/rubber.ogg'
//	var/balloonPath = /obj/item/latexballon

//TODO: Make inflating gloves a thing
/*/obj/item/clothing/gloves/sterile/proc/Inflate(/mob/living/carbon/human/user)
	user.visible_message(span_infoplain(span_bold("\The [src]") + " expands!"))
	qdel(src)*/

/obj/item/clothing/gloves/sterile/latex
	name = "latex gloves"
	desc = "Sterile latex gloves."

/obj/item/clothing/gloves/sterile/nitrile
	name = "nitrile gloves"
	desc = "Sterile nitrile gloves"
	icon_state = "nitrile"
	item_state = "ngloves"
//	balloonPath = /obj/item/nitrileballoon

/obj/item/clothing/gloves/botanic_leather
	desc = "These leather work gloves protect against thorns, barbs, prickles, spikes and other harmful objects of floral origin."
	name = "botanist's leather gloves"
	icon_state = "leather"
	item_state_slots = list(slot_r_hand_str = "lightbrown", slot_l_hand_str = "lightbrown")
	permeability_coefficient = 0.05
	siemens_coefficient = 0.75 //thick work gloves
	drop_sound = 'sound/items/drop/leather.ogg'
	pickup_sound = 'sound/items/pickup/leather.ogg'

/obj/item/clothing/gloves/duty
	desc = "These brown duty gloves are made from a durable synthetic."
	name = "work gloves"
	icon_state = "work"
	item_state = "wgloves"
	armor = list(melee = 10, bullet = 10, laser = 10, energy = 5, bomb = 0, bio = 0, rad = 0)
// CHOMPEdit Start - If they resist lasers and energy they should help inulate against heat and cold.
	cold_protection = HANDS
	min_cold_protection_temperature = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE
	heat_protection = HANDS
	max_heat_protection_temperature = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE
// CHOMPEdit End
/obj/item/clothing/gloves/tactical
	desc = "These brown tactical gloves are made from a durable synthetic, and have hardened knuckles."
	name = "tactical gloves"
	icon_state = "work"
	item_state = "wgloves"
	force = 5
	punch_force = 3
	siemens_coefficient = 0.75
	permeability_coefficient = 0.05
	armor = list(melee = 30, bullet = 10, laser = 10, energy = 15, bomb = 20, bio = 0, rad = 0)

/obj/item/clothing/gloves/vox
	desc = "These bizarre gauntlets seem to be fitted for... bird claws?"
	name = "insulated gauntlets"
	icon_state = "gloves-vox"
	item_state = "gloves-vox"
	flags = PHORONGUARD
	siemens_coefficient = 0
	permeability_coefficient = 0.05
	species_restricted = list("Vox")
	drop_sound = 'sound/items/drop/metalboots.ogg'
	pickup_sound = 'sound/items/pickup/toolbox.ogg'
	armor = list (melee = 20, bullet = 15, laser = 10, energy = 10, bomb =5, bio = 30, rad = 30) //gently bumped up Heavy engineering gloves value for protection //ChompEdit

	min_cold_protection_temperature = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE
	resistance_flags = FIRE_PROOF

/obj/item/clothing/gloves/ranger
	var/glovecolor = "white"
	name = "ranger gloves"
	desc = "The gloves of the Rangers are the least memorable part. They're not even insulated in the show, so children \
	don't try and take apart a toaster with inadequate protection. They only serve to complete the fancy outfit."
	icon = 'icons/obj/clothing/ranger.dmi'
	icon_state = "ranger_gloves"

/obj/item/clothing/gloves/ranger/Initialize(mapload)
	. = ..()
	if(icon_state == "ranger_gloves")
		name = "[glovecolor] ranger gloves"
		icon_state = "[glovecolor]_ranger_gloves"

/obj/item/clothing/gloves/ranger/black
	glovecolor = "black"

/obj/item/clothing/gloves/ranger/pink
	glovecolor = "pink"

/obj/item/clothing/gloves/ranger/green
	glovecolor = "green"

/obj/item/clothing/gloves/ranger/cyan
	glovecolor = "cyan"

/obj/item/clothing/gloves/ranger/orange
	glovecolor = "orange"

/obj/item/clothing/gloves/ranger/yellow
	glovecolor = "yellow"

/obj/item/clothing/gloves/waterwings
	name = "water wings"
	desc = "Swim aids designed to help a wearer float in water and learn to swim."
	icon_state = "waterwings"


// === merged from miscellaneous_vr.dm during hard-fork de-suffix (verified no override-order change) ===
//CHOMPEdit Start??? Somehow wedding rigs were attributed to me from 9 years ago but is not upstream and is only on here, yet there's no chomp edits?
/obj/item/clothing/gloves/weddingring
	name = "golden wedding ring"
	desc = "For showing your devotion to another person. It has a golden glimmer to it."
	icon_state = "wedring_g"
	item_state = "wedring_g"
	var/partnername = ""
	body_parts_covered = null
	special_handling = TRUE

/obj/item/clothing/gloves/weddingring/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	partnername = tgui_input_text(user, "Would you like to change the holoengraving on the ring?", "Name your betrothed", "Bae", MAX_NAME_LEN)
	name = "[initial(name)] - [partnername]"

/obj/item/clothing/gloves/weddingring/silver
	name = "silver wedding ring"
	icon_state = "wedring_s"
	item_state = "wedring_s"
//CHOMPEdit End???

/obj/item/clothing/gloves/color
	name = "gloves"
	desc = "A pair of gloves, they don't look special in any way."
	item_state_slots = list(slot_r_hand_str = "white", slot_l_hand_str = "white")
	icon_state = "latex"

// Armor Versions Here
/obj/item/clothing/gloves/combat/knight
	desc = "ye olde armored gauntlets"
	name = "knight gauntlets"
	icon_state = "black"
	item_state = "black"
	siemens_coefficient = 2
	permeability_coefficient = 0.05
	min_cold_protection_temperature = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE
	armor = list(melee = 80, bullet = 50, laser = 10, energy = 0, bomb = 0, bio = 0, rad = 0)

/obj/item/clothing/gloves/combat/knight/brown
	desc = "ye olde armored gauntlets"
	name = "knight gauntlets"
	icon_state = "brown"
	item_state = "brown"

// Costume Versions Here
/obj/item/clothing/gloves/combat/knight_costume
	desc = "ye olde armored gauntlets"
	name = "knight gauntlets"
	icon_state = "black"
	item_state = "black"
	siemens_coefficient = 2
	permeability_coefficient = 0.05
	min_cold_protection_temperature = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE
	armor = list(melee = 0, bullet = 0, laser = 0, energy = 0, bomb = 0, bio = 0, rad = 0)

/obj/item/clothing/gloves/combat/knight_costume/brown
	desc = "ye olde armored gauntlets"
	name = "knight gauntlets"
	icon_state = "brown"
	item_state = "brown"

/obj/item/clothing/gloves/heavy_engineer
	desc = "Elbow-length insulated gloves, with added reinforcement. They'll keep your fingers and forearms just that little bit safer from things that might try to melt, mangle, or burn them. A tag on the inside of each glove reads \'PROPERTY OF ENGINEERING, RETURN IF FOUND\'."
	name = "heavy-duty engineering gloves"
	icon_state = "heavy_engi"
	item_state = "heavy_engi"
	siemens_coefficient = 0
	permeability_coefficient = 0.05
	flags = THICKMATERIAL
	armor = list(melee = 10, bullet = 10, laser = 10, energy = 5, bomb = 0, bio = 30, rad = 30)
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/hands/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/hands/mob_vox.dmi',
		SPECIES_WEREBEAST = 'icons/inventory/hands/mob_werebeast.dmi')

	heat_protection = HANDS|ARMS
	cold_protection = HANDS|ARMS
	min_cold_protection_temperature = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE

/obj/item/clothing/gloves/black/bloodletter
	desc = "A pair of ordinary looking black gloves. On closer examination, they seem somewhat well-made, with an almost metallic sheen to them."
	description_fluff = "A prohibited concealed weapon, the Melee Grip Reinforcement system is the product of the military applications of nanotechnology. The striking face of the glove hardens in response to impact, producing monofilament blades from the knuckles to greatly enhance the wearer's close-combat lethality."
	special_attack_type = /datum/unarmed_attack/hardclaws
