// /datum/component/container_item

//NON TG Signals:
///from /obj/structure/closet/close()
#define COMSIG_CLOSET_CLOSED "closet_closed"

// Containment ledger (code/datums/containment/). Sent on the holder.
///from the ledger before a thing enters one of the holder's slots: (atom/movable/thing, slot_id, mob/actor)
#define COMSIG_SLOT_PRE_INSERT "slot_pre_insert"
///from the ledger before a thing leaves one of the holder's slots: (atom/movable/thing, slot_id, mob/actor)
#define COMSIG_SLOT_PRE_REMOVE "slot_pre_remove"
	/// Return from either pre signal to refuse the move.
	#define COMPONENT_SLOT_BLOCK (1<<0)
///from the ledger after a thing entered one of the holder's slots: (atom/movable/thing, slot_id)
#define COMSIG_SLOT_INSERTED "slot_inserted"
///from the ledger after a thing left one of the holder's slots: (atom/movable/thing, slot_id)
#define COMSIG_SLOT_REMOVED "slot_removed"
