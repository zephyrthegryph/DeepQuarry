/**
 * Holder semantics (doc/rewrite/grants.md): a grant's source decides who keeps it
 * when a mind moves body. A grant from an organ, implant or item follows the BODY -
 * it lives on whatever mob physically holds that source, so it needs no help; mind
 * transfer never touches it. A grant from the mind itself (learned languages,
 * species memory, ...) needs to move WITH the mind, onto whatever body it's
 * currently piloting - that's what transfer_grants() is for.
 *
 * Called from /datum/mind/proc/transfer_to() (code/datums/mind.dm) on every mind
 * move (body swap, resleeve, a fresh sleeve for a new character): grants whose
 * source is the mind itself (`filter` = /datum/mind) move from the old body to the
 * new one. A source that grants through some OTHER mind-owned datum (an antag
 * holder, a spell datum, ...) can pass its own type as `filter` from its own
 * transfer hook, or extend this call site if it always needs to ride along with
 * every mind move.
 */
/proc/transfer_grants(mob/from, mob/to, filter)
	if(!from || !to || from == to || !from.grants)
		return
	var/list/to_move = list() // list(list(kind, id, source))
	for(var/kind in from.grants)
		var/list/by_id = from.grants[kind]
		for(var/id in by_id)
			for(var/datum/source as anything in by_id[id])
				if(!filter || istype(source, filter))
					to_move += list(list(kind, id, source))
	for(var/list/entry in to_move)
		revoke(from, entry[1], entry[2], entry[3])
		grant(to, entry[1], entry[2], entry[3])
