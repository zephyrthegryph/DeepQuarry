// Legacy spellings and subtype paths retain compatibility; implementation lives in the engine.

/datum/om/behaviour/internal/edge_refresh
	parent_type = /datum/scheduled_behaviour/internal/edge_refresh
	abstract_type = /datum/om/behaviour/internal/edge_refresh

/proc/om_link(datum/source, datum/target, rel_path)
	return relation_link(arglist(args))

/proc/om_unlink(datum/source, datum/target, rel_path)
	return relation_unlink(arglist(args))

/proc/om_unlink_edge(datum/om/edge/edge, datum/deleting)
	return relation_unlink_edge(arglist(args))

/proc/om_edge_views_link(datum/om/relation/R, datum/source, datum/target)
	return relation_edge_views_link(arglist(args))

/proc/om_edge_views_unlink(datum/om/relation/R, datum/source, datum/target)
	return relation_edge_views_unlink(arglist(args))

/proc/om_leave(datum/member, rel_path, datum/other)
	return relation_leave(arglist(args))

/proc/om_drop_z(z)
	return relation_drop_z(arglist(args))

/proc/om_z_generation(z)
	return relation_z_generation(arglist(args))

/proc/om_z_generation_bump(z)
	return relation_z_generation_bump(arglist(args))

/proc/om_edge_from(datum/om/rec/rec, datum/om/relation/R, as_source)
	return relation_edge_from(arglist(args))

/proc/om_edge_setup(datum/om/edge/edge)
	return relation_edge_setup(arglist(args))

/proc/om_edge_teardown(datum/om/edge/edge)
	return relation_edge_teardown(arglist(args))

/proc/om_edge_refresh(datum/om/edge/edge)
	return relation_edge_refresh(arglist(args))

/proc/om_edge_structure_changed(datum/om/rec/rec, rel_id, bit)
	return relation_edge_structure_changed(arglist(args))

/proc/om_has_related(datum/om/rec/rec)
	return relation_has_related(arglist(args))

/proc/om_neighbours(datum/E, rel_id)
	return relation_neighbours(arglist(args))

/proc/om_rebuild_fwd(datum/om/rec/rec)
	return relation_rebuild_fwd(arglist(args))

/proc/om_install_path(datum/om/rec/rec, list/ids, depth, datum/at, mask, bid)
	return relation_install_path(arglist(args))

/proc/om_fwd_add(datum/om/rec/rec, datum/N, mask, bid, structural)
	return relation_fwd_add(arglist(args))

/proc/om_clear_fwd_out(datum/om/rec/rec)
	return relation_clear_fwd_out(arglist(args))

// Old interaction callers identify successful links by their legacy edge subtype.
/datum/relation_definition/make_edge()
	return new /datum/om/edge
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

/// The mob holding grab item src (the grab lives in the assailant's hand), or null. Was GRAB_ASSAILANT().
/obj/item/grab/proc/grab_assailant() as /mob/living/carbon/human
	return ishuman(loc) ? loc : null
