// Bridges incoming injuries into the brain's notify pipeline.
//
// Every harm to a living mob goes through injure() (doc/body_architecture.md
// §2), which sends COMSIG_LIVING_INJURED after the injury lands. The brain
// listens for it (registered in /datum/ai_brain/New), so it learns of every
// hit regardless of the source (projectile, melee, generic attack,
// environmental). Mobs without a brain pay nothing.

/datum/ai_brain/proc/on_holder_injured(mob/living/source_mob, kind, applied, zone, atom/source, flags)
	SIGNAL_HANDLER
	if(applied <= 0 || QDELETED(holder))
		return
	INVOKE_ASYNC(holder, TYPE_PROC_REF(/mob/living, dq_notify_damage), applied, kind, dq_resolve_attacker(source))

/// Works out who is responsible for an injury source: a projectile's firer,
/// the mob wielding a weapon, or the mob itself.
/proc/dq_resolve_attacker(atom/source)
	if(!istype(source))
		return null
	if(istype(source, /obj/item/projectile))
		var/obj/item/projectile/P = source
		return P.firer || P
	if(ismob(source))
		return source
	if(ismob(source.loc))
		return source.loc
	return source
