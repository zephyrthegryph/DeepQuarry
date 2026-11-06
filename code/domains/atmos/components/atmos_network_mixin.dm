// Shared network-lifecycle helpers for atmospherics machinery.
//
// binary, unary, and trinary all implement an identical pattern for
// network_expand: assign the relevant networkN var then add src to
// new_network.normal_members.
//
// IDEMPOTENCY CONTRACT
// --------------------
// network_expand must be safe to call multiple times with the same
// new_network.  The original code assigned networkN *before* checking
// whether src was already a member, so a re-entrant call (reachable when
// a device sits at the junction of two expansion walks) would redundantly
// overwrite a valid slot reference.
//
// Correct order:
//   a) bail early (return 0) if src is already in new_network.normal_members
//   b) assign the slot variable
//   c) append to normal_members
//
// This is now done inline in each base class's network_expand, matching
// the pattern in datum_pipeline.dm's /datum/pipeline/proc/network_expand.
//
// DESTROY CONTRACT
// ----------------
// For binary/unary/trinary the Destroy sequence must be:
//   1. disconnect all live nodes (which qdels the matching network)
//   2. null all node/network vars
//   3. chain ..()
// This ensures node.disconnect(src) runs against still-valid state before
// the GC and parent Destroy chain release atom references.
