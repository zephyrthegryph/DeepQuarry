// Emag as an interaction (doc/rewrite/systems.md section 13, runtime code/datums/sys/emag.dm).
//
//   DECLARE_EMAG(/obj/machinery/vending, PROC_REF(on_emag), "You short out the product lock.", null)
//   DECLARE_EMAG(/obj/machinery/suit_cycler, PROC_REF(on_emag), null, "The cycler has already been subverted.")
//   DECLARE_EMAG_REPEATABLE(/obj/item/shockpaddles, PROC_REF(on_emag), null)
//
// A type that reacts to a cryptographic sequencer declares it next to the type. The declaration
// is a per-type table (TYPE_TABLE `emag_decl`), inherited and overridable per subtype. It
// generates the "Emag" interaction (INTERACT_INSERT of /obj/item/card/emag): DECLARE_EMAG adds
// REQ_NOT_EMAGGED, so an emagged target refuses with the reason, and after a successful effect
// sets the `emagged` field (set_emagged() on machinery). DECLARE_EMAG_REPEATABLE has no gate and
// sets nothing (toggles, locks that can be broken by other means, multi-stage subversion).
//
// The effect is called on the target as PROC(remaining_charges, mob/user, obj/item/emag_source)
// and returns the emag uses it consumed (0 or null: tried, nothing used), or EMAG_DECLINED when
// this target doesn't take the emag after all (the card then hits it as an ordinary item).
// MSG, when not null, is shown to the user after a successful effect. ALREADY (DECLARE_EMAG only),
// when not null, replaces the generic refusal shown for an emag on an already emagged target.
// The effect of a gated declaration never sees an emagged target: it has no "already" guard.
//
// A subtype changes an inherited reaction by overriding the effect proc (or redeclaring).
// Anything that emags without a card (ion storms, the pAI toolkit, a blade slicing a lock)
// calls emag_target(target, charges, user, source). There is no emag_act() proc.

/// An emag effect's return: the target doesn't take the emag.
#define EMAG_DECLINED -1

/// Declares T's emag effect, gated on the target not being emagged yet.
#define DECLARE_EMAG(T, PROC, MSG, ALREADY) TYPE_TABLE(T, emag_decl, list(PROC, MSG, TRUE, ALREADY))
/// Declares T's emag effect with no gate: it can be applied again.
#define DECLARE_EMAG_REPEATABLE(T, PROC, MSG) TYPE_TABLE(T, emag_decl, list(PROC, MSG, FALSE, null))
/// The emag declaration row of instance I: list(proc, message, gated), or null.
#define EMAG_DECL(I) TYPE_TABLE_GET(I, emag_decl)

// Row indices.
#define EMAG_DECL_PROC 1
#define EMAG_DECL_MSG 2
#define EMAG_DECL_GATED 3
#define EMAG_DECL_ALREADY 4
