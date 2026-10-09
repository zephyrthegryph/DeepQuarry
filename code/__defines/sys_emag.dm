// Emag (runtime code/datums/sys/emag.dm). A type that reacts to a cryptographic sequencer declares the emag() capability in its CAPABILITIES
// block (code/library/access/emag.dm); anything that emags without a card (ion storms, the pAI toolkit, a blade slicing a lock) calls
// emag_target(target, charges, user, source), which runs the target's "emag.subvert" op.

/// emag_target()'s return: the target doesn't take the emag.
#define EMAG_DECLINED -1
