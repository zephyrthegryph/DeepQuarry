# Pinned client intrinsic presence

BYOND 516.1687 compile-only control, hidden window and 60-second timeout; no
DreamDaemon. The client is explicitly reparented to /datum, matching DeepQuarry.
preload_rsc, control_freak and show_verb_panel each accept an authored default
assignment and exact src.field reads/writes in a procedure (0 errors/warnings).

Only preload_rsc was missing from the pinned catalog. This control certifies its
positive instance-field presence/storage. It does not certify a declared type,
source modifier flags, default value, or runtime behavioral effects.

A source inspection of DeepQuarry's ordinary /client type-block assignments
found these three fields and parent_type; user-defined variables are declared
separately. Existing control_freak/show_verb_panel entries remain unchanged.
