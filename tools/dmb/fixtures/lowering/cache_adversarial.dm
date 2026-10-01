/datum/cache_leaf
 var/value=7
 var/datum/cache_leaf/child
 proc/action(x)
  return value+x
/datum/cache_box
 var/list/values=list(7)
 var/datum/cache_leaf/child=new
/proc/change_values(datum/cache_box/box)
 box.values=list(11)
 return 1
/proc/change_child(datum/cache_box/box)
 box.child=new
 return 1
/proc/mutate_key(datum/cache_box/box)
 return change_values(box)
/proc/index_post_key(datum/cache_box/box)
 return box.values[mutate_key(box)]++
/proc/index_post_rhs(datum/cache_box/box)
 return box.values[1]++ + change_values(box)
/proc/index_assign_rhs(datum/cache_box/box)
 box.values[1] = change_values(box)
/proc/index_append_rhs(datum/cache_box/box)
 box.values[1] += change_values(box)
/proc/index_two_mutations(datum/cache_box/box)
 return box.values[1]++ + box.values[1]++
/proc/index_nested_post(list/list/values)
 return values[1][1]++
/proc/index_conditional_post(datum/cache_box/left,datum/cache_box/right,flag)
 return (flag ? left : right).values[1]++
/proc/field_post_receiver(datum/cache_box/box)
 return box.child.value++ + change_child(box)
/proc/field_append_receiver(datum/cache_box/box)
 box.child.value += change_child(box)
/proc/method_argument_post(datum/cache_box/box)
 return box.child.action(box.values[1]++)
/proc/method_argument_receiver(datum/cache_box/box)
 return box.child.action(change_child(box))
/proc/method_safe_argument_receiver(datum/cache_box/box)
 return box.child?.action(change_child(box))
/proc/index_post_nested_calls(datum/cache_box/box)
 return box.values[change_child(box) + mutate_key(box) - 1]++
/proc/get_box(datum/cache_box/box)
 return box
/proc/get_values(datum/cache_box/box)
 return box.values
/proc/index_call_receiver(datum/cache_box/box)
 return get_values(box)[mutate_key(box)]++
/proc/field_call_receiver(datum/cache_box/box)
 return get_box(box).child.value++
/proc/index_key_postfix(datum/cache_box/box)
 return box.values[box.values[1]++]++
/proc/index_double_rhs(datum/cache_box/box)
 box.values[mutate_key(box)] += change_values(box)
/proc/field_assign_rhs(datum/cache_box/box)
 box.child.value = change_child(box)
/proc/field_safe_postfix(datum/cache_box/box)
 return box?.child.value++
/proc/index_safe_postfix(datum/cache_box/box)
 return box?.values[mutate_key(box)]++
/proc/index_conditional_receiver_call(datum/cache_box/box,flag)
 return (flag ? get_values(box) : box.values)[mutate_key(box)]++
/proc/index_rhs_nested_postfix(datum/cache_box/box)
 box.values[1] = box.values[1]++
/proc/field_rhs_nested_postfix(datum/cache_box/box)
 box.child.value = box.child.value++
/proc/index_logical_rhs(datum/cache_box/box)
 box.values[1] ||= change_values(box)
/proc/index_logical_key_mutation(datum/cache_box/box)
 box.values[mutate_key(box)] &&= change_values(box)
/proc/field_logical_rhs(datum/cache_box/box)
 box.child.value ||= change_child(box)
/proc/field_safe_preinc(datum/cache_box/box)
 return ++box?.child.value
/proc/field_safe_postdec(datum/cache_box/box)
 return box?.child.value--
/proc/field_safe_statement(datum/cache_box/box)
 box?.child.value++
/proc/field_safe_append_rhs(datum/cache_box/box)
 box?.child.value += change_child(box)
/proc/method_outer_safe_argument_receiver(datum/cache_box/box)
 return box?.child.action(change_child(box))
/proc/field_inner_safe_postfix(datum/cache_box/box)
 return box.child?.value++
/proc/field_safe_rhs_safe(datum/cache_box/box,datum/cache_box/other)
 box?.child.value += other?.child.value
/proc/field_safe_indexed_owner(datum/cache_box/box)
 return box?.values[1].value++
/proc/field_safe_chain_assign(datum/cache_box/box)
 box?.child.value = change_child(box)
/proc/field_safe_nested_guard(datum/cache_box/box)
 return box?.child?.value++
/proc/field_safe_indexed_append(datum/cache_box/box)
 box?.values[1].value += change_values(box)
/proc/field_safe_indexed_preinc(datum/cache_box/box)
 return ++box?.values[1].value
/proc/field_safe_indexed_postdec(datum/cache_box/box)
 return box?.values[1].value--
/proc/field_safe_nested_append(datum/cache_box/box)
 box?.child?.value += change_child(box)
/proc/field_safe_indexed_append_field_rhs(datum/cache_box/box,datum/cache_box/other)
 box?.values[1].value += other.child.value
/proc/field_safe_indexed_nested_guard(datum/cache_box/box)
 return box?.values[1]?.value++
/proc/field_safe_indexed_conditional_key(datum/cache_box/box,flag)
 return box?.values[flag ? 1 : 2].value++
/proc/field_safe_indexed_mutating_key(datum/cache_box/box)
 box?.values[mutate_key(box)].value += change_values(box)
/proc/field_safe_rhs_safe_postfix(datum/cache_box/box,datum/cache_box/other)
 box?.child.value += other?.child.value++
/proc/field_safe_rhs_safe_prefix(datum/cache_box/box,datum/cache_box/other)
 box?.child.value += ++other?.child.value
/proc/field_safe_rhs_safe_compound(datum/cache_box/box,datum/cache_box/other)
 box?.child.value += (other?.child.value += 1)
/proc/field_safe_triple_postfix(datum/cache_box/box)
 return box?.child.child.value++
/proc/field_safe_triple_append(datum/cache_box/box,datum/cache_box/other)
 box?.child.child.value += other.child.value
/proc/field_safe_triple_nested(datum/cache_box/box)
 return box?.child?.child.value++
/proc/field_safe_rhs_safe_logical(datum/cache_box/box,datum/cache_box/other)
 box?.child.value += (other?.child.value ||= 1)
/proc/field_safe_indexed_logical(datum/cache_box/box)
 return (box?.values[1].value ||= change_values(box))
/proc/field_safe_indexed_logical_constant(datum/cache_box/box)
 return (box?.values[1].value &&= 3)
/proc/field_safe_nested_indexed_logical(datum/cache_box/box)
 return (box?.values[1]?.value ||= 3)
/proc/field_safe_assign_into(datum/cache_box/box)
 return (box?.child.value := 3)
/proc/field_safe_indexed_assign_into(datum/cache_box/box)
 return (box?.values[1].value := 3)
/proc/field_safe_direct_assign_into(datum/cache_leaf/box)
 return (box?.value := 3)
/proc/field_safe_nested_assign_into(datum/cache_box/box)
 return (box?.child?.value := 3)
/proc/field_safe_statement_assign_into(datum/cache_box/box)
 box?.child.value := 3
/proc/field_safe_direct_assign_into_conditional(datum/cache_leaf/box,flag)
 return (box?.value := (flag ? 3 : 4))
/proc/field_safe_indexed_assign_into_conditional(datum/cache_box/box,flag)
 return (box?.values[flag ? 1 : 2].value := (flag ? 3 : 4))
