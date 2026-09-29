// Relation views (doc/rewrite/ownership.md): every non-owning reference to a dying entity is
// cleared by phase 4 without an on_destroy() body. Replaces the old BACK_VIA / LIST_BACK /
// DROP / QUEUE bookkeeping-kind test: members naming the owner, list memberships, two-hop
// references and one-sided views all clear, and unrelated entries survive.

/// The object whose destruction is tested.
/datum/dq_decl_kinds_owner
	var/list/members
	var/datum/dq_decl_kinds_hub/hub

/// A member of the owner's list, naming it back two ways.
/datum/dq_decl_kinds_member
	var/datum/dq_decl_kinds_owner/back
	var/list/names

/// Reached through the owner's hub; names the owner in `slot`.
/datum/dq_decl_kinds_hub
	var/datum/dq_decl_kinds_owner/slot
	var/datum/dq_decl_kinds_inner/inner

/// Two hops away; holds the owner in a list.
/datum/dq_decl_kinds_inner
	var/list/owners

REL_PAIR_LIST(/datum/dq_decl_kinds_owner, members, back)
REL_PAIR(/datum/dq_decl_kinds_member, back, members)
REL_LIST(/datum/dq_decl_kinds_member, names)
REL(/datum/dq_decl_kinds_owner, hub)
REL(/datum/dq_decl_kinds_hub, slot)
REL(/datum/dq_decl_kinds_hub, inner)
REL_LIST(/datum/dq_decl_kinds_inner, owners)

/datum/unit_test/dq_lifecycle_declared_kinds

/datum/unit_test/dq_lifecycle_declared_kinds/Run()
	var/datum/dq_decl_kinds_owner/owner = new
	var/datum/dq_decl_kinds_owner/other = new
	var/datum/dq_decl_kinds_member/first = new
	var/datum/dq_decl_kinds_member/second = new
	var/datum/dq_decl_kinds_hub/hub = new
	var/datum/dq_decl_kinds_inner/inner = new

	rel_add(owner, "members", first)
	rel_set(second, "back", owner)
	TEST_ASSERT_EQUAL(first.back, owner, "REL_PAIR_LIST sets the member's partner side")
	TEST_ASSERT((second in owner.members), "REL_PAIR sets the owner's list side")
	rel_add(first, "names", owner)
	rel_add(first, "names", other)
	rel_set(hub, "slot", owner)
	rel_set(hub, "inner", inner)
	rel_set(owner, "hub", hub)
	rel_add(inner, "owners", owner)
	rel_add(inner, "owners", other)

	qdel(owner)

	TEST_ASSERT_NULL(first.back, "a pair member's view back clears")
	TEST_ASSERT_NULL(second.back, "a pair member set from its own side clears")
	TEST_ASSERT(!(owner in first.names), "the dying entity leaves a member's list view")
	TEST_ASSERT((other in first.names), "a list view keeps its other entries")
	TEST_ASSERT_NULL(owner.members, "the owner's own list view drops")
	TEST_ASSERT_NULL(hub.slot, "a one-sided view naming the entity clears")
	TEST_ASSERT(!(owner in inner.owners), "a view two hops away clears")
	TEST_ASSERT((other in inner.owners), "the two-hop list keeps its other entries")
	TEST_ASSERT_EQUAL(hub.inner, inner, "views not naming the dying entity are untouched")

	qdel(first)
	qdel(second)
	qdel(hub)
	qdel(inner)
	qdel(other)
