/*
Remember to update _globalvars/traits.dm if you're adding/removing/renaming traits.
*/

/*
//mob traits
#define TRAIT_BLIND 			"blind"
*/
#define TRAIT_DREAMING			"currently_dreaming"
#define TRAIT_MUTE				"mute"
#define TRAIT_CAN_SEE_WIRES		"wire_seerr"
#define TRAIT_XENO_HOST			"xeno_host"	//Tracks whether we're gonna be a baby alien's mummy.
#define TRAIT_MIMING			"miming" //Tracks whether you're a mime or not.
/// "Magic" trait that blocks the mob from moving or interacting with anything. Used for transient stuff like mob transformations or incorporality in special cases.
/// Will block movement, `Life()` (!!!), and other stuff based on the mob.
#define TRAIT_NO_TRANSFORM		"block_transformations"
#define TRAIT_ANTIMAGIC			"anti_magic"
#define TRAIT_HOLY				"holy"
#define TRAIT_NODROP            "nodrop"
#define TRAIT_DISRUPTED			"disrupted"
#define TRAIT_NO_TELEPORT		"no-teleport" //you just can't
#define MAGIC_TRAIT "magic"
#define JOB_TRAIT "job"
#define TRAIT_MIME "mime" //Mime trait.
/*
#define CYBORG_ITEM_TRAIT "cyborg-item"
*/
#define ADMIN_TRAIT "admin" // (B)admins only.
#define CLOTHING_TRAIT "clothing"
#define HAND_REPLACEMENT_TRAIT "magic-hand"

#define STRONG_IMMUNITY_TRAIT "strongimmunity"

#define SLIP_REFLEX_TRAIT "slip_reflex"

#define ORGANICS	1
#define SYNTHETICS	2
