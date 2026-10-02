// Test-only aliases for the E0 proofs (doc/rewrite/engine_contracts.md, "Name clashes"). Six of the final API's public names are
// live on master with other shapes (perform_op, action_options, screentip_for, grant, revoke, granted), so E0's stubs carry an e0_
// prefix. Between this file and dq_e0_unalias.dm the final names mean the stubs, so the proofs read exactly as section 19
// writes them. The include list keeps both files directly around the proofs: nothing else sees these macros.
// Each engine deletes its aliases, with the legacy proc it replaces, when it lands (E1: grant, revoke, granted; E2: perform_op,
// action_options, screentip_for).
#define perform_op(args...) e0_perform_op(args)
#define action_options(args...) e0_action_options(args)
#define screentip_for(args...) e0_screentip_for(args)
#define grant(args...) e0_grant(args)
#define revoke(args...) e0_revoke(args)
#define granted(args...) e0_granted(args)
