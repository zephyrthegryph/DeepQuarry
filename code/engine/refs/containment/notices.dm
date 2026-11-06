/// From the ledger after a thing entered one of the holder's slots: (atom/movable/thing, slot_id)
ACTION(slot_inserted, atom/movable/thing, slot_id, FIXED, notice = /datum/notice/slot_inserted)

/// From the ledger after a thing left one of the holder's slots: (atom/movable/thing, slot_id)
ACTION(slot_removed, atom/movable/thing, slot_id, FIXED, notice = /datum/notice/slot_removed)
