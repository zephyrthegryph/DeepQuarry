// Z_LEVEL are just hard coded z-levels
// Z_NAME are late loaded z-level maps that can be looked up in GLOB.map_templates_loaded
// GLOB.map_templates_loaded is populated as /datum/map_template/proc/on_map_preload(z) is called
// Some Z_NAME ultimately will be indexed under an alias however e.g. Z_NAME_ALIAS_GATEWAY

// Z_NAME/Z_LEVEL constants for Tether, Stellar Delight, and Groundbase maps
// were removed (those maps are deleted from the build).

#define Z_NAME_SPACE_ROCKS					"V3b Asteroid Field"
#define Z_NAME_OVERMAP						"Overmap"

// Common
#define Z_NAME_OFFMAP1						"Offmap Ship - Talon V2"
#define Z_NAME_AEROSTAT						"Remmi Aerostat - Z1 Aerostat"
#define Z_NAME_AEROSTAT_SURFACE				"Remmi Aerostat - Z2 Surface"
#define Z_NAME_DEBRISFIELD					"Debris Field - Z1 Space"
#define Z_NAME_FUELDEPOT					"Fuel Depot - Z1 Space"
#define Z_NAME_BEACH						"Desert Planet - Z1 Beach"
#define Z_NAME_BEACH_CAVE					"Desert Planet - Z2 Cave"

#define Z_NAME_ALIAS_GATEWAY				"GATEWAY"
#define Z_NAME_ALIAS_OM_ADVENTURE			"OVERMAP ADVENTURE"
#define Z_NAME_ALIAS_REDGATE				"REDGATE"
#define Z_NAME_ALIAS_CENTCOM				"CENTRAL COMMAND"
#define Z_NAME_ALIAS_MISC					"MISC"

// Gateways (Aliased to Z_NAME_ALIAS_GATEWAY)
#define Z_NAME_GATEWAY_CARP_FARM			"Gateway - Carp Farm"
#define Z_NAME_GATEWAY_SNOW_FIELD			"Gateway - Snow Field"
#define Z_NAME_GATEWAY_LISTENING_POST		"Gateway - Listening Post"
#define Z_NAME_GATEWAY_HONLETH_A			"Gateway - Honleth Highlands A"
#define Z_NAME_GATEWAY_HONLETH_B			"Gateway - Honleth Highlands B"
#define Z_NAME_GATEWAY_ARYNTHI_CAVE_A		"Gateway - Arynthi Lake Underground A"
#define Z_NAME_GATEWAY_ARYNTHI_A			"Gateway - Arynthi Lake A"
#define Z_NAME_GATEWAY_ARYNTHI_CAVE_B		"Gateway - Arynthi Lake Underground B"
#define Z_NAME_GATEWAY_ARYNTHI_B			"Gateway - Arynthi Lake B"
#define Z_NAME_GATEWAY_WILD_WEST			"Gateway - Wild West"

// Overmap Adventures (Aliased to Z_NAME_ALIAS_OM_ADVENTURE)
#define Z_NAME_OM_GRASS_CAVE				"Grass Cave"

// Redgates (Aliased to Z_NAME_ALIAS_REDGATE)
#define Z_NAME_REDGATE_TEPPI_RANCH			"Redgate - Teppi Ranch"
#define Z_NAME_REDGATE_INNLAND				"Redgate - Innland"
#define Z_NAME_REDGATE_ABANDONED_ISLAND		"Redgate - Abandoned Island" // Commented out currently
#define Z_NAME_REDGATE_DARK_ADVENTURE		"Redgate - Dark Adventure"
#define Z_NAME_REDGATE_EGGNOG_CAVE			"Redgate - Eggnog Town Underground"
#define Z_NAME_REDGATE_EGGNOG_TOWN			"Redgate - Eggnog Town"
#define Z_NAME_REDGATE_STAR_DOG				"Redgate - Star Dog"
#define Z_NAME_REDGATE_HOTSPRINGS			"Redgate - Hotsprings"
#define Z_NAME_REDGATE_RAIN_CITY			"Redgate - Rain City"
#define Z_NAME_REDGATE_ISLANDS_UNDERWATER	"Redgate - Islands Underwater"
#define Z_NAME_REDGATE_ISLANDS				"Redgate - Islands"
#define Z_NAME_REDGATE_MOVING_TRAIN			"Redgate - Moving Train"
#define Z_NAME_REDGATE_MOVING_TRAIN_UPPER	"Redgate - Moving Train Upper Level"
#define Z_NAME_REDGATE_FANTASY_DUNGEON		"Redgate - Fantasy Dungeon"
#define Z_NAME_REDGATE_FANTASY_TOWN			"Redgate - Fantasy Town"
#define Z_NAME_REDGATE_LASERDOME			"Redgate - Laserdome"
#define Z_NAME_REDGATE_CASCADING_FALLS		"Redgate - Cascading Falls"
#define Z_NAME_REDGATE_JUNGLE_CAVE			"Redgate - Jungle Underground"
#define Z_NAME_REDGATE_JUNGLE				"Redgate - Jungle"
#define Z_NAME_REDGATE_FACILITY				"Redgate - Facility"
#define Z_NAME_REDGATE_CASINO_CANAL			"Redgate - Casino Canal"
#define Z_NAME_REDGATE_CASINO_CANAL_LOWER	"Redgate - Casino Canal Lower Level"

/obj/effect/overmap/visitable/sector/virgo3b
	name = "Virgo 3B"
	desc = "Full of phoron, and home to the NSB Adephagia."
	scanner_desc = @{"[i]Registration[/i]: NSB Adephagia
[i]Class[/i]: Installation
[i]Transponder[/i]: Transmitting (CIV), NanoTrasen IFF
[b]Notice[/b]: NanoTrasen Base, authorized personnel only"}

	icon = 'icons/obj/overmap_vr.dmi'
	icon_state = "virgo3b"

	skybox_icon = 'icons/skybox/virgo3b.dmi'
	skybox_icon_state = "small"
	skybox_pixel_x = 0
	skybox_pixel_y = 0

	mob_announce_cooldown = 0

/obj/effect/overmap/visitable/sector/virgo3c
	name = "Virgo 3C"
	desc = "A small, volcanically active moon."
	scanner_desc = @{"[i]Registration[/i]: NSB Rascal's Pass
[i]Class[/i]: Installation
[i]Transponder[/i]: Transmitting (CIV), NanoTrasen IFF
[b]Notice[/b]: NanoTrasen Base, authorized personnel only"}
	known = TRUE
	in_space = TRUE

	icon = 'icons/obj/overmap.dmi'
	icon_state = "lush"

	skybox_icon = null
	skybox_icon_state = null
	skybox_pixel_x = 0
	skybox_pixel_y = 0

	initial_generic_waypoints = list("groundbase", "gb_excursion_pad","omship_axolotl")
	initial_restricted_waypoints = list()

/obj/effect/overmap/visitable/sector/virgo2
	name = "Virgo 2"
	desc = "Includes the Remmi Aerostat and associated ground mining complexes."
	scanner_desc = @{"[i]Stellar Body[/i]: Virgo 2
[i]Class[/i]: R-Class Planet
[i]Habitability[/i]: Low (High Temperature, Toxic Atmosphere)
[b]Notice[/b]: Planetary environment not suitable for life. Landing may be hazardous."}
	icon_state = "globe"
	in_space = 0
	known = TRUE
	icon_state = "chlorine"

	skybox_icon = 'icons/skybox/virgo2.dmi'
	skybox_icon_state = "v2"
	skybox_pixel_x = 0
	skybox_pixel_y = 0

	extra_z_levels = list(Z_NAME_AEROSTAT_SURFACE)

//This is in the v5_outpost_build.dmm. I am unsure if this was maintained, but it's put here because it was a map edit
/obj/effect/overmap/visitable/sector/virgo5
	icon = 'icons/obj/overmap_vr.dmi'
	icon_state = "virgo5"
	name = "Virgo 5"
	scanner_desc = "Mahir, or Virgo 5, is the fifth planet from the star Virgo-Erigone. It suffers from Kessler Syndrome, making landing difficult and only possible at specific time intervals. The surface sits well below inhabitable temperatures and the atmosphere consists primarily of carbon dioxide."
	skybox_icon = 'icons/skybox/virgo5.dmi'
	skybox_icon_state = "v5"
	unknown_name = "unknown planet"


// === merged from maps/ during hard-fork flatten ===
// Z_LEVEL are just hard coded z-levels
// Z_NAME are late loaded z-level maps that can be looked up in GLOB.map_templates_loaded
// GLOB.map_templates_loaded is populated as /datum/map_template/proc/on_map_preload(z) is called
// Some Z_NAME ultimately will be indexed under an alias however e.g. Z_NAME_ALIAS_GATEWAY

// Southern Cross
#define Z_LEVEL_SC_STATION_MAINTS			1
#define Z_LEVEL_SC_STATION_ONE				2
#define Z_LEVEL_SC_STATION_TWO				3
#define Z_LEVEL_SC_STATION_THREE			4

#define Z_NAME_SC_SURFACE					"Southern Cross - Surface" // Aliased to Z_NAME_ALIAS_SURFACE
#define Z_NAME_SC_SURFACE_MINE				"Southern Cross - Surface Mines" // Aliased to Z_NAME_ALIAS_SURFACE_MINES
#define Z_NAME_SC_SURFACE_WILD				"Southern Cross - Surface Wild" // Aliased to Z_NAME_ALIAS_SURFACE_WILDS
#define Z_NAME_SC_MISC						"Southern Cross - Misc" // Aliased to Z_NAME_ALIAS_MISC
#define Z_NAME_SC_CENTCOM					"Southern Cross - Central Command" // Aliased to Z_NAME_ALIAS_CENTCOM
#define Z_NAME_SC_TRANSIT					"Southern Cross - Transit"

// Soluna Nexus
#define Z_LEVEL_SN_STATION_ONE				1
#define Z_LEVEL_SN_STATION_TWO				2
#define Z_LEVEL_SN_STATION_THREE			3

#define Z_NAME_SN_MISC						"Soluna Nexus - Misc" // Aliased to Z_NAME_ALIAS_MISC
#define Z_NAME_SN_CENTCOM					"Soluna Nexus - Central Command" // Aliased to Z_NAME_ALIAS_CENTCOM
#define Z_NAME_SN_TRANSIT					"Soluna Nexus - Transit"

// Cetus
#define Z_LEVEL_CETUS_STATION_ONE				1
#define Z_LEVEL_CETUS_STATION_TWO				2
#define Z_LEVEL_CETUS_STATION_THREE				3

#define Z_NAME_CETUS_MISC						"Cetus - Misc" // Aliased to Z_NAME_ALIAS_MISC
#define Z_NAME_CETUS_CENTCOM					"Cetus - Central Command" // Aliased to Z_NAME_ALIAS_CENTCOM
#define Z_NAME_CETUS_TRANSIT					"Cetus - Transit"

// Relic Base
#define Z_LEVEL_RB_CATACOMBS				1
#define Z_LEVEL_RB_UNDERGROUND				2
#define Z_LEVEL_RB_SURFACE					3
#define Z_LEVEL_RB_UPPER_FLOORS				4
#define Z_LEVEL_RB_THE_SKY					5

#define Z_NAME_RB_UNDERMINES				"Relic Base - Undermines"
#define Z_NAME_RB_SURFACE_WILDS				"Relic Base - Surface Wilds" // Aliased to Z_NAME_ALIAS_SURFACE_WILDS
#define Z_NAME_RB_WILDERNESS_SKY			"Relic Base - Wilderness Sky"
#define Z_NAME_RB_SURFACE_OCEAN				"Relic Base - Surface Ocean" // Aliased to Z_NAME_ALIAS_SURFACE
#define Z_NAME_RB_SURFACE_MINES				"Relic Base - Surface Mines" // Aliased to Z_NAME_ALIAS_SURFACE_MINES
#define Z_NAME_RB_CARRIER 					"Relic Base - Misc" // Aliased to Z_NAME_ALIAS_MISC
#define Z_NAME_RB_CENTCOM					"Relic Base - Central Command" // Aliased to Z_NAME_ALIAS_CENTCOM
#define Z_NAME_RB_TRANSIT					"Relic Base - Transit"

// Named Lateload Submaps
#define Z_NAME_FUELDEPOT_CH					"Offmap - Fueldepot CH"
#define Z_NAME_KARA_AEROSTAT_CH				"Offmap - Kara Aerostat - Z1 Aerostat CG"
#define Z_NAME_KARA_NSTAR_MINES_CH			"Offmap - Kara - Z1 Northern Star"
#define Z_NAME_VR_WORLD_CH					"VR - VR World CH"
#define Z_NAME_PLANET_THOR_CH				"Planet - Thor Surface CH"
#define Z_NAME_PLANET_TYR_CH				"Planet - Desert Valley CH"

// Common
#define Z_NAME_ALIAS_SURFACE				"SURFACE"
#define Z_NAME_ALIAS_SURFACE_MINES			"SURFACE MINES"
#define Z_NAME_ALIAS_SURFACE_WILDS			"SURFACE WILDS"

// Gateways (Aliased to Z_NAME_ALIAS_GATEWAY)
#define Z_NAME_GATEWAY_SNOW_FIELD_CH		"Gateway - Snow Field CH"
#define Z_NAME_GATEWAY_ABANDONED_CITY_CH	"Gateway - Abandoned City CH"
#define Z_NAME_GATEWAY_SKYSCRAPER_CH		"Gateway - Skyscraper CH"
#define Z_NAME_GATEWAY_BASE_BLEP_CH			"Gateway - Base Blep CH"
#define Z_NAME_GATEWAY_MADNESS_LAB_CH		"Gateway - Maddness Lab CH"
#define Z_NAME_GATEWAY_CARP_FARM_CH			"Gateway - Carp Farm CH"
#define Z_NAME_GATEWAY_HIDDEN_ECLIPSE_CH	"Gateway - Hidden Eclipse CH" // Commented out

// Camera Network Additions
#define NETWORK_EXTERIOR "Exterior" // Exterior Cameras
