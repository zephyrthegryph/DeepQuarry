#if 0
ACTION(fall, turf/landing, mob/living/landed_on)
ACTION(move, turf/origin, turf/destination)
ACTION(hit, datum/damage_packet/packet)
ACTION(hit/projectile, obj/projectile/proj)
ACTION(hit/projectile/beam, num/energy)
ACTION(open, obj/item/door, FIXED, notice = /datum/notice/special)
ACTION(op, mob/actor, key)
ACTION(slot_check, QUERY, mob/wearer, mob/mover, datum/destination, slot_id, requirement_channel, list/query_options)
ACTION(speak, num/volume)
ACTION(equip, obj/item/item)
ACTION(thrown_hit, num/force)
ACTION(ghost/child, num/value)
ACTION(bad, mob/actor)
ACTION(badshape, @oops)
ACTION(badquery, QUERY, @oops)
ACTION(qwrong, QUERY, obj/nope)
ACTION(qfixed, QUERY, FIXED)
ACTION(fixed/child, num/value, FIXED)
/datum/notice/fell
    var/landing
/datum/notice/hit_extra
    var/packet
#endif
