//Material Container Signals
/// Called from datum/component/material_container/proc/insert_item() : (item, primary_mat, mats_consumed, material_amount, context)
#define COMSIG_MATCONTAINER_ITEM_CONSUMED "matcontainer_item_consumed"
/// Called from datum/component/material_container/proc/retrieve_stack() : (new_stack, context)
#define COMSIG_MATCONTAINER_STACK_RETRIEVED "matcontainer_stack_retrieved"

//mat container signals but from the ore silo's perspective
