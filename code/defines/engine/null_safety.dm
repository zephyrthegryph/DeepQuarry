// Sentinels for "unset" (unified plan sec 2.16, "No nulls in APIs"). A value that can be
// absent has a defined stand-in, so callers never branch on null. Others live beside their
// owners: NIGHTSHIFT_AUTO (apc.dm).

/// "Not on any z-level": an atom in nullspace, in a container with no turf, or a z that was never set.
#define NO_Z 0
