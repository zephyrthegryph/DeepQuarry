// ---------------------------------------------------------------- typed relation accessors
//
// One proc per relation end, typed so reads chain (M.buckled_to()?.loc). They
// replaced the BUCKLED()/PULLING()/... accessor macros; tools/ci/check_ratchets.sh
// bans the macros and bare link_of() outside code/datums/om.

/// Was BUCKLED().
/mob/proc/buckled_to() as /atom/movable
	return link_of(src, /datum/om/relation/buckled_to)

/// Was BUCKLED_MOBS().
/atom/movable/proc/buckled_mob_list() as /list
	return linked_to(src, /datum/om/relation/buckled_to)

/// Was PULLING().
/mob/proc/pulling_target() as /atom/movable
	return link_of(src, /datum/om/relation/pulling)

/// A wheelchair pulls too (relaymove()); declared here rather than on /atom/movable.
/obj/structure/bed/chair/wheelchair/proc/pulling_target() as /atom/movable
	return link_of(src, /datum/om/relation/pulling)

/// Was PULLED_BY().
/atom/movable/proc/pulled_by_mob() as /mob/living
	return link_source_of(src, /datum/om/relation/pulling)

/// Was GRABBED_BY().
/mob/proc/grabbed_by_list() as /list
	return linked_to(src, /datum/om/relation/grabbing)

/// Was EYE_OWNER().
/mob/observer/eye/proc/eye_owner() as /mob
	return link_of(src, /datum/om/relation/eye_of)

/// Was EYES_OF().
/mob/living/proc/eyes_list() as /list
	return linked_to(src, /datum/om/relation/eye_of)

/// Was ACTIVE_EYE().
/mob/proc/active_eye() as /mob/observer/eye
	return link_of(src, /datum/om/relation/active_eye)

/// Was GRAB_TARGET().
/obj/item/grab/proc/grab_target() as /mob/living
	return link_of(src, /datum/om/relation/grabbing)

/// Was ORBIT_TARGET().
/atom/movable/proc/orbit_target() as /atom/movable
	return link_of(src, /datum/om/relation/orbiting)

/// Was ORBITERS().
/atom/movable/proc/orbiter_list() as /list
	return linked_to(src, /datum/om/relation/orbiting)

/// Was LEASH_PET().
/obj/item/leash/proc/leash_pet() as /mob/living
	return link_source_of(src, /datum/om/relation/leashed_to)

/// Was LEASH_MASTER().
/obj/item/leash/proc/leash_master() as /mob/living
	return link_of(src, /datum/om/relation/leash_held_by)

/// Was LEASH_OF().
/mob/living/proc/leash_item() as /obj/item
	return link_of(src, /datum/om/relation/leashed_to)

/// Was FOLLOWING().
/mob/observer/proc/following_target() as /atom/movable
	return link_of(src, /datum/om/relation/following)

/// Was FOLLOWERS().
/mob/proc/follower_list() as /list
	return linked_to(src, /datum/om/relation/following)

/// Was BORER_HOST().
/mob/living/simple_mob/animal/borer/proc/borer_host() as /mob/living/carbon/human
	return link_of(src, /datum/om/relation/host_of)

/// Was BORER_OF().
/mob/living/carbon/human/proc/borer_of() as /mob/living/simple_mob/animal/borer
	return link_source_of(src, /datum/om/relation/host_of)

/// Was BS_TX_TARGET().
/obj/item/radio/proc/bs_tx_target() as /obj/machinery/telecomms
	return link_of(src, /datum/om/relation/bluespace_tx_to)

/// Was BS_TX_RADIOS().
/obj/machinery/telecomms/proc/bs_tx_radios() as /list
	return linked_to(src, /datum/om/relation/bluespace_tx_to)

/// Was BS_RX_SOURCE().
/obj/item/radio/proc/bs_rx_source() as /obj/machinery/telecomms
	return link_of(src, /datum/om/relation/bluespace_rx_from)

/// Was BS_RX_RADIOS().
/obj/machinery/telecomms/proc/bs_rx_radios() as /list
	return linked_to(src, /datum/om/relation/bluespace_rx_from)

/// Was GRIPPER_HELD().
/obj/item/gripper/proc/gripper_held() as /obj/item
	return link_of(src, /datum/om/relation/gripper_holding)

/// Was UAV_MASTERS().
/obj/item/uav/proc/uav_masters() as /list
	return linked_to(src, /datum/om/relation/uav_master)

/// The mob holding grab item src (the grab lives in the assailant's hand), or null. Was GRAB_ASSAILANT().
/obj/item/grab/proc/grab_assailant() as /mob/living/carbon/human
	return ishuman(loc) ? loc : null
