// Variants of /obj/structure/sign/levels: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_sign_levels, list(
	"ai_core" = list("name" = "\improper AI Core", "desc" = "A level sign, stating the level to find the AI Core on.", "icon_state" = "level_ai_core"),
	"bar" = list("name" = "\improper Bar", "desc" = "A level sign, stating the level to find the nearest watering hole on.", "icon_state" = "level_bar"),
	"bridge" = list("name" = "\improper Bridge", "desc" = "A level sign, stating the level to find the Bridge on.", "icon_state" = "level_bridge"),
	"chapel" = list("name" = "\improper Chapel", "desc" = "A level sign, stating the level to find the Chapel on.", "icon_state" = "level_chapel"),
	"command" = list("name" = "\improper Command", "desc" = "A level sign, stating the level to find the Command Center on.", "icon_state" = "level_command"),
	"cryo" = list("name" = "\improper Cryogenic Storage", "desc" = "A level sign, stating the level to find Cryogenic Storage on.", "icon_state" = "level_cry"),
	"dock" = list("name" = "\improper Dock", "desc" = "A level sign, stating the level to find the nearest docking area on.", "icon_state" = "level_dock"),
	"dorms" = list("name" = "\improper Dormitories", "desc" = "A level sign, stating the level to find the Dormitories on.", "icon_state" = "level_dorms"),
	"elevator" = list("name" = "\improper Elevator", "desc" = "A level sign, stating the level to find the nearest elevator on.", "icon_state" = "level_elv"),
	"eva" = list("name" = "\improper Extra-Vehicular Activity", "desc" = "A level sign, stating the level to find the EVA Bay on.", "icon_state" = "level_eva"),
	"evac" = list("name" = "\improper Evacuation", "desc" = "A level sign, stating the level to find the Escape Shuttle Dock on.", "icon_state" = "level_evac"),
	"gym" = list("name" = "\improper Gym", "desc" = "A level sign, stating the level to find the Gym on.", "icon_state" = "level_gym"),
	"janitor" = list("name" = "\improper Custodial Closet", "desc" = "A level sign, stating the level to find the Custodial Closet on.", "icon_state" = "level_janitor"),
	"kitchen" = list("name" = "\improper Kitchen", "desc" = "A pictographic direction sign with a knife, plate, and fork, stating the level to find the nearest dining establishment on.", "icon_state" = "level_kitchen"),
	"library" = list("name" = "\improper Library", "desc" = "A level sign, stating the level to find the Library on.", "icon_state" = "level_library"),
	"pool" = list("name" = "\improper Pool", "desc" = "A level sign, stating the level to find the Pool on.", "icon_state" = "level_pool"),
	"recreation" = list("name" = "\improper Recreation Area", "desc" = "A level sign, stating the level to find the nearest Recreation Area on.", "icon_state" = "level_recreation"),
	"shuttle_bay" = list("name" = "\improper Shuttle Bay", "desc" = "A direction sign, stating the level to find the nearest shuttle bay on.", "icon_state" = "level_bay"),
	"telecomms" = list("name" = "\improper Telecommunications Hub", "desc" = "A level sign, stating the level to find the Telecommunications Hub on.", "icon_state" = "level_tcomms"),
	"teleporter" = list("name" = "\improper Teleporter", "desc" = "A level sign, stating the level to find the Teleporter on.", "icon_state" = "level_teleport"),
	"tram" = list("name" = "\improper Public Transit Station", "desc" = "A level sign, stating the level to find the nearest public transit station on.", "icon_state" = "level_tram"),
))
