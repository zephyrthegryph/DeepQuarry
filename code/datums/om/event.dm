// Object-model core: typed events (doc/rewrite/object_model_core.md section G).
//
// om_emit(E, new /datum/om/event/x(...)) delivers to every started behaviour
// on E that handles /datum/om/event/x or any of its ancestors (the boot
// table flattens inheritance, so a subtype event is never missed), in run
// order, by double dispatch: event.dispatch(B, E) calls B.on_x(E, event).
//
// Re-entrancy: an ordinary event emitted while another is being delivered
// is queued (coalesced per entity and type unless coalesce = FALSE) and
// delivered right after, in the same call. A before_* event is synchronous
// so it can be vetoed. The re-entrancy guard is keyed by event type: a
// before_* event may emit a DIFFERENT before_* event on the same entity (a
// before_move asking before_drop), but re-emitting the SAME type while it is
// being delivered, or nesting deeper than OM_VETO_DEPTH_MAX, is an error,
// reported loudly and answered with a veto, never silently dropped.





