// The providers of the mobs that act in the world: a human (any species) has hands; a cyborg has its chassis manipulators, its selected gripper
// (robot_simple_items.dm: preferred, and what it carries is the held item) and its interface for the remote controls (remote_interface(),
// library/mob/silicon.dm). The engine has no hand provider of its own on /mob/living (code/engine/parts/provider.dm), so a mob
// type declares its own; the implicit req_capable() of a physical binding already refuses a stunned, restrained or dead actor, and the reach gate
// refuses a target out of arm's reach.

/mob/living/carbon/human/starting_nutrition() // a human starts with 200-400 (was a rolls() entry)
	return rand(200, 400)

CAPABILITIES_PART(/mob/living/carbon/human, human_hands)
	hands()
