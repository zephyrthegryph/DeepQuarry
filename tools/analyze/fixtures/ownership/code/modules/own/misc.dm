// callback, handle and removed.
/obj/holder/proc/callbacks()
	var/datum/callback/cb = CALLBACK(src, PROC_REF(callbacks))
	CALLBACK(src, PROC_REF(callbacks)) // ALLOW(ownership): the fixture keeps this CALLBACK on purpose
	// ALLOW(ownership): the comment line above keeps the next CALLBACK
	var/datum/callback/cb2 = CALLBACK(src, PROC_REF(callbacks))
	// CALLBACK(src, PROC_REF(callbacks)) in a comment
	var/s = "CALLBACK(src, x)"
	var/datum/callback/cb3 = CALLBACKS(src)
	var/datum/callback/cb4 = MYCALLBACK(src)

/obj/holder/proc/handles(atom/A)
	var/h = om_handle(A)
	var/r = om_resolve(h)
	var/k = om_handle_of(A)
	var/i = om_handle_is(h, A)
	var/all = om_resolve_all(list(h))
	var/m = om_handled(A)
	var/n = custom_om_handle(A)
	var/ok = om_handle(A) // ALLOW(ownership): the fixture keeps this handle call on purpose
	// ALLOW(ownership): the comment line above keeps the next handle call
	var/ok2 = om_resolve(h)
	// om_handle(A) in a comment
	var/s = "om_handle(A)"

/obj/holder
	var/target_handle
	var/list/obj/item/stuff_handle
	var/kept_handle // ALLOW(ownership): the fixture keeps this handle var on purpose
	// ALLOW(ownership): the comment line above keeps the next handle var
	var/kept_handle_two
	var/handle_not
	var/some_handlebar
	var/tmp/static/other_handle
	VAR_PRIVATE/secret_handle

/obj/holder/var/abs_handle
/obj/holder/var/obj/item/abs_item_handle
/obj/holder/var/ok_ahandle // ALLOW(ownership): the fixture keeps this absolute handle var

/obj/holder/proc/local_handle()
	var/local_handle = 1
	var/obj/holder/list/other_handle = list()
	return local_handle

/obj/holder/proc/removed_forms()
	DECLARE_REF(thing)
	OM_STATIC_TYPE(thing)
	var/k = REFKIND_STRONG
	link_set(src, thing)
	link_clear(src)
	link_backlist_add(src, thing)
	WEAK_LIST_ADD(x, y)
	weak_list_live(x)
	var/c = DuplicateObject(src)
	var/t = dq_lifecycle_link_table
	declared_refs()
	own_declare(src)
	OWN(thing)
	OWN_POLICY(thing)
	SHARED(thing)
	PROTO(thing)
	REL(thing)
	REL_LIST(thing)
	REL_KEYED(thing)
	FORWARD_STATE(thing)
	POOL_RESET(thing)
	DECLARE_REF(thing) // ALLOW(ownership): the fixture keeps this removed form on purpose
	// ALLOW(ownership): the comment line above keeps the next removed form
	OWN(thing)
	// OWN(thing) in a comment
	var/s = "DECLARE_REF(thing)"
	var/not_removed = OWNER(thing)
	var/also_not = OWN
	var/x = NOTOWN(thing)
	DECLARE_REF(a) DuplicateObject(b)

#define OWN_MACRO OWN(x)
#define REF_MACRO DECLARE_REF(x)
