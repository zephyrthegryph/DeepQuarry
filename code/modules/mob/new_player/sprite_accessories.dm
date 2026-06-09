/*

	Hello and welcome to sprite_accessories: For sprite accessories, such as hair,
	facial hair, and possibly tattoos and stuff somewhere along the line. This file is
	intended to be friendly for people with little to no actual coding experience.
	The process of adding in new hairstyles has been made pain-free and easy to do.
	Enjoy! - Doohl


	Notice: This all gets automatically compiled in a list in dna2.dm, so you do not
	have to define any UI values for sprite accessories manually for hair and facial
	hair. Just add in new hair types and the game will naturally adapt.

	!!WARNING!!: changing existing hair information can be VERY hazardous to savefiles,
	to the point where you may completely corrupt a server's savefiles. Please refrain
	from doing this unless you absolutely know what you are doing, and have defined a
	conversion in savefile.dm
*/

/**
 * Color channel names; this is used in things like character setup, editors, etc.
 *
 * * The length of this is also used to sanitize color channel list lengths. This should never be longer than the
 *   maximum number of color channels possible across all sprite accessories.
 */
GLOBAL_LIST_INIT(fancy_sprite_accessory_color_channel_names, list("Primary", "Secondary", "Tertiary", "Quaternary"))

/datum/sprite_accessory

	var/icon			// the icon file the accessory is located in
	var/icon_state		// the icon_state of the accessory
	var/preview_state	// a custom preview state for whatever reason

	var/name = DEVELOPER_WARNING_NAME // the preview name of the accessory

	/// Determines if the accessory will be skipped or included in random hair generations
	var/gender = NEUTER

	/// Restrict some styles to specific species. Default to all species to avoid runtimes in character creator.
	var/list/species_allowed = list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_UNATHI, SPECIES_TAJARAN, SPECIES_TESHARI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_FENNEC, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_XENOCHIMERA, SPECIES_XENOHYBRID, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_PROTEAN, SPECIES_ALRAUNE, SPECIES_WEREBEAST, SPECIES_SHADEKIN, SPECIES_SHADEKIN_CREW, SPECIES_ALTEVIAN, SPECIES_LLEILL, SPECIES_HANNER, SPECIES_ZADDAT, SPECIES_SPARKLE, SPECIES_PROMETHEAN, SPECIES_ZORREN_DARK)

	/// If the accessory can be selected normally. If FALSE, only staff can select it.
	var/can_be_selected = TRUE

	/// Whether or not the accessory can be affected by colouration
	var/do_colouration = 1

	var/color_blend_mode = ICON_MULTIPLY	// If checked.

	/// Ckey of person allowed to use this, if defined.
	var/list/ckeys_allowed = null

	/// Should this sprite block emissives?
	var/em_block = FALSE

	/// What body parts we hide when this accessory is worn. Only blocks the body part if the accompanying organ in body_parts is also enabled.
	var/list/hide_body_parts = list() //Uses organ tag defines. Bodyparts in this list do not have their icons rendered, allowing for more spriter freedom when doing taur/digitigrade stuff.

/**
 * Gets the number of color channels we have.
 */
/datum/sprite_accessory/proc/get_color_channel_count()
	return do_colouration ? 1 : 0


// === merged from sprite_accessories_chomp.dm during hard-fork de-suffix (manually verified: all-new types / new defines, no base re-open) ===
/datum/sprite_accessory/marking/vox/vox_alt_eyes
	icon = 'icons/mob/human_races/markings_vox.dmi'

/datum/sprite_accessory/marking/vox/vox_underbeak
	name = "Vox Underbeak"
	icon = 'icons/mob/human_races/markings_vox.dmi'
	icon_state = "vox_underbeak"
	body_parts = list(BP_HEAD)

//human hair override with shading
/datum/sprite_accessory/hair/longbraidalt
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/front_braid
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/vegeta
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/beehive
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/sideponytail6
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/protagonist
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/antenna
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/bigcurls
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/glammetal
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/feferi
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/mulder
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/kanaya
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/sharpponytail
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/midb
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/topknot
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/rockandroll
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/poofy2
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/business2
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/froofy_long
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/halfshavedlong
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/crono
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/mohawkunshaven
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/band
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/wisp
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/joestar
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/longbraid
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/vriska
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/zieglertail
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/dirk
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/elize
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/short2
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/bun3
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/cia
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/bieber
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/longundercut
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/gamzee
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/fabio
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/terezi
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/bedheadlongest
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/rosa
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/dandypomp
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/mahdrills
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/shyold
	name = "Shy old"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "hair_shy_old"
	flags = HAIR_TIEABLE

/datum/sprite_accessory/hair/country
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/shy
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/nepeta
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/belenko
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/judge
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/rose
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/short3
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/rowbraid
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/scully
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/mia
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/aradia
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/emoleft
	name = "Emo Left"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "hair_emoleft"
	flags = HAIR_TIEABLE

/datum/sprite_accessory/hair/equius
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/mialong
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/belenkotied
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/poofy
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/emoright
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/sideponytail5
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/roxy
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/manbun
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/doll
	name = "Doll"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "hair_doll"
	flags = HAIR_TIEABLE

/datum/sprite_accessory/hair/keanu
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/spikyponytail
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/glossy
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/bun2
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/ronin
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/bedheadlong
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/nitori
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/familyman
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/afropuffright
	icon_add = 'icons/mob/human_face.dmi'	// offset by 1 px on upstream file

//taj hair override with shading
/datum/sprite_accessory/hair/taj/sidepartedright
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/shoulderparted
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/shoulderpartedlong
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/fringeup
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/shaggy
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/cascadingalt
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/plait
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/shoulderlengthalt
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/rattail
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/_sidepony
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/bangs_alt
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/shoulderpartedsmall
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/bob
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/braid
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/spiky
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/long
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/shoulderlength
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/clean
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/mohawk
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/bun
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/bunlow
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/straight
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/greaser
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/bangs
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/tresses
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/short_fringe
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/mane
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/cascading
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/messy
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/bunsmall
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/chomp
	name = "Tajaran Ch. Ears"
	icon_add = 'icons/mob/human_face.dmi'
	icon_state = "ears_plain"

/datum/sprite_accessory/hair/taj/curlsalt
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/sidepartedleft
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/_wedge
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/gman
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/taj/bunlowsmall
	icon_add = 'icons/mob/human_face.dmi'

//tesahri hair override with shading
/datum/sprite_accessory/hair/teshari/backstrafe
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/tree
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/tallmohawk
	name = "Teshari Tall Mohawk"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "teshari_tallmohawk"

/datum/sprite_accessory/hair/teshari/aerodynamic
	name = "Teshari Aerodynamic"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "teshari_aerodynamic"

/datum/sprite_accessory/hair/teshari/pointy
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/crowned
	name = "Teshari Crowned"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "teshari_crowned"

/datum/sprite_accessory/hair/teshari/tight
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/bun
	name = "Teshari Bun"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "teshari_bun"

/datum/sprite_accessory/hair/teshari/droopy
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/burst
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/excited
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/shortburst
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/_longway
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/chomp
	name = "Teshari Ch. Default"
	icon_add = 'icons/mob/human_face.dmi'
	icon_state = "teshari_default"

/datum/sprite_accessory/hair/teshari/peel
	name = "Teshari Peel"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "teshari_peel"

/datum/sprite_accessory/hair/teshari/altdefault
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/sleek
	name = "Teshari Sleek"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "teshari_sleek"

/datum/sprite_accessory/hair/teshari/ponytail
	name = "Teshari Ponytail"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "teshari_ponytail"

/datum/sprite_accessory/hair/teshari/sweep
	name = "Teshari Sweep"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "teshari_sweep"

/datum/sprite_accessory/hair/teshari/spike
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/mohawk
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/spiky2
	name = "Teshari Alt. Spiky"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "teshari_spiky2"

/datum/sprite_accessory/hair/teshari/mane
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/fluffymohawk
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/twies
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/mushroom
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/upright
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/long
	icon_add = 'icons/mob/human_face.dmi'

/datum/sprite_accessory/hair/teshari/crest
	name = "Teshari Crest"
	icon= 'icons/mob/human_face.dmi'
	icon_state = "teshari_crest"

/datum/sprite_accessory/hair/teshari/soap
	name = "Teshari Soap"
	icon = 'icons/mob/human_face.dmi'
	icon_state = "teshari_soap"

//screll hair override
/datum/sprite_accessory/hair/skr/chomp
	name = "Tentacles Ch., Average"
	icon_state = "skrell_short"
	name = "Tentacles, Average"
	icon_state = "skrell_short"
	icon = 'icons/mob/hair_skrell.dmi'
	icon_add = 'icons/mob/hair_skrell_add.dmi'

/datum/sprite_accessory/hair/skr/pullback
	icon = 'icons/mob/hair_skrell.dmi'
	icon_add = 'icons/mob/hair_skrell_add.dmi'
	name = "Tentacles, Average, Pullback"
	icon_state = "skrell_short_pullback"

/datum/sprite_accessory/hair/skr/very_short
	icon = 'icons/mob/hair_skrell.dmi'
	icon_add = 'icons/mob/hair_skrell_add.dmi'
	name = "Tentacles, Short"
	icon_state = "skrell_very_short"

/datum/sprite_accessory/hair/skr/long
	icon = 'icons/mob/hair_skrell.dmi'
	icon_add = 'icons/mob/hair_skrell_add.dmi'
	name = "Tentacles, Long"
	icon_state = "skrell_long"

/datum/sprite_accessory/hair/skr/long/pullback
	name = "Tentacles, Long, Pullback"
	icon_state = "skrell_long_pullback"

/datum/sprite_accessory/hair/skr/long/scarf
	name = "Tentacles, Long, Scarf"
	icon_state = "skrell_long_scarf"

/datum/sprite_accessory/hair/skr/long/wavy
	name = "Tentacles, Long, Wavy"
	icon_state = "skrell_long_wavy"

/datum/sprite_accessory/hair/skr/very_long
	icon = 'icons/mob/hair_skrell.dmi'
	icon_add = 'icons/mob/hair_skrell_add.dmi'
	name = "Tentacles, Very Long"
	icon_state = "skrell_very_long"

/datum/sprite_accessory/hair/skr/very_long/pullback
	name = "Tentacles, Very Long, Pullback"
	icon_state = "skrell_very_long_pullback"

/datum/sprite_accessory/hair/skr/very_long/scarf
	name = "Tentacles, Very Long, Scarf"
	icon_state = "skrell_very_long_scarf"

/datum/sprite_accessory/hair/skr/very_long/wavy
	name = "Tentacles, Very Long, Wavy"
	icon_state = "skrell_very_long_wavy"

/datum/sprite_accessory/hair/skr/split
	icon = 'icons/mob/hair_skrell.dmi'
	icon_add = 'icons/mob/hair_skrell_add.dmi'
	name = "Tentacles, Split"
	icon_state = "skrell_split"

//una hair override with shading
/datum/sprite_accessory/hair/una/Chomp
	name = "Long Unathi Spines Ch."
	icon_state = "soghun_longspines"
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'

/datum/sprite_accessory/hair/una/finhawk
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Unathi Finhawk"
	icon_state = "fin_hawk"

/datum/sprite_accessory/hair/una/downcurve_horns
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Downward-Curved Unathi Horns"
	icon_state = "curved_down"

/datum/sprite_accessory/hair/una/upcurve_horns
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Upward-Curved Unathi Horns"
	icon_state = "curved_up"

/datum/sprite_accessory/hair/una/samurai_horns
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Unathi Samurai Horns"
	icon_state = "samurai"

/datum/sprite_accessory/hair/una/big_frills
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Big Unathi Frills"
	icon_state = "big_frills"

/datum/sprite_accessory/hair/una/head_spikes
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Unathi Head Spikes"
	icon_state = "head_spikes"

/datum/sprite_accessory/hair/una/overgrown_spikes
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Overgrown Unathi Head Spikes"
	icon_state = "overgrown_head_spikes"

/datum/sprite_accessory/hair/una/cobrahood
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Unathi Cobra Hood"
	icon_state = "unathi_cobrahood"

/datum/sprite_accessory/hair/una/demon_horns
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Unathi Demon Horns"
	icon_state = "unathi_horns_demon"

/datum/sprite_accessory/hair/una/large_ram_horns
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Large Unathi Ram Horns"
	icon_state = "unathi_horns_ram_big"

/datum/sprite_accessory/hair/una/aqua_frills
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Unathi Aqua Frills"
	icon_state = "unathi_frills_aqua"

/datum/sprite_accessory/hair/una/curled_horns
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Curled Unathi Horns"
	icon_state = "unathi_horns_curled"

/datum/sprite_accessory/hair/una/thick_ram_horns
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Thick Unathi Ram Horns"
	icon_state = "unathi_horns_ram_thick"

/datum/sprite_accessory/hair/una/swept_horns
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Swept Unathi Horns"
	icon_state = "unathi_horns_swept"

/datum/sprite_accessory/hair/una/short_spined_frills
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Short Spined Unathi Frills"
	icon_state = "unathi_spined_short_frills"

/datum/sprite_accessory/hair/una/long_spined_frills
	icon = 'icons/mob/hair_unathi.dmi'
	icon_add = 'icons/mob/hair_unathi_add.dmi'
	name = "Long Spined Unathi Frills"
	icon_state = "unathi_spined_long_frills"

/datum/sprite_accessory/hair/braid
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/awoohair
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/twindrills
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/una_hood
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/una_doublehorns
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/sergal_plain
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/sergal_medicore
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/sergal_tapered
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/sergal_fairytail
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_kajam
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_keid
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_adhara
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_kleeia
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_mizar
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_apollo
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_belle
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_bun
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_jagged
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_curl
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_hawk
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_anita
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_short
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/vulp_hair_spike
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/xeno_head_drone_color
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/xeno_head_sentinel_color
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/xeno_head_queen_color
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/xeno_head_hunter_color
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/xeno_head_praetorian_color
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/shadekin_hair_short
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/shadekin_hair_poofy
	icon_add = 'icons/mob/human_face_alt_add.dmi'

/datum/sprite_accessory/hair/shadekin_hair_long
	icon_add = 'icons/mob/human_face_alt_add.dmi'


// === merged from sprite_accessories_extra_ch.dm during hard-fork de-suffix (manually verified) ===
/datum/sprite_accessory/marking/ch
	icon = 'icons/mob/human_races/markings_ch.dmi'

/datum/sprite_accessory/marking/ch/orca_head
	name = "Orca Head"
	icon_state = "orca"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)
	species_allowed = list(SPECIES_AKULA)

/datum/sprite_accessory/marking/ch/orca_body
	name = "Orca Body (female)"
	icon_state = "orca"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO,BP_GROIN)
	species_allowed = list(SPECIES_AKULA)

/datum/sprite_accessory/marking/ch/orca_legs
	name = "Orca Legs"
	icon_state = "orca"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_LEG,BP_R_LEG)
	species_allowed = list(SPECIES_AKULA)

/datum/sprite_accessory/marking/ch/orca_arms
	name = "Orca Arms"
	icon_state = "orca"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_ARM,BP_R_ARM)
	species_allowed = list(SPECIES_AKULA)
/* //I can't make out what this icon_state was ever supposed to be. There is no 'zan' 'mon' or anything like that in the ch.dmi file...
/datum/sprite_accessory/marking/ch/zangoose_belly
	name = "Mongoose Cat Belly Marking"
	icon_state = "test"
	body_parts = list(BP_TORSO)
	species_allowed = list(SPECIES_HUMAN, SPECIES_UNATHI, SPECIES_TAJARAN, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_XENOCHIMERA, SPECIES_XENOHYBRID, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_PROTEAN, SPECIES_ALRAUNE) //This lets all races use the default hairstyles.
*/
/datum/sprite_accessory/marking/ch/athena_lights
	name = "Hephaestus - Athena lights"
	icon_state = "athena"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_TORSO,BP_HEAD)

/datum/sprite_accessory/marking/ch/athena_panels
	name = "Hephaestus - Athena FBP Panels"
	icon_state = "athena_p"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_FOOT,BP_R_FOOT,BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_L_HAND,BP_R_HAND,BP_GROIN,BP_TORSO,BP_HEAD)

/datum/sprite_accessory/marking/ch/athena_panels_body
	name = "Hephaestus - Athena FBP Panels (body)"
	icon_state = "athena_p"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_FOOT,BP_R_FOOT,BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_L_HAND,BP_R_HAND,BP_GROIN,BP_TORSO)

/datum/sprite_accessory/marking/ch/athena_panels_head
	name = "Hephaestus - Athena FBP Panels (head)"
	icon_state = "athena_p"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/rook_lights
	name = "Bishop - Rook lights"
	icon_state = "rook-l"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_FOOT,BP_R_FOOT,BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_L_HAND,BP_R_HAND,BP_GROIN,BP_TORSO,BP_HEAD)

/datum/sprite_accessory/marking/ch/rook_lights_body
	name = "Bishop - Rook lights (body)"
	icon_state = "rook-l"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_FOOT,BP_R_FOOT,BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_L_HAND,BP_R_HAND,BP_GROIN,BP_TORSO)

/datum/sprite_accessory/marking/ch/rook_lights_head
	name = "Bishop - Rook lights (head)"
	icon_state = "rook-l"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/grointojaw
	name = "Groin to mouth marking"
	icon_state = "grointojaw"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_HEAD, BP_GROIN)

/datum/sprite_accessory/marking/ch/vale_eyes
	name = "VALE Eyes"
	icon_state = "vale_eyes"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/vale_belly
	name = "VALE Belly"
	icon_state = "vale_belly"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_GROIN)

/datum/sprite_accessory/marking/ch/vale_back
	name = "VALE Back"
	icon_state = "vale_back"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO)

/datum/sprite_accessory/marking/ch/vulp_skull
	name = "Vulp Skullface"
	icon_state = "vulpskull"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/voxbeak2
	name = "Vox Beak (Normal)"
	icon_state = "vox_beak"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/voxtalons
	name = "Vox Talons"
	icon_state = "vox_talons"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_ARM,BP_L_ARM,BP_R_HAND,BP_L_HAND,BP_R_LEG,BP_L_LEG,BP_R_FOOT,BP_L_FOOT)

/datum/sprite_accessory/marking/ch/sylveonheadribbons1
	name = "Sylveon Head Ribbons"
	icon_state = "sylveon-bowribbons1"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/protogen_snout
	name = "Protogen Snout"
	icon_state = "protogen_snout"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/hshark_snout
	name = "HShark Snout"
	icon_state = "hshark_snout"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/hshark_head
	name = "HShark Head"
	icon_state = "hshark"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/ram_horns
	name = "Ram Horns"
	icon_state = "ram_horns"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/neckfluff
	name = "Neck Fluff"
	icon_state = "neckfluff"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/husky_chest
	name = "Husky Chest"
	icon_state = "husky"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_GROIN)

/datum/sprite_accessory/marking/ch/fox_head
	name = "Fox Head"
	icon_state = "fox"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/fox_chest
	name = "Fox Chest"
	icon_state = "fox"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_GROIN)

/datum/sprite_accessory/marking/ch/fox_hsocks
	name = "Fox Hand Socks"
	icon_state = "fox"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_ARM, BP_R_HAND, BP_L_ARM, BP_L_HAND)

/datum/sprite_accessory/marking/ch/fox_lsocks
	name = "Fox Leg Socks"
	icon_state = "fox"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_LEG,BP_R_FOOT,BP_L_LEG,BP_L_FOOT)
	digitigrade_acceptance = MARKING_ALL_LEGS

/datum/sprite_accessory/marking/ch/tiger_head
	name = "Tiger Head"
	icon_state = "tiger"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/tiger_chest
	name = "Tiger Chest"
	icon_state = "tiger"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_GROIN)

/datum/sprite_accessory/marking/ch/tiger_arms
	name = "Tiger Arms"
	icon_state = "tiger"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_ARM, BP_R_HAND, BP_L_ARM, BP_L_HAND)

/datum/sprite_accessory/marking/ch/tiger_legs
	name = "Tiger Legs"
	icon_state = "tiger"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_LEG,BP_R_FOOT,BP_L_LEG,BP_L_FOOT)
	digitigrade_acceptance = MARKING_ALL_LEGS

/datum/sprite_accessory/marking/ch/gradient_arms
	name = "Gradient Arms"
	icon_state = "gradient"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_ARM, BP_R_HAND, BP_L_ARM, BP_L_HAND)

/datum/sprite_accessory/marking/ch/gradient_legs
	name = "Gradient Legs"
	icon_state = "gradient"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_LEG,BP_R_FOOT,BP_L_LEG,BP_L_FOOT)
	digitigrade_acceptance = MARKING_ALL_LEGS

/datum/sprite_accessory/marking/ch/hawk_talons
	name = "Hawk Talons (Legs)"
	icon_state = "hawktalon"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_LEG,BP_R_FOOT,BP_L_LEG,BP_L_FOOT)
	digitigrade_acceptance = MARKING_ALL_LEGS

/datum/sprite_accessory/marking/ch/deer_hooves
	name = "Deer Hooves"
	icon_state = "deerhoof"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_FOOT, BP_L_FOOT)
	digitigrade_acceptance = MARKING_ALL_LEGS

/datum/sprite_accessory/marking/ch/frills_simple
	name = "Frills (Simple)"
	icon_state = "frills_simple"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/frills_short
	name = "Frills (Short)"
	icon_state = "frills_short"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/frills_aquatic
	name = "Frills (Aquatic)"
	icon_state = "frills_aqua"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/guilmonhead
	name = "Guilmon Head"
	icon_state = "guilmon_head"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/guilmonchest
	name = "Guilmon Chest"
	icon_state = "guilmon_chest"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO)

/datum/sprite_accessory/marking/ch/guilmonchestmarking
	name = "Guilmon Chest Markings"
	icon_state = "guilmon_marking"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO)

/datum/sprite_accessory/marking/ch/guilmonarms
	name = "Guilmon Arms"
	icon_state = "guilmon"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_ARM,BP_L_ARM,BP_R_HAND,BP_L_HAND)

/datum/sprite_accessory/marking/ch/guilmonlegs
	name = "Guilmon Legs"
	icon_state = "guilmon"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_R_LEG,BP_R_FOOT,BP_L_LEG,BP_L_FOOT)
	digitigrade_acceptance = MARKING_ALL_LEGS

/datum/sprite_accessory/tail/special/orca_tail
	name = "Orca Tail"
	desc = ""
	icon_state = "sharktail_s"
	extra_overlay = "orca_tail"
	do_colouration = 1
	color_blend_mode = ICON_MULTIPLY
	species_allowed = list(SPECIES_AKULA)

/datum/sprite_accessory/hair/ch
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
/datum/sprite_accessory/hair/ch/cotton
	name = "Cotton"
	icon_state = "hair_cotton"


/datum/sprite_accessory/hair/ch/unshavenreversemohawk
	name = "Mohawk Reverse Unshaven"
	icon_state = "hair_unshaven_reversemohawk"

// Extra colorable options for Vox
/datum/sprite_accessory/hair/vox_afro_color
	name = "Vox Afro, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_afro"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_crestedquills_color
	name = "Vox Crested Quills, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_crestedquills"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_empquills_color
	name = "Vox Emperor Quills, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_emperorquills"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_hairhorns_color
	name = "Vox Hair Horns, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_horns"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_keelquills_color
	name = "Vox Keel Quills, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_keelquills"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_keetquills_color
	name = "Vox Keet Quills, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_keetquills"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_kingly_color
	name = "Vox Kingly Quills, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_kingly"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_mohawk_color
	name = "Vox Mohawk, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_mohawk"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_nights_color
	name = "Vox Night Quills, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_nights"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_razorclipped_color
	name = "Vox Razor Clipped, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_razorclipped"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_razor_color
	name = "Vox Razor, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_razor"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_shortquills_color
	name = "Vox Short Quills, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_shortquills"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_tielquills_color
	name = "Vox Tiel Quills, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_tielquills"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/hair/vox_yasuquills_color
	name = "Vox Yasu Quills, Colorable"
	icon = 'icons/mob/human_face_ch.dmi'
	icon_add = 'icons/mob/human_face_ch_add.dmi'
	icon_state = "hair_vox_yasu"
	species_allowed = list(SPECIES_VOX)

/datum/sprite_accessory/marking/ch/teshari_large_eyes_het
	name = "Teshari large eyes (Heterochromia)"
	icon_state = "teshlarge_eyes_het"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

// Nightstalker Body Markings
/datum/sprite_accessory/marking/ch/desert_nightstalker
	name = "Nightstalker Scales (Desert Coloration)"
	icon_state = "nightstalker_desert"
	body_parts = list(BP_R_ARM,BP_L_ARM,BP_R_HAND,BP_L_HAND,BP_R_LEG,BP_L_LEG,BP_R_FOOT,BP_L_FOOT,BP_TORSO,BP_GROIN) // Fullbody markings, save head
	do_colouration = 0 // Don't color, these are pre-colored markings

/datum/sprite_accessory/marking/ch/desert_nightstalker_head
	name = "Nightstalker Head (Desert Coloration)"
	icon_state = "nightstalker_desert"
	body_parts = list(BP_HEAD)
	do_colouration = 0 // Don't color, these are pre-colored markings

/datum/sprite_accessory/marking/ch/nightstalker_head_center
	name = "Nightstalker Head, Tricolor (Center)"
	icon_state = "nightstalker_1"
	body_parts = list(BP_HEAD)
	color_blend_mode = ICON_MULTIPLY

/datum/sprite_accessory/marking/ch/nightstalker_head_left
	name = "Nightstalker Head, Tricolor (Left)"
	icon_state = "nightstalker_2"
	body_parts = list(BP_HEAD)
	color_blend_mode = ICON_MULTIPLY

/datum/sprite_accessory/marking/ch/nightstalker_head_right
	name = "Nightstalker Head, Tricolor (Right)"
	icon_state = "nightstalker_3"
	body_parts = list(BP_HEAD)
	color_blend_mode = ICON_MULTIPLY

/datum/sprite_accessory/marking/ch/diamondback_nightstalker_outer
	name = "Nightstalker Scales, Outer"
	icon_state = "nightstalker_1"
	body_parts = list(BP_R_ARM,BP_L_ARM,BP_R_HAND,BP_L_HAND,BP_R_LEG,BP_L_LEG,BP_R_FOOT,BP_L_FOOT,BP_TORSO,BP_GROIN) // Fullbody markings, save head
	color_blend_mode = ICON_MULTIPLY

/datum/sprite_accessory/marking/ch/diamondback_nightstalker_inner
	name = "Nightstalker Scales, Inner"
	icon_state = "nightstalker_2"
	body_parts = list(BP_R_ARM,BP_L_ARM,BP_R_LEG,BP_L_LEG,BP_TORSO,BP_GROIN) // Fullbody markings, save head
	color_blend_mode = ICON_MULTIPLY

/datum/sprite_accessory/marking/ch/outer_spots
	name = "Spots, Outer"
	icon_state = "spots_extremities"
	body_parts = list(BP_R_ARM,BP_L_ARM,BP_R_LEG,BP_L_LEG,BP_R_FOOT,BP_L_FOOT)
	color_blend_mode = ICON_MULTIPLY

//Hellscout panel markings
/datum/sprite_accessory/marking/ch/hellscout_panels_body
	name = "Erebus - Hellscout FBP Panels (upper body)"
	icon_state = "hellscout_p"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_ARM,BP_R_ARM,BP_L_HAND,BP_R_HAND,BP_TORSO)

/datum/sprite_accessory/marking/digi/hellscout_panels_legs
	name = "Erebus - Hellscout FBP Panels (legs)"
	icon_state = "hellscout_p"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_FOOT,BP_R_FOOT,BP_L_LEG,BP_R_LEG)

/datum/sprite_accessory/marking/ch/hellscout_panels_head
	name = "Erebus - Hellscout FBP Panels (head)"
	icon_state = "hellscout_p"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

//Hellscout abdomen markings
/datum/sprite_accessory/marking/digi/hellscout_abdomen
	name = "Erebus - Hellscout FBP Abdomen (Digitigrade)"
	icon_state = "hellscout_r"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_LEG,BP_R_LEG,BP_GROIN,BP_TORSO)

/datum/sprite_accessory/marking/ch/hellscout_abdomen_p
	name = "Erebus - Hellscout FBP Abdomen (Plantigrade)"
	icon_state = "hellscout_r"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_GROIN,BP_TORSO)

/datum/sprite_accessory/marking/ch/spectre_panels
	name = "RACS Spectre FBP Panels"
	icon_state = "spectre"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_FOOT,BP_R_FOOT,BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_L_HAND,BP_R_HAND,BP_GROIN,BP_TORSO,BP_HEAD)

/datum/sprite_accessory/marking/ch/spectre_panels_body
	name = "RACS Spectre FBP Panels (body)"
	icon_state = "spectre"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_L_FOOT,BP_R_FOOT,BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_L_HAND,BP_R_HAND,BP_GROIN,BP_TORSO)

/datum/sprite_accessory/marking/ch/spectre_panels_head
	name = "RACS Spectre FBP Panels (head)"
	icon_state = "spectre"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/spectre_eyes
	name = "RACS Spectre FBP Eyes"
	icon_state = "spectre_eyes"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch/organs_gi
	name = "Internal Organs - Digestive"
	icon_state = "organs_gastro"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO,BP_GROIN)

/datum/sprite_accessory/marking/ch/organs_cv
	name = "Internal Organs - Heart,Lungs"
	icon_state = "organs_cardio" //Look I know cardio doesn't include the lungs but I don't care that's what I'm calling it
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO)

/datum/sprite_accessory/marking/ch/organs_ribs
	name = "Internal Organs - Ribcage"
	icon_state = "organs_ribs"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO)

/datum/sprite_accessory/marking/ch/chestfluff_big
	name = "Chest Fluff, Big"
	icon_state = "chestfluff_big"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO)

/datum/sprite_accessory/marking/ch/softbelly
	name = "Belly Fur, Soft"
	icon_state = "softbelly"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_GROIN)

/datum/sprite_accessory/marking/ch/softbelly_navel
	name = "Belly Fur, Soft With Navel"
	icon_state = "softbelly_navel"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_GROIN)

/datum/sprite_accessory/marking/ch/softbelly_fem
	name = "Belly Fur, Soft (Female)"
	icon_state = "softbelly_fem"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_GROIN)

/datum/sprite_accessory/marking/ch/softbelly_fem_navel
	name = "Belly Fur, Soft With Navel (Female)"
	icon_state = "softbelly_fem_navel"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_GROIN)

/datum/sprite_accessory/marking/ch/chitinbelly
	name = "Chitinous Scutes"
	icon_state = "chitin_belly"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_GROIN)

/datum/sprite_accessory/marking/ch/chitinbelly_fem
	name = "Chitinous Scutes (Female)"
	icon_state = "chitinbelly_fem"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_TORSO, BP_GROIN)

/datum/sprite_accessory/marking/ch/extraeyes
	name = "Extra Eyes"
	icon_state = "extra_eyes"
	color_blend_mode = ICON_MULTIPLY
	body_parts = list(BP_HEAD)

/datum/sprite_accessory/marking/ch_gloss
	name = "Full body gloss (additive)"
	icon = 'icons/mob/human_races/markings.dmi'
	color_blend_mode = ICON_ADD
	icon_state = "gloss"
	body_parts = list(BP_L_FOOT,BP_R_FOOT,BP_L_LEG,BP_R_LEG,BP_L_ARM,BP_R_ARM,BP_L_HAND,BP_R_HAND,BP_GROIN,BP_TORSO,BP_HEAD)

/datum/sprite_accessory/marking/digi/digigloss
	name = "Body gloss (digitigrade legs)"
	icon = 'icons/mob/human_races/markings_digi.dmi'
	color_blend_mode = ICON_MULTIPLY
	icon_state = "gloss"
	body_parts = list(BP_L_LEG,BP_R_LEG,BP_L_FOOT,BP_R_FOOT)

/datum/sprite_accessory/marking/digi/digiglossadd
	name = "Body gloss (digitigrade legs, additive)"
	icon = 'icons/mob/human_races/markings_digi.dmi'
	color_blend_mode = ICON_ADD
	icon_state = "gloss"
	body_parts = list(BP_L_LEG,BP_R_LEG,BP_L_FOOT,BP_R_FOOT)
