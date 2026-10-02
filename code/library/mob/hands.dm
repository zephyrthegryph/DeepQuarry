// The hand provider of the mobs that act with their hands in the world: a human (any species) and a cyborg. The engine has no hand provider of its own on
// /mob/living (code/engine/parts/provider.dm), so a mob type declares its own; the implicit req_capable() of a physical binding already refuses a
// stunned, restrained or dead actor, and the reach gate refuses a target out of arm's reach.

CAPABILITIES(/mob/living/carbon/human, hands())

CAPABILITIES(/mob/living/silicon/robot, hands())
