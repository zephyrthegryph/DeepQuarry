// The slot capability's constants (code/datums/capabilities/slot.dm).

/// Eject inputs (slot(..., eject_via = ...)): alt-click, the default.
#define SLOT_VIA_ALT (1<<0)
/// An empty-hand click ejects.
#define SLOT_VIA_HAND (1<<1)
/// Using the host in hand (its self-use) ejects.
#define SLOT_VIA_USE (1<<2)
/// An object verb in the Menu ejects.
#define SLOT_VIA_VERB (1<<3)
/// No generated eject (the host takes the item out itself, or never).
#define SLOT_VIA_NONE 0

/// A full slot (slot(..., when_full = ...)) refuses with full_msg: the default.
#define SLOT_FULL_REFUSE 0
/// A full slot declines, so the host's next interaction for the item answers (a second slot for the
/// same type fills next).
#define SLOT_FULL_PASS 1
/// A full slot swaps: the item in it drops (its slot capability's ejected() runs) and the new one goes in.
#define SLOT_FULL_SWAP 2

/// slot capability refusal() answer: refuse without a message (the hook already told the actor).
#define SLOT_REFUSED_SILENT "__silent"
/// slot capability refusal() answer: decline without using the input, so the host's next interaction for the
/// item answers.
#define SLOT_REFUSED_PASS "__pass"
