// Emag result (the emag capability: code/library/access/emag.dm; emag_target(): code/datums/sys/emag.dm).
// A type declares `emag(then(PROC_REF(on_emag)))` in its CAPABILITIES block; anything that emags without a card
// (ion storms, the pAI toolkit, a blade slicing a lock) calls emag_target(target, charges, user, source).

/// emag_target()'s return: the target doesn't take the emag.
#define EMAG_DECLINED -1
