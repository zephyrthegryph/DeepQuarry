// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// Material Container Signals Called from datum/component/material_container/proc/insert_item() : (item, primary_mat, mats_consumed, material_amount, context)
ACTION(matcontainer_item_consumed, item, primary_mat, mats_consumed, material_amount, context, FIXED, notice = /datum/notice/matcontainer_item_consumed)

/// Called from datum/component/material_container/proc/retrieve_stack() : (new_stack, context)
ACTION(matcontainer_stack_retrieved, new_stack, context, FIXED, notice = /datum/notice/matcontainer_stack_retrieved)
