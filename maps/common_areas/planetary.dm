//Planetside

/area/surface
	name = "The Surface (Don't Use)"
	flags = RAD_SHIELDED


/area/surface/outside
	ambience = AMBIENCE_SIF
	always_unpowered = TRUE
	outdoors = OUTDOORS_YES

// The area near the outpost, so POIs don't show up right next to the outpost.
/area/surface/outside/plains/outpost
	name = "Outpost Perimeter"
	icon_state = "green"

/area/surface/outside/plains/outpost/outdoors_area
	outdoors = OUTDOORS_AREA


//Surface Outposts

/area/surface/outpost
	ambience = AMBIENCE_GENERIC

//Wilderness Shuttle Shelter


// Main mining outpost
/area/surface/outpost/mining_main
	name = "North Mining Outpost"
	icon_state = "outpost_mine_main"
	outdoors = OUTDOORS_NO

/area/surface/outpost/mining_main/exterior
	name = "North Mining Outpost Exterior"
	icon_state = "outpost_mine_main"
	outdoors = OUTDOORS_YES

/area/surface/outpost/mining_main/exterior/pad
	name = "Surface Mines Operations Pad"


// Rust-Engine Outpost ksc


//Research Surface Outpost


//Main Outpost


//Civilian Outpost


//Security Outpost


//Fishing outpost


//Mining Station

