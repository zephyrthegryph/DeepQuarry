//Refurbished Set
//Voidsuits from old Terran exploration vessels and naval ships.

//Standard Crewsuit (GRAY)
//Nothing really special here. Some light resists for mostly-non-combat purposes. The rad protection ain't bad?
//The reduced slowdown is an added bonus - something to make it worth considering using if you do find it.
/obj/item/clothing/head/helmet/space/void/refurb
	name = "vintage crewman's voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum. This one is devoid of any identifying markings or rank indicators."
	icon_state = "rig0-vintagecrew"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black", slot_l_hand_str = "syndicate-helm-black")
	armor = list(melee = 30, bullet = 15, laser = 15,energy = 5, bomb = 20, bio = 100, rad = 50)
	light_overlay = "helmet_light"

/obj/item/clothing/suit/space/void/refurb
	name = "vintage crewman's voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer spacers swear by these old things, even if new powered hardsuits have more features and better armor. This one is devoid of any identifying markings or rank indicators."
	icon_state = "rig-vintagecrew"
	item_state_slots = list(slot_r_hand_str = "sec_voidsuitTG", slot_l_hand_str = "sec_voidsuitTG")
	armor = list(melee = 30, bullet = 15, laser = 15,energy = 5, bomb = 20, bio = 100, rad = 50)
	allowed = list(POCKET_ALL_TANKS, POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_ENGINEERING, POCKET_MINING)

//Engineering Crewsuit (ORANGE, RING)
//This is probably the most appealing to get your hands on for basic protection and the specialist stuff
//Don't expect it to stand up to modern assault/laser rifles, but it'll make you a fair bit tougher against most low-end pistols and SMGs
/obj/item/clothing/head/helmet/space/void/refurb/engineering
	name = "vintage engineering voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. This one in particular seems to be an ode to the Ship of Theseus, but the insulation and radiation proofing are top-notch, and it has several oily stains that seem to be impossible to scrub off."
	icon_state = "rig0-vintageengi"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black", slot_l_hand_str = "syndicate-helm-black")
	armor = list(melee = 40, bullet = 20, laser = 20, energy = 5, bomb = 35, bio = 100, rad = 100)
	min_pressure_protection = 0  * ONE_ATMOSPHERE
	max_pressure_protection = 15 * ONE_ATMOSPHERE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE+10000

/obj/item/clothing/suit/space/void/refurb/engineering
	name = "vintage engineering voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. This one in particular seems to be an ode to the Ship of Theseus, but the insulation and radiation proofing are top-notch. The chestplate bears the logo of an old shipyard - though you don't recognize the name."
	icon_state = "rig-vintageengi"
	item_state_slots = list(slot_r_hand_str = "sec_voidsuitTG", slot_l_hand_str = "sec_voidsuitTG")
	slowdown = 1
	armor = list(melee = 40, bullet = 20, laser = 20, energy = 5, bomb = 35, bio = 100, rad = 100)
	min_pressure_protection = 0  * ONE_ATMOSPHERE
	max_pressure_protection = 15 * ONE_ATMOSPHERE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE+10000
	breach_threshold = 14 //These are kinda thicc
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_ENGINEERING, POCKET_CE, POCKET_MINING, POCKET_HEAVYTOOLS)

//Medical Crewsuit (GREEN, CROSS)
//This thing is basically tissuepaper, but it has very solid rad protection for its age
//It also has the bonus of not slowing you down quite as much as other suits, same as the crew suit
/obj/item/clothing/head/helmet/space/void/refurb/medical
	name = "vintage medical voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum. The green and white markings indicate this as a medic's suit."
	icon_state = "rig0-vintagemedic"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black", slot_l_hand_str = "syndicate-helm-black")
	armor = list(melee = 30, bullet = 15, laser = 15, energy = 5, bomb = 25, bio = 100, rad = 75)

/obj/item/clothing/head/helmet/space/void/refurb/medical/alt
	name = "vintage medical voidsuit bubble helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor on this model has been expanded to the full bubble design to improve visibility. Wouldn't want to lose a scalpel in someone's abdomen because your visor fogged over!"
	icon_state = "rig0-vintagepilot"

/obj/item/clothing/suit/space/void/refurb/medical
	name = "vintage medical voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer spacers swear by these old things, even if new powered hardsuits have more features and better armor. The green and white markings indicate this as a medic's suit."
	icon_state = "rig-vintagemedic"
	item_state_slots = list(slot_r_hand_str = "sec_voidsuitTG", slot_l_hand_str = "sec_voidsuitTG")
	armor = list(melee = 30, bullet = 15, laser = 15, energy = 5, bomb = 25, bio = 100, rad = 75)
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_MEDICAL)

//Marine Crewsuit (BLUE, SHIELD)
//Really solid, balance between Sec and Sec EVA, but it has slightly worse shock protection
/obj/item/clothing/head/helmet/space/void/refurb/marine
	name = "vintage marine's voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum. The blue markings indicate this as the marine/guard variant, likely from a merchant ship."
	icon_state = "rig0-vintagemarine"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black", slot_l_hand_str = "syndicate-helm-black")
	armor = list(melee = 40, bullet = 35, laser = 35, energy = 5, bomb = 40, bio = 100, rad = 50)
	siemens_coefficient = 0.8

/obj/item/clothing/suit/space/void/refurb/marine
	name = "vintage marine's voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer marines swear by these old things, even if new powered hardsuits have more features and better armor. The blue markings indicate this as the marine/guard variant, likely from a merchant ship."
	icon_state = "rig-vintagemarine"
	item_state_slots = list(slot_r_hand_str = "sec_voidsuitTG", slot_l_hand_str = "sec_voidsuitTG")
	slowdown = 1
	armor = list(melee = 40, bullet = 35, laser = 35, energy = 5, bomb = 40, bio = 100, rad = 50)
	breach_threshold = 14 //These are kinda thicc
	resilience = 0.15 //Armored
	siemens_coefficient = 0.8
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_SECURITY)

//Officer Crewsuit (GOLD, X)
//The best of the bunch - at the time, this would have been almost cutting edge
//Now it's good, but it's badly outclassed by the hot shit that the TSCs and such can get
/obj/item/clothing/head/helmet/space/void/refurb/officer
	name = "vintage officer's voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum. This variant appears to be an officer's, and has the best protection of all the old models."
	icon_state = "rig0-vintageofficer"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black", slot_l_hand_str = "syndicate-helm-black")
	armor = list(melee = 50, bullet = 45, laser = 45, energy = 10, bomb = 30, bio = 100, rad = 60)
	siemens_coefficient = 0.7

/obj/item/clothing/suit/space/void/refurb/officer
	name = "vintage officer's voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer spacers swear by these old things, even if new powered hardsuits have more features and better armor. This variant appears to be an officer's, and has the best protection of all the old models."
	icon_state = "rig-vintageofficer"
	item_state_slots = list(slot_r_hand_str = "sec_voidsuitTG", slot_l_hand_str = "sec_voidsuitTG")
	slowdown = 1
	armor = list(melee = 50, bullet = 45, laser = 45, energy = 10, bomb = 30, bio = 100, rad = 60)
	breach_threshold = 16 //Extra Thicc
	resilience = 0.1 //Heavily Armored
	siemens_coefficient = 0.7
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_SECURITY)

//Pilot Crewsuit (ROYAL BLUE, I)
//The lightest weight of the lot, but protection is about the same as the crew variant's. It has an extra helmet variant for those who prefer that design.
/obj/item/clothing/head/helmet/space/void/refurb/pilot
	name = "vintage pilot's voidsuit bubble helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The standard pilot model has a nice clear bubble helmet that doesn't fog up easily and has much better visibility, at the cost of relatively poor protection."
	icon_state = "rig0-vintagepilot"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black", slot_l_hand_str = "syndicate-helm-black")
	armor = list(melee = 25, bullet = 20, laser = 20, energy = 5, bomb = 20, bio = 100, rad = 50)
	siemens_coefficient = 0.9

//fluff alt-variant helmet, no changes to protection or anything despite the desc (and it wouldn't matter unless you found a base-type since armor values aren't transferred during refits)
/obj/item/clothing/head/helmet/space/void/refurb/pilot/alt
	name = "vintage pilot's voidsuit helmet"
	desc = "For pilots who don't like the increased fracture vulnerability of the huge visor, overrides exist in certain cyclers that allow pilots to use the conventional helmet design. It's a little more claustrophobic, but some find the all-round protection to be worth the loss in visibility."
	icon_state = "rig0-vintagepilotalt"

/obj/item/clothing/suit/space/void/refurb/pilot
	name = "vintage pilot's voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer spacers swear by these old things, even if new powered hardsuits have more features and better armor. The royal blue markings indicate this is the pilot's variant; low protection but ultra-lightweight."
	icon_state = "rig-vintagepilot"
	item_state_slots = list(slot_r_hand_str = "sec_voidsuitTG", slot_l_hand_str = "sec_voidsuitTG")
	slowdown = 0
	armor = list(melee = 25, bullet = 20, laser = 20, energy = 5, bomb = 20, bio = 100, rad = 50)
	siemens_coefficient = 0.9
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_MINING)

//Scientist Crewsuit (PURPLE, O)
//Baseline values are slightly worse than the gray crewsuit, but it has significantly better Energy protection and is the only other suit with 100% rad immunity besides the engi suit
/obj/item/clothing/head/helmet/space/void/refurb/research
	name = "vintage research voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum. The purple markings indicate this as a scientist's helmet. Got your crowbar handy?"
	icon_state = "rig0-vintagescientist"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black", slot_l_hand_str = "syndicate-helm-black")
	armor = list(melee = 25, bullet = 10, laser = 10, energy = 50, bomb = 10, bio = 100, rad = 100)
	siemens_coefficient = 0.8

/obj/item/clothing/head/helmet/space/void/refurb/research/alt
	name = "vintage research voidsuit bubble helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. This version has been refitted with the distinctive bubble design to increase visibility, so that you can see what you're sciencing better!"
	icon_state = "rig0-vintagepilot"

/obj/item/clothing/suit/space/void/refurb/research
	name = "vintage research voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer spacers swear by these old things, even if new powered hardsuits have more features and better armor. The purple markings indicate this as a scientist's suit. Keep your eyes open for ropes."
	icon_state = "rig-vintagescientist"
	item_state_slots = list(slot_r_hand_str = "sec_voidsuitTG", slot_l_hand_str = "sec_voidsuitTG")
	armor = list(melee = 25, bullet = 10, laser = 10, energy = 50, bomb = 10, bio = 100, rad = 100)
	siemens_coefficient = 0.8
	allowed = list(POCKET_ALL_TANKS, POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_MINING, POCKET_XENOARC, /obj/item/storage/firstaid)

//Miner's Crewsuit (BROWN)
//Basically just the basic suit, but with brown markings. If anyone wants to tweak this, go wild.
/obj/item/clothing/head/helmet/space/void/refurb/mining
	name = "vintage miner's's voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum. This one has brown markings, denoting it as a miner's helmet."
	icon_state = "rig0-vintageminer"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black", slot_l_hand_str = "syndicate-helm-black")
	armor = list(melee = 30, bullet = 15, laser = 15,energy = 5, bomb = 20, bio = 100, rad = 50)
	light_overlay = "helmet_light"

/obj/item/clothing/suit/space/void/refurb/mining
	name = "vintage miner's voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer spacers swear by these old things, even if new powered hardsuits have more features and better armor. This one has brown markings, denoting it as a miner's suit."
	icon_state = "rig-vintageminer"
	item_state_slots = list(slot_r_hand_str = "sec_voidsuitTG", slot_l_hand_str = "sec_voidsuitTG")
	armor = list(melee = 30, bullet = 15, laser = 15,energy = 5, bomb = 20, bio = 100, rad = 50)
	allowed = list(POCKET_ALL_TANKS, POCKET_GENERIC, POCKET_EMERGENCY, POCKET_MINING)

//Mercenary Crewsuit (RED, CROSS)
//The best of the best, this should be ultra-rare
/obj/item/clothing/head/helmet/space/void/refurb/mercenary
	name = "vintage mercenary voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum. The red markings indicate this as the mercenary variant. The company ID has been scratched off."
	icon_state = "rig0-vintagemerc"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black", slot_l_hand_str = "syndicate-helm-black")
	armor = list(melee = 55, bullet = 45, laser = 45, energy = 25, bomb = 50, bio = 100, rad = 50)
	siemens_coefficient = 0.6

/obj/item/clothing/suit/space/void/refurb/mercenary
	name = "vintage mercenary voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer mercs swear by these old things, even if new powered hardsuits have more features and better armor. The red markings indicate this as the mercenary variant. The company ID has been scratched off."
	icon_state = "rig-vintagemerc"
	item_state_slots = list(slot_r_hand_str = "sec_voidsuitTG", slot_l_hand_str = "sec_voidsuitTG")
	slowdown = 1.5 //the tradeoff for being hot shit almost on par with a crimson suit is that it slows you down even more
	armor = list(melee = 55, bullet = 45, laser = 45, energy = 25, bomb = 50, bio = 100, rad = 50)
	breach_threshold = 16 //Extra Thicc
	resilience = 0.05 //Military Armor
	siemens_coefficient = 0.6
	allowed = list(POCKET_ALL_TANKS, POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_SECURITY)


// === merged from event_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/clothing/head/helmet/space/void/refurb/talon
	name = "talon crew voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum."
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/suit/space/void/refurb/talon
	name = "talon crew voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer spacers swear by these old things, even if new powered hardsuits have more features and better armor."

/obj/item/clothing/head/helmet/space/void/refurb/engineering/talon
	name = "talon engineering voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. This one in particular must be several decades old, but the insulation and radiation proofing are top-notch. Don't mind the grease marks."
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/suit/space/void/refurb/engineering/talon
	name = "talon engineering voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. This one in particular must be several decades old, but the insulation and radiation proofing are top-notch. The chestplate has a simple gear logo on it."

/obj/item/clothing/head/helmet/space/void/refurb/medical/talon
	name = "talon medical voidsuit helmet"
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/head/helmet/space/void/refurb/medical/alt/talon
	name = "talon medical voidsuit bubble helmet"
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/suit/space/void/refurb/medical/talon
	name = "talon medical voidsuit"

/obj/item/clothing/head/helmet/space/void/refurb/marine/talon
	name = "talon marine's voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum. The blue markings indicate this as the marine/guard variant. \"ITV TALON\" has been stamped onto the sides of the helmet."
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/suit/space/void/refurb/marine/talon
	name = "talon marine's voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer marines swear by these old things, even if new powered hardsuits have more features and better armor. The blue markings indicate this as the marine/guard variant, with \"ITV TALON\" stamped under the shield design."

/obj/item/clothing/head/helmet/space/void/refurb/officer/talon
	name = "talon officer's voidsuit helmet"
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/suit/space/void/refurb/officer/talon
	name = "talon officer's voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer spacers swear by these old things, even if new powered hardsuits have more features and better armor. This variant appears to be an officer's, and has the best protection of all the old models. \"ITV TALON\" is stamped across the left side of the breastplate in faded faux-gold."

/obj/item/clothing/head/helmet/space/void/refurb/pilot/talon
	name = "talon pilot voidsuit bubble helmet"
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/head/helmet/space/void/refurb/pilot/alt/talon
	name = "talon pilot voidsuit helmet"
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/suit/space/void/refurb/pilot/talon
	name = "talon pilot voidsuit"

/obj/item/clothing/head/helmet/space/void/refurb/mining/talon
	name = "talon miner voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum. \"ITV TALON\" has been stamped onto the sides of the helmet."
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/suit/space/void/refurb/mining/talon
	name = "talon miner voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer spacers swear by these old things, even if new powered hardsuits have more features and better armor. \"ITV TALON\" is stamped across the left side of the breastplate in faded faux-gold."

/obj/item/clothing/head/helmet/space/void/refurb/research/talon
	name = "talon scientific voidsuit helmet"
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/head/helmet/space/void/refurb/research/alt/talon
	name = "talon scientific voidsuit bubble helmet"
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/suit/space/void/refurb/research/talon
	name = "talon scientific voidsuit"

/obj/item/clothing/head/helmet/space/void/refurb/mercenary/talon
	name = "talon mercenary's voidsuit helmet"
	desc = "A refurbished early contact era voidsuit helmet of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. The visor has a bad habit of fogging up and collecting condensation, but it beats sucking hard vacuum. The red markings indicate this as the mercenary variant. \"ITV TALON\" is stamped across the back of the helmet."
	camera_networks = list(NETWORK_TALON_HELMETS)

/obj/item/clothing/suit/space/void/refurb/mercenary/talon
	name = "talon mercenary's voidsuit"
	desc = "A refurbished early contact era voidsuit of human design. These things aren't especially good against modern weapons but they're sturdy, incredibly easy to come by, and there are lots of spare parts for repairs. Many old-timer mercs swear by these old things, even if new powered hardsuits have more features and better armor. The red markings indicate this as the mercenary variant. \"ITV TALON\" has been stamped onto each pauldron and the right side of the breastplate."

// HEV Suits
/obj/item/clothing/suit/space/void/hev
	name = "hazardous environment suit"
	desc = "Has a strange smell to it, but you feel like it might be an old friend."
	icon_state = "hev_orange"

/obj/item/clothing/suit/space/void/hev/violet
	icon_state = "hev_violet"
	desc = "Has a strange smell to it, but you feel like it might be an old friend. This one has 'Dr. Coomer' engraved on the collar."

/obj/item/clothing/head/helmet/space/void/hev
	name = "hazardous environment helmet"
	desc = "Has a strange smell to it, but you feel like it might be an old friend."
	icon_state = "hev_orange"

/obj/item/clothing/head/helmet/space/void/hev/violet
	icon_state = "hev_violet"
	desc = "Has a strange smell to it, but you feel like it might be an old friend. This one has 'Dr. Coomer' engraved on the collar."

// Makeshift void suit
/obj/item/clothing/suit/space/void/makeshift
	name = "makeshift voidsuit"
	desc = "This is not something you should use if you have other options, but it's better than nothing!"
	icon_state = "makeshift_void"

	armor = list("melee" = 0, "bullet" = 0, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 100, "rad" = 0)

/obj/item/clothing/head/helmet/space/void/makeshift
	name = "makeshift voidsuit helmet"
	desc = "This is not something you should use if you have other options, but it's better than nothing!"
	icon_state = "makeshift_void"

	armor = list("melee" = 0, "bullet" = 0, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 100, "rad" = 0)

// 'Custodian' armor
/obj/item/clothing/suit/space/void/custodian
	name = "custodian suit"
	desc = "Vacuum-capable armor for a Custodian to do their duty."
	icon_state = "custodian"

	armor = list("melee" = 70, "bullet" = 70, "laser" = 70, "energy" = 50, "bomb" = 40, "bio" = 0, "rad" = 20)

/obj/item/clothing/head/helmet/space/void/custodian
	name = "custodian helmet"
	desc = "Vacuum-capable helmet for a Custodian to do their duty."
	icon_state = "custodian"

	armor = list("melee" = 70, "bullet" = 70, "laser" = 70, "energy" = 50, "bomb" = 40, "bio" = 0, "rad" = 20)

// 'Moebius' armor
/obj/item/clothing/suit/space/void/aether
	name = "\improper Aether voidsuit"
	desc = "This suit seems rather high-end for a standard voidsuit. The air in it has a hint of 'new car smell', courtesy of Aether Atmospherics."
	icon_state = "moebiussuit"

	armor = list("melee" = 30, "bullet" = 30, "laser" = 30, "energy" = 20, "bomb" = 20, "bio" = 100, "rad" = 20)

/obj/item/clothing/head/helmet/space/void/aether
	name = "\improper Aether voidsuit helmet"
	desc = "Aether Atmospherics thought that giving this helmet selectable colored lighting would improve market penetration. Very comfortable, regardless."
	icon_state = "moebiushelm_White"

	armor = list("melee" = 30, "bullet" = 30, "laser" = 30, "energy" = 20, "bomb" = 20, "bio" = 100, "rad" = 20)

/obj/item/clothing/head/helmet/space/void/aether/verb/select_color()
	set name = "Helmet Color"
	set desc = "Change the color of the helmet"
	set category = "Object"

	var/choice = tgui_input_list(usr, "Select a new color:", "[src] Color", list("White", "Blue", "Purple", "Yellow", "Red", "Green"))
	if(!choice)
		return
	icon_state = "moebiushelm_[choice]"
	update_clothing_icon()
	to_chat(usr, span_notice("[src] color changed to: [choice]"))

// Excelsior suit
/obj/item/clothing/suit/space/void/excelsior
	name = "\improper Excelsior voidsuit"
	desc = "A space suit from a particular spaceship: Excelsior."
	icon_state = "excelsior"

/obj/item/clothing/head/helmet/space/void/excelsior
	name = "\improper Excelsior voidsuit helmet"
	desc = "A space helmet from a particular spaceship: Excelsior."
	icon_state = "excelsior"

/obj/item/clothing/suit/space/void/altevian_heartbreaker
	name = "\improper heartbreaker voidsuit"
	desc = "The altevians' newest iteration of their armored suits. This one is tailored for zero-g environments, and while it can still be worn in an area with gravity, it'll put a strain on even the most athletic of individuals."

	icon = 'icons/inventory/suit/item_altevian.dmi'
	default_worn_icon = 'icons/inventory/suit/mob_altevian.dmi'
	icon_state = "rig-heartbreaker"

	armor = list(melee = 70, bullet = 70, laser = 70, energy = 30, bomb = 80, bio = 100, rad = 40)

	species_restricted = list(SPECIES_ALTEVIAN)
	no_cycle = TRUE
	slowdown = 2.5

/obj/item/clothing/head/helmet/space/void/altevian_heartbreaker
	name = "\improper heartbreaker helmet"
	desc = "The altevians' newest iteration of their armored suits. This one is tailored for zero-g environments, and while it can still be worn in an area with gravity, it'll put a strain on even the most athletic of individuals."

	icon = 'icons/inventory/head/item_altevian.dmi'
	default_worn_icon = 'icons/inventory/head/mob_altevian.dmi'
	icon_state = "rig0-heartbreaker"

	armor = list(melee = 70, bullet = 70, laser = 70, energy = 30, bomb = 80, bio = 100, rad = 40)

	species_restricted = list(SPECIES_ALTEVIAN)
	no_cycle = TRUE

/obj/item/clothing/suit/space/void/salvagecorp_shipbreaker
	name = "\improper CSC industrial voidsuit"
	desc = "A heavy-duty Kirillov-Y771 voidsuit intended for use in hazardous shipbreaking, salvage, and industrial operations, manufactured (or more likely refurbished) by the Coyote Salvage Corporation. It's slow and awkward if used outside of microgravity, but it offers good protection for what is technically a civilian-legal voidsuit."
	icon_state = "breaker_suit"

	armor = list("melee" = 50, "bullet" = 15, "laser" = 15, "energy" = 25, "bomb" = 45, "bio" = 100, "rad" = 80)
	slowdown = 1.5
	breach_threshold = 14
	allowed = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_ENGINEERING)

/obj/item/clothing/head/helmet/space/void/salvagecorp_shipbreaker
	name = "\improper CSC industrial voidsuit helmet"
	desc = "A dome/bubble style helmet for use with the Kirillov-Y771 voidsuit. It offers surprisingly good protection and visibility, though wearers are still advised to avoid face-on collisions. Sadly, this one doesn't seem to have the (in)famous 0PTIK3WL cross-spectrum imaging visor installed..."
	icon_state = "breaker_helmet"

	armor = list("melee" = 50, "bullet" = 15, "laser" = 15, "energy" = 25, "bomb" = 45, "bio" = 100, "rad" = 80)
