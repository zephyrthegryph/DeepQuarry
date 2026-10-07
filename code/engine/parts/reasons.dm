// Shared refusal messages used by native operation requirements and legacy adapters.

/// The reason of req(..., silent = TRUE): no text, so the refused actor is told nothing.
MSG_DEF_SELF(req_silent, "")
MSG_DEF_SELF(req_refused, "%DETAIL%")
MSG_DEF_SELF(req_hand_full, "You need an empty hand for that.")
MSG_DEF_SELF(req_no_provider, "You have nothing to do that with.")
MSG_DEF_SELF(req_no_route, "You can't do that that way.")
MSG_DEF_SELF(req_out_of_reach, "You can't reach it.")
MSG_DEF_SELF(req_not_capable, "You can't do that right now.")
MSG_DEF_SELF(req_wrong_item, "That isn't the right thing to use.")
MSG_DEF_SELF(req_wrong_state, "It isn't in the right state for that.")
MSG_DEF_SELF(req_no_access, "Access denied.")
MSG_DEF_SELF(req_wire_cut, "A wire it needs is cut.")
MSG_DEF_SELF(req_no_part, "It is missing a part.")
MSG_DEF_SELF(req_forbidden, "Not while things are as they are.")
MSG_DEF_SELF(req_sealed, "Something in the way stops you.")
MSG_DEF_SELF(req_cancelled, "You stop.")
