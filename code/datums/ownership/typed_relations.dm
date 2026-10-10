// ---------------------------------------------------------------- typed relation accessors
//
// One proc per relation end, typed so reads chain (M.buckled_to()?.loc). They
// replaced the BUCKLED()/PULLING()/... accessor macros; tools/ci/check_ratchets.sh
// bans the macros and bare link_of() outside the relation core.

/// What the mob is buckled to, or null (the sparse link LK_BUCKLED_TO, links() in CAPABILITIES(/atom/movable)). Was BUCKLED().
/mob/proc/buckled_to() as /atom/movable
	return link_get(src, LK_BUCKLED_TO)

/// The mobs buckled to it: a fresh list, never null. Was BUCKLED_MOBS().
/atom/movable/proc/buckled_mob_list() as /list
	return link_list(src, LK_BUCKLED_MOBS)

/// What the mob pulls, or null (LK_PULLING). Was PULLING().
/mob/proc/pulling_target() as /atom/movable
	return link_get(src, LK_PULLING)

/// A wheelchair pulls too (relaymove()); declared here rather than on /atom/movable.
/obj/structure/bed/chair/wheelchair/proc/pulling_target() as /atom/movable
	return link_get(src, LK_PULLING)

/// What pulls it, or null (LK_PULLED_BY). Was PULLED_BY().
/atom/movable/proc/pulled_by_mob() as /mob/living
	return link_get(src, LK_PULLED_BY)

/// The grabs holding the mob: a fresh list, never null. Was GRABBED_BY().
/mob/proc/grabbed_by_list() as /list
	return link_list(src, LK_GRABBED_BY)

/// The mob the grab holds, or null (LK_GRABBING). Was GRAB_TARGET().
/obj/item/grab/proc/grab_target() as /mob/living
	return link_get(src, LK_GRABBING)

/// What the atom orbits, or null (LK_ORBITING). Was ORBIT_TARGET().
/atom/movable/proc/orbit_target() as /atom
	return link_get(src, LK_ORBITING)

/// The atoms orbiting it: a fresh list, never null (LK_ORBITERS). Was ORBITERS().
/atom/proc/orbiter_list() as /list
	return link_list(src, LK_ORBITERS)

/// The mob holding grab item src (the grab lives in the assailant's hand), or null. Was GRAB_ASSAILANT().
/obj/item/grab/proc/grab_assailant() as /mob/living/carbon/human
	return ishuman(loc) ? loc : null
