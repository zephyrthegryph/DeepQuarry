// Surgery framework for the DQ medical book.
//
// Each /datum/dq_surgery records a complete clinical procedure as data:
// name, description, the body region it's performed on, the ordered
// steps (rendered as prose for the book reader), tools needed, and
// the list of conditions it treats.
//
// Surgeries integrate with the cascading-condition system in two
// directions:
//
//   - Book side: the Surgery tab walks every /datum/dq_surgery subtype
//     and renders one entry per procedure, with cross-links to the
//     conditions it treats.
//   - Runtime side: when a player completes an upstream surgery_step
//     that matches one of our /datum/dq_surgery records (matched by
//     "completion step" typepath), every active instance of that
//     surgery's `treats` conditions is cleared from the patient.
//
// Authoring style: one subtype per procedure, prose-style steps for the
// book reader (no game-mechanical jargon), `treats` listing the
// condition typepaths the procedure cures.


/datum/dq_surgery
	/// Display name in the book.
	var/name = "surgery"
	/// One-sentence clinical overview.
	var/description = ""
	/// Reference-book category for grouping.
	/// "Trauma" / "Bone" / "Vascular" / "Chest" / "Limb" / "Soft Tissue"
	/// / "Special".
	var/category = "Trauma"
	/// Optional finer-grained grouping rendered as a grey subheader.
	var/subcategory
	/// Body region this is performed on, in plain English. Just text;
	/// the runtime doesn't enforce it (upstream surgery_step does).
	var/body_region = ""
	/// Ordered list of prose strings describing the steps a surgeon
	/// takes. Each item is one step, e.g. "Make an incision below the
	/// ribs." The book renders these as a numbered list.
	var/list/steps
	/// Tools the surgeon needs (display strings, not typepaths).
	var/list/tools
	/// list of /datum/medical_issue/condition typepaths that this
	/// surgery, when completed, cures on the patient.
	var/list/treats
	/// Upstream /datum/surgery_step typepath whose successful end()
	/// signals our cure hook. The dispatcher in
	/// code/modules/medical/surgery/integration.dm watches
	/// for this step finishing on a patient and clears the matching
	/// `treats` conditions. Null = procedure isn't yet hooked to a
	/// real upstream step; treats listing is informational only.
	var/completion_step
	/// How much severity the completing step drops from each matching
	/// condition. Default 100 = full cure. Lower values produce
	/// graduated effects — e.g. a craniotomy that drops 60 severity
	/// will bring Critical brain damage down to Significant rather
	/// than instantly clearing it. The condition's normal
	/// progression then takes over.
	var/cure_severity = 100
	/// Which internal organs the surgery actually repairs, as a list of
	// / O_* tags. Read by the on /datum/surgery_step/internal/fix_organ
	/// to gate which organs get their damage zeroed when the step finishes
	/// — upstream behaviour zeros every internal organ in the zone, which
	/// is far too generous (a craniotomy would also fix every other organ
	/// in the head). A surgery that doesn't share fix_organ can leave this
	/// null.
	var/list/heals_organs
