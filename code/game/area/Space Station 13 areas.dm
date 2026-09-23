/*

### This file contains a list of all the areas in your station. Format is as follows:

/area/CATEGORY/OR/DESCRIPTOR/NAME	(you can make as many subdivisions as you want)
	name = "NICE NAME"				(not required but makes things really nice)
	icon = "ICON FILENAME"			(defaults to areas.dmi)
	icon_state = "NAME OF ICON"		(defaults to "unknown" (blank))
	requires_power = 0				(defaults to 1)
	music = "music/music.ogg"		(defaults to "music/music.ogg")

NOTE: there are two lists of areas in the end of this file: centcom and station itself. Please maintain these lists valid. --rastaf0

*/

/*-----------------------------------------------------------------------------*/

/////////
//SPACE//
/////////

/area/space
	name = "\improper Space"
	icon_state = "space"
	requires_power = 1
	always_unpowered = 1
	dynamic_lighting = 0
	has_gravity = 0
	power_light = 0
	power_equip = 0
	power_environ = 0
	ambience = list('sound/ambience/ambispace.ogg','sound/music/title2.ogg','sound/music/space.ogg','sound/music/main.ogg','sound/music/traitor.ogg','sound/ambience/space/space_serithi.ogg','sound/music/freefallin.mid')
	base_turf = /turf/space
	ambience = AMBIENCE_SPACE
	flags = AREA_FLAG_IS_NOT_PERSISTENT

/area/space/atmosalert()
	return

/area/space/fire_alert()
	return

/area/space/fire_reset()
	return

/area/space/readyalert()
	return

/area/space/partyalert()
	return

/area/arrival
	requires_power = 0


/area/admin
	name = "\improper Admin room"
	icon_state = "start"


////////////
//SHUTTLES//
////////////
//Shuttles only need starting area, movement is handled by landmarks
//All shuttles should now be under shuttle since we have smooth-wall code.

/area/shuttle
	requires_power = 0
	flags = RAD_SHIELDED | AREA_FLAG_IS_NOT_PERSISTENT | AREA_FORBID_EVENTS
	sound_env = SMALL_ENCLOSED
	base_turf = /turf/space

/area/shuttle/arrival
	name = "\improper Arrival Shuttle"
	ambience = AMBIENCE_ARRIVALS

/area/shuttle/supply
	name = "\improper Supply Shuttle"
	icon_state = "shuttle2"

/area/shuttle/escape
	name = "\improper Emergency Shuttle"
	music = "music/escape.ogg"

/area/shuttle/escape/techfloor_grid_base
	base_turf = /turf/simulated/floor/tiled/techfloor/grid

/area/shuttle/escape_pod1
	name = "\improper Escape Pod One"
	music = "music/escape.ogg"

/area/shuttle/escape_pod2
	name = "\improper Escape Pod Two"
	music = "music/escape.ogg"

/area/shuttle/escape_pod3
	name = "\improper Escape Pod Three"
	music = "music/escape.ogg"

/area/shuttle/escape_pod4
	name = "\improper Escape Pod Four"
	music = "music/escape.ogg"

/area/shuttle/escape_pod5
	name = "\improper Escape Pod Five"
	music = "music/escape.ogg"

/area/shuttle/escape_pod6
	name = "\improper Escape Pod Six"
	music = "music/escape.ogg"

/area/shuttle/large_escape_pod1
	name = "\improper Large Escape Pod One"
	music = "music/escape.ogg"

/area/shuttle/large_escape_pod2
	name = "\improper Large Escape Pod Two"
	music = "music/escape.ogg"

/area/shuttle/cryo
	name = "\improper Cryogenic Storage"

/area/shuttle/mining
	name = "\improper Mining Elevator"
	music = "music/escape.ogg"
	dynamic_lighting = 0
	base_turf = /turf/simulated/mineral/floor/ignore_mapgen

/area/shuttle/transport1/centcom
	icon_state = "shuttle"
	name = "\improper Transport Shuttle CentCom"

/area/shuttle/transport1/station
	icon_state = "shuttle"
	name = "\improper Transport Shuttle"


/area/shuttle/prison/
	name = "\improper Prison Shuttle"

/area/shuttle/prison/station
	icon_state = "shuttle"

/area/shuttle/prison/prison
	icon_state = "shuttle2"

/area/shuttle/specops/centcom
	name = "\improper Special Ops Shuttle"
	icon_state = "shuttlered"

/area/shuttle/specops/station
	name = "\improper Special Ops Shuttle"
	icon_state = "shuttlered2"

/area/shuttle/syndicate_elite/mothership
	name = "\improper Merc Elite Shuttle"
	icon_state = "shuttlered"

/area/shuttle/syndicate_elite/station
	name = "\improper Merc Elite Shuttle"
	icon_state = "shuttlered2"

/area/shuttle/administration/centcom
	name = "Centcom Large Bay (AS)"
	icon_state = "shuttlered"

/area/shuttle/administration/station
	name = "NSB Adephagia (AS)"
	icon_state = "shuttlered2"

/area/shuttle/trade
	name = "\improper Trade Station"
	icon_state = "red"
	dynamic_lighting = 0


// === end remove


// CENTCOM

/area/centcom
	name = "\improper CentCom"
	icon_state = "centcom"
	requires_power = 0
	dynamic_lighting = 0
	flags = AREA_FLAG_IS_NOT_PERSISTENT


/area/centcom/evac
	name = "\improper CentCom Emergency Shuttle"

/area/centcom/suppy
	name = "\improper CentCom Supply Shuttle"


/area/centcom/living
	name = "\improper CentCom Living Quarters"

/area/centcom/specops
	name = "\improper CentCom Special Ops"

/area/centcom/creed
	name = "Creed's Office"

/area/centcom/holding
	name = "\improper Holding Facility"

/area/centcom/terminal
	name = "\improper Docking Terminal"
	icon_state = "centcom_dock"
	ambience = AMBIENCE_ARRIVALS


/area/centcom/security
	name = "\improper CentCom Security"
	icon_state = "centcom_security"

/area/centcom/security/residential
	name = "\improper CentCom Residential Security"

/area/centcom/security/arrivals
	name = "\improper CentCom Security Arrivals"

/area/centcom/medical
	name = "\improper CentCom Medical"
	icon_state = "centcom_medical"

/area/centcom/command
	name = "\improper CentCom Command" //Central Command Command totally isn't RAS Syndrome in action.
	icon_state = "centcom_command"
	ambience = AMBIENCE_HIGHSEC

/area/centcom/main_hall
	name = "\improper Main Hallway"
	icon_state = "centcom_hallway1"

/area/centcom/bar
	name = "\improper CentCom Bar"
	icon_state = "centcom_crew"


//SYNDICATES

/area/syndicate_mothership
	name = "\improper Mercenary Base"
	icon_state = "syndie-ship"
	requires_power = 0
	dynamic_lighting = 0
	ambience = AMBIENCE_HIGHSEC
	flags = AREA_FLAG_IS_NOT_PERSISTENT

/area/syndicate_mothership/trader
	name = "\improper Trader Base"


/area/syndicate_mothership/elite_squad
	name = "\improper Elite Mercenary Squad"
	icon_state = "syndie-elite"

//EXTRA

/area/asteroid					// -- TLE
	name = "\improper Moon"
	icon_state = "asteroid"
	requires_power = 0
	sound_env = ASTEROID
	flags = AREA_FLAG_IS_NOT_PERSISTENT


/area/tdome
	name = "\improper Thunderdome"
	icon_state = "thunder"
	requires_power = 0
	dynamic_lighting = 0
	sound_env = SOUND_ENVIRONMENT_ARENA
	flags = AREA_FLAG_IS_NOT_PERSISTENT

/area/tdome/tdome1
	name = "\improper Thunderdome (Team 1)"
	icon_state = "green"

/area/tdome/tdome2
	name = "\improper Thunderdome (Team 2)"
	icon_state = "yellow"

/area/tdome/tdomeadmin
	name = "\improper Thunderdome (Admin.)"
	icon_state = "purple"

/area/tdome/tdomeobserve
	name = "\improper Thunderdome (Observer.)"
	icon_state = "purple"

/area/virtual_reality
	name = "Virtual Reality"
	icon_state = "Virtual_Reality"
	dynamic_lighting = 0
	requires_power = 0
	flags = AREA_FLAG_IS_NOT_PERSISTENT

//ENEMY

//names are used
// start: Shuttle condensing
/area/syndicate_station
	name = "\improper Independent Station"
	icon_state = "yellow"
	requires_power = 0
	flags = RAD_SHIELDED
	base_turf = /turf/space
	ambience = AMBIENCE_HIGHSEC
	flags = AREA_FLAG_IS_NOT_PERSISTENT

/area/shuttle/syndicate
	name = "\improper Mercenary Shuttle"
	icon_state = "yellow"
	requires_power = 0
	flags = RAD_SHIELDED
	base_turf = /turf/space
	ambience = AMBIENCE_HIGHSEC
	flags = AREA_FLAG_IS_NOT_PERSISTENT
// Shuttle condensing

/area/syndicate_station/southwest
	name = "\improper south-west of SS13"
	icon_state = "southwest"


/area/syndicate_station/arrivals_dock
	name = "\improper docked with station"
	icon_state = "shuttle"


/area/syndicate_station/transit
	name = "\improper hyperspace"
	icon_state = "shuttle"

/area/wizard_station
	name = "\improper Wizard's Den"
	icon_state = "yellow"
	requires_power = 0
	dynamic_lighting = 0
	ambience = AMBIENCE_OTHERWORLDLY
	flags = AREA_FLAG_IS_NOT_PERSISTENT

// Shuttle condensing
/area/skipjack_station
	name = "Raider Outpost"
	icon_state = "yellow"
	requires_power = 0
	dynamic_lighting = 0
	flags = RAD_SHIELDED
	ambience = AMBIENCE_HIGHSEC

/area/shuttle/skipjack
	name = "\improper Skipjack"
	icon_state = "yellow"
	requires_power = 0
	base_turf = /turf/space
	ambience = AMBIENCE_HIGHSEC
	flags = AREA_FLAG_IS_NOT_PERSISTENT
// Shuttle condensing

//PRISON
/area/prison
	name = "\improper Prison Station"
	icon_state = "brig"
	ambience = AMBIENCE_HIGHSEC
	flags = AREA_FLAG_IS_NOT_PERSISTENT


/area/prison/solitary
	name = "Solitary Confinement"
	icon_state = "brig"


////////////////////
//SPACE STATION 13//
////////////////////

/area
	ambience = AMBIENCE_GENERIC

//Maintenance

/area/maintenance
	flags = RAD_SHIELDED
	sound_env = TUNNEL_ENCLOSED
	turf_initializer = new /datum/turf_initializer/maintenance()
	ambience = AMBIENCE_MAINTENANCE


/area/maintenance/apmaint
	name = "Cargo Engineering Maintenance"
	icon_state = "apmaint"


/area/maintenance/bar
	name = "Bar Maintenance"
	icon_state = "maint_bar"

/area/maintenance/central
	name = "Central Maintenance"
	icon_state = "maint_central"


/area/maintenance/cargo
	name = "Cargo Maintenance"
	icon_state = "maint_cargo"


/area/maintenance/chapel
	name = "Chapel Maintenance"
	icon_state = "maint_chapel"

/area/maintenance/disposal
	name = "Waste Disposal"
	icon_state = "disposal"
	flags = AREA_FLAG_IS_NOT_PERSISTENT //If trash items got this far, they can be safely deleted.

/area/maintenance/engineering
	name = "Engineering Maintenance"
	icon_state = "maint_engineering"


/area/maintenance/locker
	name = "Locker Room Maintenance"
	icon_state = "maint_locker"

/area/maintenance/medbay
	name = "Medbay Maintenance"
	icon_state = "maint_medbay"


/area/maintenance/medbay_fore
	name = "Medbay Maintenance - Fore"
	icon_state = "maint_medbay_fore"


/area/maintenance/research
	name = "Research Maintenance"
	icon_state = "maint_research"


/area/maintenance/security_port
	name = "Security Maintenance - Port"
	icon_state = "maint_security_port"

/area/maintenance/security_starboard
	name = "Security Maintenance - Starboard"
	icon_state = "maint_security_starboard"


// SUBSTATIONS (Subtype of maint, that should let them serve as shielded area during radstorm)

/area/maintenance/substation
	name = "Substation"
	icon_state = "substation"
	sound_env = SMALL_ENCLOSED
	ambience = AMBIENCE_SUBSTATION

/area/maintenance/substation/engineering // Probably will be connected to engineering SMES room, as wires cannot be crossed properly without them sharing powernets.
	name = "Engineering Substation"


/area/maintenance/substation/medical // Medbay
	name = "Medical Substation"

/area/maintenance/substation/research // Research
	name = "Research Substation"


/area/maintenance/substation/civilian // Dorms, Lockerroom, Pool
	name = "Civilian Substation"


/area/maintenance/substation/cargo // Cargo
	name = "Cargo Substation"

/area/maintenance/substation/command // AI and central cluster. This one will be between HoP office and meeting room (probably).
	name = "Command Substation"


/area/maintenance/substation/security // Security, Brig, Permabrig, etc.
	name = "Security Substation"

//Hallway

/area/hallway/primary/
	sound_env = LARGE_ENCLOSED
	ambience = AMBIENCE_GENERIC

/area/hallway/primary/fore
	name = "\improper Fore Primary Hallway"
	icon_state = "hallF"


/area/hallway/primary/central_one
	name = "\improper Central Primary Hallway - Fore"
	icon_state = "hallC1"


/area/hallway/secondary/exit
	name = "\improper Escape Shuttle Hallway"
	icon_state = "escape"


/area/hallway/secondary/entry
	flags = AREA_FORBID_EVENTS


/area/hallway/secondary/entry/D1
	name = "\improper Shuttle Dock Hallway - Dock One"
	icon_state = "entry_D1"
	base_turf = /turf/space
	flags = AREA_FORBID_EVENTS

/area/hallway/secondary/entry/D2
	name = "\improper Shuttle Dock Hallway - Dock Two"
	icon_state = "entry_D2"
	base_turf = /turf/space
	flags = AREA_FORBID_EVENTS

/area/hallway/secondary/entry/D2/arrivals
	name = "\improper Shuttle Dock Hallway - Dock Two"
	icon_state = "entry_D2"
	base_turf = /turf/space
	requires_power = 0

/area/hallway/secondary/entry/D3
	name = "\improper Shuttle Dock Hallway - Dock Three"
	icon_state = "entry_D3"
	base_turf = /turf/space
	flags = AREA_FORBID_EVENTS


/area/hallway/secondary/entry/docking_lounge
	name = "\improper Docking Lounge"
	icon_state = "docking_lounge"


/area/hallway/secondary/civilian_hallway_aft
	name = "\improper Civilian Hallway Aft"
	icon_state = "aft_civilian_hallway"

/area/hallway/secondary/civilian_hallway_fore
	name = "\improper Civilian Hallway Fore"
	icon_state = "fore_civilian_hallway"


/area/hallway/secondary/docking_hallway2
	name = "\improper Secondary Docking Hallway"
	icon_state = "docking_hallway"

/area/hallway/secondary/engineering_hallway
	name = "\improper Engineering Primary Hallway"
	icon_state = "engineering_primary_hallway"

/area/hallway/secondary/eva_hallway
	name = "\improper EVA Hallway"
	icon_state = "eva_hallway"


//Command

/area/bridge
	name = "\improper Bridge"
	icon_state = "bridge"
	music = "signal"
	flags = AREA_BLOCK_INSTANT_BUILDING

/area/bridge_hallway
	name = "\improper Bridge Hallway"
	icon_state = "bridge"

/area/bridge/meeting_room
	name = "\improper Heads of Staff Meeting Room"
	icon_state = "bridge"
	music = null
	sound_env = MEDIUM_SOFTFLOOR


/area/mint
	name = "\improper Mint"
	icon_state = "green"


/area/server
	name = "\improper Research Server Room"
	icon_state = "server"

//Civilian

/area/crew_quarters
	name = "\improper Dormitories"
	icon_state = "Sleep"
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_INSTANT_BUILDING
	ambience = AMBIENCE_GENERIC

/area/crew_quarters/toilet
	name = "\improper Dormitory Toilets"
	icon_state = "toilet"
	sound_env = SMALL_ENCLOSED

/area/crew_quarters/sleep
	name = "\improper Dormitories"
	icon_state = "Sleep"


/area/crew_quarters/sleep/vistor_room_1
	name = "\improper Visitor Room 1"
	icon_state = "Sleep"

/area/crew_quarters/sleep/vistor_room_2
	name = "\improper Visitor Room 2"
	icon_state = "Sleep"


// TFF 6/2/20 - Added two new dorms


/area/crew_quarters/locker
	name = "\improper Locker Room"
	icon_state = "locker"

/area/crew_quarters/locker/locker_toilet
	name = "\improper Locker Toilets"
	icon_state = "toilet"
	sound_env = SMALL_ENCLOSED


/area/crew_quarters/recreation_area_restroom
	name = "\improper Recreation Area Restroom"
	icon_state = "recreation_area_restroom"
	sound_env = SMALL_ENCLOSED

/area/crew_quarters/recreation_area_restroom/showers
	name = "\improper Recreation Area Showers"


/area/crew_quarters/cafeteria
	name = "\improper Cafeteria"
	icon_state = "cafeteria"


/area/crew_quarters/kitchen
	name = "\improper Kitchen"
	icon_state = "kitchen"

/area/crew_quarters/bar
	name = "\improper Bar"
	icon_state = "bar"
	sound_env = LARGE_SOFTFLOOR


/area/library
	name = "\improper Library"
	icon_state = "library"
	sound_env = LARGE_SOFTFLOOR
	lightswitch = 0 // We like dark libraries


/area/chapel
	ambience = AMBIENCE_CHAPEL
	flags = AREA_BLOCK_INSTANT_BUILDING

/area/chapel/main
	name = "\improper Chapel"
	icon_state = "chapel"
	sound_env = LARGE_ENCLOSED

/area/chapel/office
	name = "\improper Chapel Office"
	icon_state = "chapeloffice"


/area/lawoffice
	name = "\improper Internal Affairs"
	icon_state = "law"


/area/vacant/vacant_shop
	name = "\improper Vacant Shop"
	icon_state = "vacant_shop"


/area/holodeck
	name = "\improper Holodeck"
	icon_state = "Holodeck"
	dynamic_lighting = 0
	sound_env = LARGE_ENCLOSED
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_FORBID_EVENTS | AREA_BLOCK_INSTANT_BUILDING

/area/holodeck/alphadeck
	name = "\improper Holodeck Alpha"

/area/holodeck/source_plating
	name = "\improper Holodeck - Off"

/area/holodeck/source_emptycourt
	name = "\improper Holodeck - Empty Court"
	sound_env = SOUND_ENVIRONMENT_ARENA

/area/holodeck/source_boxingcourt
	name = "\improper Holodeck - Boxing Court"
	sound_env = SOUND_ENVIRONMENT_ARENA

/area/holodeck/source_basketball
	name = "\improper Holodeck - Basketball Court"
	sound_env = SOUND_ENVIRONMENT_ARENA

/area/holodeck/source_thunderdomecourt
	name = "\improper Holodeck - Thunderdome Court"
	requires_power = 0
	sound_env = SOUND_ENVIRONMENT_ARENA

/area/holodeck/source_courtroom
	name = "\improper Holodeck - Courtroom"
	sound_env = SOUND_ENVIRONMENT_AUDITORIUM

/area/holodeck/source_beach
	name = "\improper Holodeck - Beach"
	sound_env = SOUND_ENVIRONMENT_PLAIN

/area/holodeck/source_burntest
	name = "\improper Holodeck - Atmospheric Burn Test"

/area/holodeck/source_wildlife
	name = "\improper Holodeck - Wildlife Simulation"

/area/holodeck/source_meetinghall
	name = "\improper Holodeck - Meeting Hall"
	sound_env = SOUND_ENVIRONMENT_AUDITORIUM

/area/holodeck/source_theatre
	name = "\improper Holodeck - Theatre"
	sound_env = SOUND_ENVIRONMENT_CONCERT_HALL

/area/holodeck/source_picnicarea
	name = "\improper Holodeck - Picnic Area"
	sound_env = SOUND_ENVIRONMENT_PLAIN

/area/holodeck/source_snowfield
	name = "\improper Holodeck - Snow Field"
	sound_env = SOUND_ENVIRONMENT_FOREST

/area/holodeck/source_desert
	name = "\improper Holodeck - Desert"
	sound_env = SOUND_ENVIRONMENT_PLAIN

/area/holodeck/source_space
	name = "\improper Holodeck - Space"
	has_gravity = 0
	sound_env = SPACE

/area/holodeck/source_chess
	name = "\improper Holodeck - Chessboard"


//Engineering

/area/engineering/
	name = "\improper Engineering"
	icon_state = "engineering"
	ambience = AMBIENCE_ENGINEERING
	flags = AREA_BLOCK_INSTANT_BUILDING

/area/engineering/atmos
	name = "\improper Atmospherics"
	icon_state = "atmos"
	sound_env = LARGE_ENCLOSED
	ambience = AMBIENCE_ATMOS

/area/engineering/atmos/monitoring
	name = "\improper Atmospherics Monitoring Room"
	icon_state = "atmos_monitoring"
	sound_env = STANDARD_STATION

/area/engineering/atmos/storage
	name = "\improper Atmospherics Storage"
	icon_state = "atmos_storage"
	sound_env = SMALL_ENCLOSED

/area/engineering/drone_fabrication
	name = "\improper Engineering Drone Fabrication"
	icon_state = "drone_fab"
	sound_env = SMALL_ENCLOSED

/area/engineering/engine_smes
	name = "\improper Engineering SMES"
	icon_state = "engine_smes"
	sound_env = SMALL_ENCLOSED

/area/engineering/engine_room
	name = "\improper Engine Room"
	icon_state = "engine"
	sound_env = LARGE_ENCLOSED
	flags = AREA_FORBID_EVENTS | AREA_BLOCK_INSTANT_BUILDING

/area/engineering/engine_airlock
	name = "\improper Engine Room Airlock"
	icon_state = "engine"

/area/engineering/engine_monitoring
	name = "\improper Engine Monitoring Room"
	icon_state = "engine_monitoring"

/area/engineering/engine_waste
	name = "\improper Engine Waste Handling"
	icon_state = "engine_waste"


/area/engineering/foyer
	name = "\improper Engineering Foyer"
	icon_state = "engineering_foyer"

/area/engineering/storage
	name = "\improper Engineering Storage"
	icon_state = "engineering_storage"

/area/engineering/break_room
	name = "\improper Engineering Break Room"
	icon_state = "engineering_break"
	sound_env = MEDIUM_SOFTFLOOR


/area/engineering/locker_room
	name = "\improper Engineering Locker Room"
	icon_state = "engineering_locker"

/area/engineering/workshop
	name = "\improper Engineering Workshop"
	icon_state = "engineering_workshop"


//Solars

/area/solar
	requires_power = 1
	always_unpowered = 1
	dynamic_lighting = 0
	ambience = AMBIENCE_SPACE


/area/assembly/chargebay
	name = "\improper Mech Bay"
	icon_state = "mechbay"


/area/assembly/robotics
	name = "\improper Robotics Lab"
	icon_state = "robotics"


//Teleporter

/area/teleporter
	name = "\improper Teleporter"
	icon_state = "teleporter"
	music = "signal"
	flags = RAD_SHIELDED


//MedBay

/area/medical/medbay
	name = "\improper Medbay Hallway - Port"
	icon_state = "medbay"
	music = 'sound/ambience/signal.ogg'

//Medbay is a large area, these additional areas help level out APC load.
/area/medical/medbay2
	name = "\improper Medbay Hallway - Starboard"
	icon_state = "medbay2"
	music = 'sound/ambience/signal.ogg'


/area/medical/biostorage
	name = "\improper Secondary Storage"
	icon_state = "medbay2"
	music = 'sound/ambience/signal.ogg'

/area/medical/reception
	name = "\improper Medbay Reception"
	icon_state = "medbay"
	music = 'sound/ambience/signal.ogg'

/area/medical/medbay_emt_bay
	name = "\improper Medical EMT Bay"
	icon_state = "medbay_emt_bay"
	music = 'sound/ambience/signal.ogg'

/area/medical/medbay_primary_storage
	name = "\improper Medbay Primary Storage"
	icon_state = "medbay_primary_storage"
	music = 'sound/ambience/signal.ogg'

/area/medical/psych
	name = "\improper Psych Room"
	icon_state = "medbay3"
	music = 'sound/ambience/signal.ogg'


/area/medical/ward
	name = "\improper Recovery Ward"
	icon_state = "patients"

/area/medical/patient_a
	name = "\improper Patient A"
	icon_state = "medbay_patient_room_a"

/area/medical/patient_b
	name = "\improper Patient B"
	icon_state = "medbay_patient_room_b"


/area/medical/patient_wing
	name = "\improper Patient Wing"
	icon_state = "patients"


/area/medical/virology
	name = "\improper Virology"
	icon_state = "virology"

/area/medical/virologyaccess
	name = "\improper Virology Access"
	icon_state = "virology"

/area/medical/morgue
	name = "\improper Morgue"
	icon_state = "morgue"

/area/medical/chemistry
	name = "\improper Chemistry"
	icon_state = "chem"

/area/medical/surgery
	name = "\improper Operating Theatre 1"
	icon_state = "surgery"
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_INSTANT_BUILDING//This WOULD become a filth pit

/area/medical/surgery2
	name = "\improper Operating Theatre 2"
	icon_state = "surgery"
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_INSTANT_BUILDING

/area/medical/surgeryobs
	name = "\improper Operation Observation Room"
	icon_state = "surgery"


/area/medical/surgery_storage
	name = "\improper Surgery Storage"
	icon_state = "surgery_storage"

/area/medical/cryo
	name = "\improper Cryogenics"
	icon_state = "cryo"

/area/medical/exam_room
	name = "\improper Exam Room"
	icon_state = "exam_room"

/area/medical/genetics
	name = "\improper Genetics Lab"
	icon_state = "genetics"

/area/medical/genetics_cloning
	name = "\improper Cloning Lab"
	icon_state = "cloning"

/area/medical/sleeper
	name = "\improper Emergency Treatment Centre"
	icon_state = "exam_room"
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_INSTANT_BUILDING//Trust me.


/area/medical/first_aid_station
	name = "\improper Port First-Aid Station"
	icon_state = "medbay2"

//Security

/area/security/main
	name = "\improper Security Office"
	icon_state = "security"

/area/security/lobby
	name = "\improper Security Lobby"
	icon_state = "security"

/area/security/brig
	name = "\improper Security - Brig"
	icon_state = "brig"

/area/security/brig/prison_break()
	for(var/obj/structure/closet/secure_closet/brig/temp_closet in src)
		temp_closet.locked = 0
		temp_closet.icon_state = "closed_unlocked"
	for(var/obj/machinery/door_timer/temp_timer in src)
		temp_timer.timer_duration = 1
	..()

/area/security/prison
	name = "\improper Security - Prison Wing"
	icon_state = "sec_prison"

/area/security/prison/prison_break()
	for(var/obj/structure/closet/secure_closet/brig/temp_closet in src)
		temp_closet.locked = 0
		temp_closet.icon_state = "closed_unlocked"
	for(var/obj/machinery/door_timer/temp_timer in src)
		temp_timer.timer_duration = 1
	..()

/area/security/warden
	name = "\improper Security - Warden's Office"
	icon_state = "Warden"

/area/security/armoury
	name = "\improper Security - Armory"
	icon_state = "armory"
	ambience = AMBIENCE_HIGHSEC


/area/security/evidence_storage
	name = "\improper Security - Equipment Storage"
	icon_state = "security_equipment_storage"

/area/security/evidence_storage
	name = "\improper Security - Evidence Storage"
	icon_state = "evidence_storage"

/area/security/interrogation
	name = "\improper Security - Interrogation"
	icon_state = "interrogation"

/area/security/riot_control
	name = "\improper Security - Riot Control"
	icon_state = "riot_control"
	flags = RAD_SHIELDED

/area/security/detectives_office
	name = "\improper Security - Forensic Office"
	icon_state = "detective"
	sound_env = MEDIUM_SOFTFLOOR

/area/security/range
	name = "\improper Security - Firing Range"
	icon_state = "firingrange"


/area/security/security_cell_hallway
	name = "\improper Security - Cell Hallway"
	icon_state = "security_cell_hallway"

/area/security/security_equiptment_storage
	name = "\improper Security - Equipment Storage"
	icon_state = "security_equip_storage"

/area/security/security_lockerroom
	name = "\improper Security - Locker Room"
	icon_state = "security_lockerroom"

/area/security/security_processing
	name = "\improper Security - Security Processing"
	icon_state = "security_processing"

/area/security/tactical
	name = "\improper Security - Tactical Equipment"
	icon_state = "Tactical"
	ambience = AMBIENCE_HIGHSEC


/*
	New()
		..()

		spawn(10) //let objects set up first
			for(var/turf/turfToGrayscale in src)
				if(turfToGrayscale.icon)
					var/icon/newIcon = icon(turfToGrayscale.icon)
					newIcon.GrayScale()
					turfToGrayscale.icon = newIcon
				for(var/obj/objectToGrayscale in turfToGrayscale) //1 level deep, means tables, apcs, locker, etc, but not locker contents
					if(objectToGrayscale.icon)
						var/icon/newIcon = icon(objectToGrayscale.icon)
						newIcon.GrayScale()
						objectToGrayscale.icon = newIcon
*/

/area/security/nuke_storage
	name = "\improper Vault"
	icon_state = "nuke_storage"
	ambience = AMBIENCE_HIGHSEC


/area/security/checkpoint2
	name = "\improper Security - Arrival Checkpoint"
	icon_state = "security"
	ambience = AMBIENCE_ARRIVALS


/area/janitor/
	name = "\improper Custodial Closet"
	icon_state = "janitor"

/area/hydroponics
	name = "\improper Hydroponics"
	icon_state = "hydro"
	flags = AREA_BLOCK_INSTANT_BUILDING


// SUPPLY

/area/quartermaster
	name = "\improper Quartermasters"
	icon_state = "quart"
	flags = AREA_BLOCK_INSTANT_BUILDING

/area/quartermaster/office
	name = "\improper Cargo Office"
	icon_state = "quartoffice"

/area/quartermaster/storage
	name = "\improper Cargo Bay"
	icon_state = "quartstorage"
	sound_env = LARGE_ENCLOSED

/area/quartermaster/foyer
	name = "\improper Cargo Bay Foyer"
	icon_state = "quartstorage"

/area/quartermaster/warehouse
	name = "\improper Cargo Warehouse"
	icon_state = "quartstorage"

/area/quartermaster/qm
	name = "\improper Cargo - Quartermaster's Office"
	icon_state = "quart"

/area/quartermaster/delivery
	name = "\improper Cargo - Delivery Office"
	icon_state = "quart"
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_INSTANT_BUILDING//So trash doesn't pile up too hard.


// SCIENCE

/area/rnd/research
	name = "\improper Research and Development"
	icon_state = "research"

/area/rnd/research_foyer
	name = "\improper Research Foyer"
	icon_state = "research_foyer"


/area/rnd/research_storage
	name = "\improper Research Storage"
	icon_state = "research_storage"


/area/rnd/lab
	name = "\improper Research Lab"
	icon_state = "toxlab"


/area/rnd/xenobiology
	name = "\improper Xenobiology Lab"
	icon_state = "xeno_lab"


/area/rnd/xenobiology/xenoflora_storage
	name = "\improper Xenoflora Storage"
	icon_state = "xeno_f_store"

/area/rnd/xenobiology/xenoflora
	name = "\improper Xenoflora Lab"
	icon_state = "xeno_f_lab"

/area/rnd/storage
	name = "\improper Toxins Storage"
	icon_state = "toxstorage"

/area/rnd/test_area
	name = "\improper Toxins Test Area"
	icon_state = "toxtest"

/area/rnd/mixing
	name = "\improper Toxins Mixing Room"
	icon_state = "toxmix"

/area/rnd/misc_lab
	name = "\improper Miscellaneous Research"
	icon_state = "toxmisc"

/area/rnd/workshop
	name = "\improper Workshop"
	icon_state = "sci_workshop"


//Storage


/area/storage/primary
	name = "Primary Tool Storage"
	icon_state = "primarystorage"


/area/storage/auxillary
	name = "Auxillary Storage"
	icon_state = "auxstorage"


/area/storage/tech
	name = "Technical Storage"
	icon_state = "auxstorage"


//DJSTATION


//DERELICT

/area/derelict
	name = "\improper Derelict Station"
	icon_state = "storage"
	ambience = AMBIENCE_RUINS
	flags = AREA_FLAG_IS_NOT_PERSISTENT


/area/derelict/eva
	name = "Derelict EVA Storage"
	icon_state = "eva"

/area/derelict/eva/annex
	name = "Derelict Annex"
	icon_state = "eva"


//HALF-BUILT STATION (REPLACES DERELICT IN BAYCODE, ABOVE IS LEFT FOR DOWNSTREAM)


//area/constructionsite
//	name = "\improper Construction Site Shuttle"

//area/constructionsite
//	name = "\improper Construction Site Shuttle"


//Construction

/area/construction
	name = "\improper Engineering Construction Area"
	icon_state = "yellow"


//AI

/area/ai_monitored/storage/eva
	name = "EVA Storage"
	icon_state = "eva"

/area/ai_monitored/storage/secure
	name = "Secure Storage"
	icon_state = "storage"
	ambience = AMBIENCE_HIGHSEC

/area/ai_monitored/storage/emergency
	name = "Emergency Storage"
	icon_state = "storage"

/area/ai_monitored/storage/emergency/eva
	name = "Emergency EVA"
	icon_state = "storage"

/area/ai_upload
	name = "\improper AI Upload Chamber"
	icon_state = "ai_upload"
	ambience = AMBIENCE_AI

/area/ai_upload_foyer
	name = "AI Upload Access"
	icon_state = "ai_foyer"
	sound_env = SMALL_ENCLOSED
	ambience = AMBIENCE_AI

/area/ai_server_room
	name = "Messaging Server Room"
	icon_state = "ai_server"
	sound_env = SMALL_ENCLOSED
	ambience = AMBIENCE_AI

/area/ai
	name = "\improper AI Chamber"
	icon_state = "ai_chamber"
	ambience = AMBIENCE_AI


/area/aisat
	name = "\improper AI Satellite"
	icon_state = "ai"
	ambience = AMBIENCE_AI


//Misc


// Telecommunications Satellite
/area/tcommsat/
	ambience = AMBIENCE_ENGINEERING

/area/tcommsat/entrance
	name = "\improper Telecomms Teleporter"
	icon_state = "tcomsatentrance"

/area/tcommsat/entrance/actually
	name = "\improper Telecomms Entrance"

/area/tcommsat/chamber
	name = "\improper Telecomms Central Compartment"
	icon_state = "tcomsatcham"

/area/tcomsat
	name = "\improper Telecomms Satellite"
	icon_state = "tcomsatlob"
	ambience = AMBIENCE_ENGINEERING

/area/tcomsat/lobby
	name = "\improper Telecomms Lobby"

/area/tcomfoyer
	name = "\improper Telecomms Foyer"
	icon_state = "tcomsatfoyer"
	ambience = AMBIENCE_ENGINEERING

/area/tcomfoyer/storage
	name = "\improper Telecomms Storage"


/area/tcommsat/computer
	name = "\improper Telecomms Control Room"
	icon_state = "tcomsatcomp"


// Away Missions
/area/awaymission
	name = "\improper Strange Location"
	icon_state = "away"
	ambience = AMBIENCE_FOREBODING
	flags = AREA_FLAG_IS_NOT_PERSISTENT


/area/awaymission/wwmines
	name = "\improper Wild West Mines"
	icon_state = "away1"
	luminosity = 1
	requires_power = 0


/////////////////////////////////////////////////////////////////////
/*
 * Lists of areas to be used with is_type_in_list.
 * Used in gamemodes code at the moment. --rastaf0
*/

// CENTCOM
GLOBAL_LIST_INIT(centcom_areas, list(
	/area/centcom,
	/area/shuttle/escape/centcom,
	/area/shuttle/escape_pod1/centcom,
	/area/shuttle/escape_pod2/centcom,
	/area/shuttle/escape_pod3/centcom,
	/area/shuttle/escape_pod5/centcom,
	/area/shuttle/transport1/centcom,
	/area/shuttle/administration/centcom,
	/area/shuttle/specops/centcom,
))

//SPACE STATION 13
GLOBAL_LIST_INIT(the_station_areas, list(
	/area/shuttle/arrival,
	/area/shuttle/escape/station,
	/area/shuttle/escape_pod1/station,
	/area/shuttle/escape_pod2/station,
	/area/shuttle/escape_pod3/station,
	/area/shuttle/escape_pod5/station,
	/area/shuttle/mining/station,
	/area/shuttle/transport1/station,
	// /area/shuttle/transport2/station,
	/area/shuttle/prison/station,
	/area/shuttle/administration/station,
	/area/shuttle/specops/station,
	/area/maintenance,
	/area/hallway,
	/area/bridge,
	/area/crew_quarters,
	/area/holodeck,
	/area/mint,
	/area/library,
	/area/chapel,
	/area/lawoffice,
	/area/engineering,
	/area/solar,
	/area/assembly,
	/area/teleporter,
	/area/medical,
	/area/security,
	/area/quartermaster,
	/area/janitor,
	/area/hydroponics,
	/area/rnd,
	/area/storage,
	/area/construction,
	/area/ai_monitored/storage/eva,
	/area/ai_monitored/storage/secure,
	/area/ai_monitored/storage/emergency,
	/area/ai_upload,
	/area/ai_upload_foyer,
	/area/ai
))


/area/beach
	name = "Keelin's private beach"
	icon_state = "yellow"
	luminosity = 1
	dynamic_lighting = 0
	requires_power = 0

/area/shadekin
	name = "\improper Shadekin Retreat"
	icon_state = "blue"
	requires_power = 0
	ambience = AMBIENCE_OTHERWORLDLY
	flags = RAD_SHIELDED | AREA_FLAG_IS_NOT_PERSISTENT | BLUE_SHIELDED | AREA_ALLOW_LARGE_SIZE | AREA_LIMIT_DARK_RESPITE | AREA_ALLOW_CLOCKOUT | AREA_BLOCK_INSTANT_BUILDING


// === merged from Space Station 13 areas_ch.dm during hard-fork de-suffix (verified no override-order change) ===
//Moved hangars to here from Southern cross areas.
/area/hangar
	name = "\improper First Deck Hangar"
	icon_state = "hangar"
	sound_env = LARGE_ENCLOSED
	ambience = AMBIENCE_HANGAR

/area/hangar/one
	name = "\improper Hangar One"


/area/hangar/two
	name = "\improper Hangar Two"


/area/hangar/three
	name = "\improper Hangar Three"


/area/engineering/gravgen
	name = "Gravity Generator"
	icon_state = "engineering"

/area/shuttle/stargazer
	name = "\improper Stargazer"
	icon_state = "shuttlered"
	requires_power = TRUE

/area/shuttle/echidna
	name = "\improper Echidna"
	icon_state = "shuttlered"
	requires_power = TRUE

/area/shuttle/ursula
	name = "\improper Ursula"
	icon_state = "shuttlered"
	requires_power = TRUE

/area/shuttle/needle
	name = "\improper Needle"
	icon_state = "shuttlered"
	requires_power = TRUE

/area/shuttle/baby_mammoth
	name = "\improper Baby_mammoth"
	icon_state = "shuttlered"
	requires_power = TRUE

/area/shuttle/spacebus
	name = "\improper Space Bus"
	icon_state = "shuttlered"
	requires_power = TRUE

/area/shuttle/junker
	name = "\improper Junker"
	icon_state = "shuttlered"
	requires_power = TRUE


/area/library
	flags = AREA_ALLOW_CLOCKOUT

/area/crew_quarters
	flags = AREA_ALLOW_CLOCKOUT

/area/crew_quarters/cafeteria
	flags = RAD_SHIELDED | AREA_ALLOW_CLOCKOUT


/area/crew_quarters/kitchen
	flags = RAD_SHIELDED

/area/crew_quarters/bar
	flags = RAD_SHIELDED

/area/crew_quarters/sleep
	flags = RAD_SHIELDED | AREA_SOUNDPROOF | AREA_FORBID_EVENTS | AREA_ALLOW_LARGE_SIZE | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_TRACKING | AREA_FORBID_SINGULO | AREA_ALLOW_CLOCKOUT

/area/crew_quarters/sleep/vistor_room_1

/area/crew_quarters/sleep/vistor_room_2


/area/security/nuke_storage
	flags = PHASE_SHIELDED


/area/maintenance/field
	name = "Maintenance Deck Field"

/area/security/armoury
	flags = PHASE_SHIELDED

/area/centcom/living
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_SOUNDPROOF | AREA_ALLOW_LARGE_SIZE | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/centcom/specops
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/centcom/command
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/centcom/creed
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/shuttle/response_ship
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/shuttle/administration
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/shuttle/transport1/centcom
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/shuttle/syndicate
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/syndicate_station
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/syndicate_mothership/elite_squad
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/shuttle/syndicate_elite/mothership
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/shuttle/skipjack
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/skipjack_station
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/ninja_dojo/dojo
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/shuttle/ninja
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/shuttle/trade
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/shuttle/merchant
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/wizard_station
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_BLOCK_GHOSTS | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_BLOCK_PHASE_SHIFT | AREA_BLOCK_GHOST_SIGHT

/area/crew_quarters/heads/sc
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO

/area/crew_quarters/heads/sc/hop/quarters
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/crew_quarters/heads/sc/hor/quarters
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/crew_quarters/heads/sc/chief/quarters
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/crew_quarters/heads/sc/hos/quarters
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/crew_quarters/heads/sc/cmo/quarters
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/crew_quarters/heads/sc/restroom
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/crew_quarters/heads/sc/bs
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/crew_quarters/toilet
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS


/area/engineering/engi_restroom
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/security/security_restroom
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/medical/medical_restroom
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/rnd/research_restroom_sc
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS

/area/crew_quarters/toilet/firstdeck
	flags = RAD_SHIELDED | AREA_FORBID_EVENTS | AREA_FORBID_SINGULO | AREA_BLOCK_TRACKING | AREA_BLOCK_SUIT_SENSORS | AREA_ALLOW_CLOCKOUT

/area/maintenance
	flags = RAD_SHIELDED | AREA_ALLOW_CLOCKOUT

/area/maintenance/solars
	flags = RAD_SHIELDED

/area/maintenance/substation
	flags = RAD_SHIELDED

/area/hallway
	flags = AREA_ALLOW_CLOCKOUT

/area/hallway/secondary/entry
	flags = AREA_FORBID_EVENTS | AREA_ALLOW_CLOCKOUT

/area/hallway/secondary/entry/D1
	flags = AREA_FORBID_EVENTS | AREA_ALLOW_CLOCKOUT

/area/hallway/secondary/entry/D2
	flags = AREA_FORBID_EVENTS | AREA_ALLOW_CLOCKOUT

/area/hallway/secondary/entry/D3
	flags = AREA_FORBID_EVENTS | AREA_ALLOW_CLOCKOUT


/area/holodeck/alphadeck
	flags = AREA_ALLOW_CLOCKOUT | AREA_FLAG_IS_NOT_PERSISTENT | AREA_FORBID_EVENTS

/area/turbolift
	flags = RAD_SHIELDED | AREA_ALLOW_CLOCKOUT


/area/surface/outside
	flags = AREA_FLAG_IS_NOT_PERSISTENT | AREA_ALLOW_CLOCKOUT


/area/medical/foyer
	flags = AREA_ALLOW_CLOCKOUT

/area/medical/first_aid_station
	flags = AREA_ALLOW_CLOCKOUT

/area/rnd/research_foyer
	flags = AREA_ALLOW_CLOCKOUT

/area/engineering/foyer
	flags = AREA_ALLOW_CLOCKOUT

/area/security/lobby
	flags = AREA_ALLOW_CLOCKOUT

/area/quartermaster/foyer
	flags = AREA_ALLOW_CLOCKOUT

/area/hangar/two
	flags = AREA_ALLOW_CLOCKOUT

/area/hangar/three
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/stationshuttle
	flags = AREA_ALLOW_CLOCKOUT

/area/storage/primary
	flags = AREA_ALLOW_CLOCKOUT

/area/storage/auxillary
	flags = AREA_ALLOW_CLOCKOUT

/area/storage/emergency_storage
	flags = AREA_ALLOW_CLOCKOUT | RAD_SHIELDED


//Carrier Areas
/area/expoutpost/suite1
	flags = AREA_ALLOW_CLOCKOUT | RAD_SHIELDED

/area/expoutpost/suite2
	flags = AREA_ALLOW_CLOCKOUT | RAD_SHIELDED

/area/expoutpost/slingcarrierdock
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/staginghangar
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/uppersternhallway
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/medbaylobby
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/rndlobby
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/midsternhallway
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/lowersternhallway
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/breakroom
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/starbowhallway
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/portbowhallway
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/restrooms
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/bar
	flags = AREA_ALLOW_CLOCKOUT | RAD_SHIELDED

/area/expoutpost/washroom
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/civaccesshallway
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/eva
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/botany
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/starboardbowairlock
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/portbowairlock
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/portqpadjunction
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/starqpadjunction
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/stationqpad
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/portuppermaint
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/portexplomaint
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/portlowermaint
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/staruppermaint
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/starsciencemaint
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/starlowermaint
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/hangarone
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/hangartwo
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/hangarthree
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/hangarfour
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/hangarfive
	flags = AREA_ALLOW_CLOCKOUT

/area/expoutpost/hangarsix
	flags = AREA_ALLOW_CLOCKOUT


//Rouguelike Mining
/area/asteroid/rogue
	has_gravity = 0
	requires_power = 1
	always_unpowered = 1
	power_light = 0
	power_equip = 0
	power_environ = 0
	var/asteroid_spawns = list()
	var/mob_spawns = list()
	var/shuttle_area //It would be neat if this were more dynamic, but eh.


/area/rnd/outpost
	name = "\improper Research Outpost Hallway"
	icon_state = "research"


/area/engineering/engine_gas
	name = "\improper Engine Gas Storage"
	icon_state = "engine_waste"

//holodeck 3/29/21
/area/holodeck/source_smoleworld
	name = "\improper Holodeck - Smolworld"

/area/holodeck/source_gym
	name = "\improper Holodeck - Gym"

/area/holodeck/source_game_room
	name = "\improper Holodeck - Game Room"

/area/holodeck/source_patient_ward
	name = "\improper Holodeck - Patient Ward"

/area/holodeck/the_uwu_zone
	name = "\improper Holodeck - Inside"
