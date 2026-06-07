/********************
* Devices and Tools *
********************/
/datum/uplink_item/item/tools
	category = /datum/uplink_category/tools

/datum/uplink_item/item/tools/binoculars
	name = "Binoculars"
	item_cost = 3
	path = /obj/item/binoculars

/datum/uplink_item/item/tools/toolbox // Leaving the basic as an option since powertools are loud.
	name = "Fully Loaded Toolbox"
	item_cost = 3
	path = /obj/item/storage/toolbox/syndicate

/datum/uplink_item/item/tools/powertoolbox
	name = "Fully Loaded Powertool Box"
	item_cost = 5
	path = /obj/item/storage/toolbox/syndicate/powertools

/datum/uplink_item/item/tools/clerical
	name = "Morphic Clerical Kit"
	item_cost = 5
	path = /obj/item/storage/box/syndie_kit/clerical

/datum/uplink_item/item/tools/encryptionkey_radio
	name = "Encrypted Radio Channel Key"
	item_cost = 10
	path = /obj/item/encryptionkey/syndicate

/datum/uplink_item/item/tools/money
	name = "Operations Funding"
	item_cost = 10
	path = /obj/item/storage/secure/briefcase/money
	desc = "A briefcase with 10,000 untraceable thalers for funding your sneaky activities."

/datum/uplink_item/item/tools/plastique
	name = "C-4 (Destroys walls)"
	item_cost = 10
	path = /obj/item/plastique

/datum/uplink_item/item/tools/duffle
	name = "Black Duffle Bag"
	item_cost = 5
	path = /obj/item/storage/backpack/dufflebag/syndie

/datum/uplink_item/item/tools/duffle/med
	name = "Black Medical Duffle Bag"
	path = /obj/item/storage/backpack/dufflebag/syndie/med

/datum/uplink_item/item/tools/duffle/ammo
	name = "Black Ammunition Duffle Bag"
	path = /obj/item/storage/backpack/dufflebag/syndie/ammo

/datum/uplink_item/item/tools/shield_diffuser
	name = "Handheld Shield Diffuser"
	desc = "A small device used to disrupt energy barriers, and allow passage through them."
	item_cost = 16
	path = /obj/item/shield_diffuser

/datum/uplink_item/item/tools/space_suit
	name = "Space Suit"
	item_cost = 10
	path = /obj/item/storage/box/syndie_kit/space

/datum/uplink_item/item/tools/encryptionkey_binary
	name = "Binary Translator Key"
	item_cost = 15
	path = /obj/item/encryptionkey/binary

/datum/uplink_item/item/tools/hacking_tool
	name = "Door Hacking Tool"
	item_cost = 15
	path = /obj/item/multitool/hacktool
	desc = "Appears and functions as a standard multitool until the mode is toggled by applying a screwdriver appropriately. \
			When in hacking mode this device will grant full access to any standard airlock within 20 to 40 seconds. \
			This device will also be able to immediately access the last 6 to 8 hacked airlocks."

/datum/uplink_item/item/tools/ai_detector
	name = "Anti-Surveillance Tool"
	item_cost = 15
	path = /obj/item/multitool/ai_detector
	desc = "This functions like a normal multitool, but includes an integrated camera network sensor that will warn the holder if they are being \
	watched, by changing color and beeping.  It is able to detect both AI visual surveillance and security camera utilization from terminals, and \
	will give different warnings by beeping and changing colors based on what it detects.  Only the holder can hear the warnings."

/datum/uplink_item/item/tools/radio_jammer
	name = "Subspace Jammer"
	item_cost = 20
	path = /obj/item/radio_jammer
	desc = "A device which is capable of disrupting subspace communications, preventing the use of headsets, PDAs, and communicators within \
	a radius of seven meters.  It runs off weapon cells, which can be replaced as needed.  One cell will last for approximately ten minutes."

/datum/uplink_item/item/tools/wall_elecrtifier
	name = "Wall Electrifier"
	item_cost = 5
	path = /obj/item/cell/spike
	desc = "A modified powercell which will electrify walls and reinforced floors in a 3x3 tile range around it. Always active."

/datum/uplink_item/item/tools/emag
	name = "Cryptographic Sequencer"
	item_cost = 20
	path = /obj/item/card/emag

/datum/uplink_item/item/tools/graviton
	name = "Graviton Goggles"
	desc = "An obvious, if useful pair of advanced imaging goggles that allow you to see objects and turfs through walls."
	item_cost = 15
	path = /obj/item/clothing/glasses/graviton

/datum/uplink_item/item/tools/thermal
	name = "Thermal Imaging Glasses"
	item_cost = 25
	path = /obj/item/clothing/glasses/thermal/syndi

/datum/uplink_item/item/tools/packagebomb
	name = "Package Bomb (Small)"
	item_cost = 30
	path = /obj/item/storage/box/syndie_kit/demolitions

/datum/uplink_item/item/tools/powersink
	name = "Powersink (DANGER!)"
	item_cost = 40
	path = /obj/item/powersink

/datum/uplink_item/item/tools/packagebomb/large
	name = "Package Bomb (Large)"
	item_cost = 60
	path = /obj/item/storage/box/syndie_kit/demolitions_heavy

/datum/uplink_item/item/tools/integratedcircuitprinter
	name = "Integrated Circuit Printer (Upgraded)"
	item_cost = 10
	path = /obj/item/integrated_circuit_printer/upgraded

/*
/datum/uplink_item/item/tools/packagebomb/huge
	name = "Package Bomb (Huge)
	item_cost = 100
	path = /obj/item/storage/box/syndie_kit/demolitions_super_heavy
*/

/datum/uplink_item/item/tools/ai_module
	name = "Hacked AI Upload Module"
	item_cost = 60
	path = /obj/item/aiModule/syndicate

/datum/uplink_item/item/tools/supply_beacon
	name = "Hacked Supply Beacon (DANGER!)"
	item_cost = 60
	path = /obj/item/supply_beacon

/datum/uplink_item/item/tools/teleporter
	name = "Teleporter Circuit Board"
	item_cost = DEFAULT_TELECRYSTAL_AMOUNT * 1.5
	path = /obj/item/circuitboard/teleporter
	blacklisted = 1


// === merged from tools_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/********************
* Devices and Tools *
********************/
/datum/uplink_item/item/tools/oxygen
	name = "Emergency Oxygen Tank"
	item_cost = 2
	path = /obj/item/tank/emergency/oxygen/double

/datum/uplink_item/item/tools/phoron
	name = "Emergency Phoron Tank"
	item_cost = 2
	path = /obj/item/tank/emergency/phoron/double

/datum/uplink_item/item/tools/suitcooler
	name = "Emergency Suit Cooler"
	item_cost = 2
	path = /obj/item/suit_cooling_unit/emergency

/datum/uplink_item/item/tools/beacon_op
	name = "Holomap Beacon-M"
	item_cost = 2
	path = /obj/item/holomap_beacon/operative
	antag_roles = list("mercenary")

/datum/uplink_item/item/tools/beacon_ert
	name = "Holomap Beacon-E"
	item_cost = 2
	path = /obj/item/holomap_beacon/ert
	antag_roles = list("ert")

/datum/uplink_item/item/tools/basiclaptop
	name = "Laptop (Basic)"
	item_cost = 5
	path = /obj/item/modular_computer/laptop/preset/custom_loadout/cheap

/datum/uplink_item/item/tools/survivalcapsule
	name = "Survival Capsule"
	item_cost = 5
	path = /obj/item/survivalcapsule

/datum/uplink_item/item/tools/popcabin
	name = "Cabin Capsule"
	item_cost = 5
	path = /obj/item/survivalcapsule/popcabin

/datum/uplink_item/item/tools/nanopaste
	name = "Nanopaste (Advanced)"
	item_cost = 10
	path = /obj/item/stack/nanopaste/advanced

/datum/uplink_item/item/tools/autolok
	name = "Autolok Voidsuit"
	item_cost = 10
	path = /obj/item/clothing/suit/space/void/autolok

/datum/uplink_item/item/tools/inflatable
	name = "Inflatables"
	item_cost = 10
	path = /obj/item/storage/briefcase/inflatable

/datum/uplink_item/item/tools/elitetablet
	name = "Tablet (Advanced)"
	item_cost = 15
	path = /obj/item/modular_computer/tablet/preset/custom_loadout/advanced

/datum/uplink_item/item/tools/metal
	name = "Metal (50 sheets)"
	item_cost = 15
	path = /obj/fiftyspawner/steel

/datum/uplink_item/item/tools/glass
	name = "Glass (50 sheets)"
	item_cost = 15
	path = /obj/fiftyspawner/glass

/datum/uplink_item/item/tools/smallpouch
	name = "Small Pouch"
	item_cost = 5
	path = /obj/item/storage/pouch/small

/datum/uplink_item/item/tools/normalpouch
	name = "Standard Pouch"
	item_cost = 10
	path = /obj/item/storage/pouch

/datum/uplink_item/item/tools/largepouch
	name = "Large Pouch"
	item_cost = 15
	path = /obj/item/storage/pouch/large

/datum/uplink_item/item/tools/elitelaptop
	name = "Laptop (Advanced)"
	item_cost = 20
	path = /obj/item/modular_computer/laptop/preset/custom_loadout/elite

/datum/uplink_item/item/tools/inducer
	name = "Inducer"
	item_cost = 20
	path = /obj/item/inducer/syndicate

/datum/uplink_item/item/tools/mappingunit_op
	name = "Mapping Unit-M"
	item_cost = 20
	path = /obj/item/mapping_unit/operative
	antag_roles = list("mercenary")

/datum/uplink_item/item/tools/mappingunit_ert
	name = "Mapping Unit-E"
	item_cost = 20
	path = /obj/item/mapping_unit/ert
	antag_roles = list("ert")

/datum/uplink_item/item/tools/luxurycapsule
	name = "Survival Capsule (Luxury)"
	item_cost = 40
	path = /obj/item/survivalcapsule/luxury

/datum/uplink_item/item/tools/translocator
	name = "Translocator"
	item_cost = 40
	path = /obj/item/perfect_tele

/datum/uplink_item/item/tools/uav
	name = "Recon Skimmer"
	item_cost = 40
	path = /obj/item/uav

/datum/uplink_item/item/tools/barcapsule
	name = "Survival Capsule (Bar)"
	item_cost = 80
	path = /obj/item/survivalcapsule/luxurybar

/datum/uplink_item/item/tools/capturecrystal
	name = "Capture Crystal"
	item_cost = 30
	path = /obj/item/capture_crystal/basic

/datum/uplink_item/item/tools/capturecrystal/great
	name = "Capture Crystal (Great)"
	item_cost = 40
	path = /obj/item/capture_crystal/great

/datum/uplink_item/item/tools/capturecrystal/ultra
	name = "Capture Crystal (Ultra)"
	item_cost = 50
	path = /obj/item/capture_crystal/ultra

/datum/uplink_item/item/tools/armoredgloves
	name = "Reinforced Insulated Gloves"
	item_cost = 5
	path = /obj/item/clothing/gloves/heavy_engineer
