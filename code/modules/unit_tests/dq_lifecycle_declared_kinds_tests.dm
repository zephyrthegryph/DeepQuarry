// DECLARE_REF(..., BACK_VIA), DECLARE_REF(..., LIST_BACK), DECLARE_REF(..., DROP) and DECLARE_REF(..., QUEUE) (doc/rewrite/lifecycle.md §4.2):
// the bookkeeping kinds phase 4 clears without an on_destroy() body.

GLOBAL_LIST_EMPTY(dq_decl_kinds_queue)

/proc/dq_decl_kinds_queue()
	return GLOB.dq_decl_kinds_queue

/// The object whose destruction is tested.
/datum/dq_decl_kinds_owner
	var/list/members
	var/list/scratch
	var/hub_handle
	var/queued = FALSE


/// A member of the owner's list, naming it back three ways.
/datum/dq_decl_kinds_member
	var/back
	var/back_handle
	var/list/names

/// Reached through the owner's hub_handle; names the owner in `slot`.
/datum/dq_decl_kinds_hub
	var/slot
	var/inner_handle

/// Two hops away; holds the owner (by handle) in a list.
/datum/dq_decl_kinds_inner
	var/list/owners

/datum/unit_test/dq_lifecycle_declared_kinds

/datum/unit_test/dq_lifecycle_declared_kinds/Run()
	var/datum/dq_decl_kinds_owner/owner = new
	var/datum/dq_decl_kinds_member/by_ref = new
	var/datum/dq_decl_kinds_member/by_handle = new
	var/datum/dq_decl_kinds_hub/hub = new
	var/datum/dq_decl_kinds_inner/inner = new
	var/list/shared = list("kept")

	var/owner_h = om_handle(owner)
	by_ref.back = owner
	by_ref.names = list(owner, "other") // ALLOW(object_keyed_lists): test fixture for DECLARE_REF(..., LIST_BACK)
	by_handle.back_handle = owner_h
	owner.members = list(by_ref, om_handle(by_handle)) // ALLOW(object_keyed_lists): test fixture for DECLARE_REF(..., LIST_BACK)
	owner.scratch = shared
	hub.slot = owner
	hub.inner_handle = om_handle(inner)
	owner.hub_handle = om_handle(hub)
	inner.owners = list(owner_h, "someone") // ALLOW(object_keyed_lists): test fixture for DECLARE_REF(..., BACK_VIA)
	owner.queued = TRUE
	GLOB.dq_decl_kinds_queue += owner // ALLOW(object_keyed_lists): test fixture for DECLARE_REF(..., QUEUE)

	qdel(owner)

	TEST_ASSERT_NULL(by_ref.back, "DECLARE_REF(..., LIST_BACK) nulls a member's reference back")
	TEST_ASSERT(!(owner in by_ref.names), "DECLARE_REF(..., LIST_BACK) removes us from a member's list")
	TEST_ASSERT(("other" in by_ref.names), "DECLARE_REF(..., LIST_BACK) leaves the member's other entries")
	TEST_ASSERT_NULL(by_handle.back_handle, "DECLARE_REF(..., LIST_BACK) reaches a member held by handle and clears its handle back")
	TEST_ASSERT_NULL(owner.members, "DECLARE_REF(..., LIST_BACK) drops the owner's list")
	TEST_ASSERT_NULL(owner.scratch, "DECLARE_REF(..., DROP) nulls the var")
	TEST_ASSERT_EQUAL(length(shared), 1, "DECLARE_REF(..., DROP) leaves a shared list's contents alone")
	TEST_ASSERT_NULL(hub.slot, "DECLARE_REF(..., BACK_VIA) nulls the partner's var naming us")
	TEST_ASSERT(!(owner_h in inner.owners), "DECLARE_REF(..., BACK_VIA) follows a two-hop path and removes our handle from a list")
	TEST_ASSERT(("someone" in inner.owners), "DECLARE_REF(..., BACK_VIA) leaves the list's other entries")
	TEST_ASSERT(!(owner in GLOB.dq_decl_kinds_queue), "DECLARE_REF(..., QUEUE) leaves the queue when flagged")

	// Unflagged: the queue isn't touched.
	var/datum/dq_decl_kinds_owner/idle = new
	GLOB.dq_decl_kinds_queue += idle // ALLOW(object_keyed_lists): test fixture for DECLARE_REF(..., QUEUE)
	qdel(idle)
	TEST_ASSERT((idle in GLOB.dq_decl_kinds_queue), "DECLARE_REF(..., QUEUE) skips an owner whose flag is clear")
	GLOB.dq_decl_kinds_queue.Cut()

	qdel(by_ref)
	qdel(by_handle)
	qdel(hub)
	qdel(inner)
