/*
'Aura' effects are semi-permanent, in that they do not have a set duration, but will end if out of range of the 'source' of the aura.
Note: The source is the origin passed to apply_body_effect(), and if not specified, it is assumed the mob is the source,
making it never end, which is likely not what you want.
*/

/datum/body_effect/aura
	stacks = MODIFIER_STACK_FORBID
	tick_interval = 2 SECONDS
	aura_max_distance = 5 // If more than this many tiles away from the source, the effect ends next tick.
