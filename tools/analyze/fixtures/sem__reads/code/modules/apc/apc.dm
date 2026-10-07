// An APC whose declaration names handlers: clean ones and one seeded violation per reads rule.
/obj/machinery/apc
	name = "apc"
	var/obj/item/cell/cell
	var/obj/item/cell/spare
	var/on = FALSE
	var/mode = 0
	var/limit = 30
	var/frozen_setting = 5
	var/secrets = 0
	var/pad_count = 0

TRACKED(/obj/machinery/apc, on)
REL(/obj/machinery/apc, cell)

CAPABILITIES(/obj/machinery/apc,
	when(PROC_REF(cell_low)),
	when(PROC_REF(bad_global)),
	when(PROC_REF(uses_mode)),
	when(PROC_REF(uses_const)),
	when(PROC_REF(dynamic)),
	when(PROC_REF(via_spare)),
	when(PROC_REF(bad_field)),
	when(PROC_REF(accessor_user)),
	when(PROC_REF(night_user)),
	when(PROC_REF(pure_user)),
	when(PROC_REF(two_arg_user)),
	when(PROC_REF(calls_ctx_free)),
	needs(PROC_REF(actor_busy)),
	needs(PROC_REF(held_charge)),
	when(PROC_REF(once_user)),
	when(PROC_REF(loops)))

/// The cell relation hop and C.charge are generated through READS_FROM.
/obj/machinery/apc/proc/cell_low(datum/act/eval/A)
	return cell_charge_percent(cell) < limit

/obj/machinery/apc/proc/bad_global(datum/act/eval/A)
	return unannotated_helper(cell) > 3

/obj/machinery/apc/proc/uses_mode(datum/act/eval/A)
	return mode == 2

/obj/machinery/apc/proc/uses_const(datum/act/eval/A)
	return frozen_setting > 3

/obj/machinery/apc/proc/dynamic(datum/act/eval/A)
	return vars["on"]

/// spare is not a declared relation.
/obj/machinery/apc/proc/via_spare(datum/act/eval/A)
	return spare.charge > 1

/obj/machinery/apc/proc/bad_field(datum/act/eval/A)
	return nonexistent_var == 1

/obj/machinery/apc/proc/accessor_user(datum/act/eval/A)
	return pad_occupied()

/obj/machinery/apc/proc/night_user(datum/act/eval/A)
	return night_shift_active() && on

/obj/machinery/apc/proc/pure_user(datum/act/eval/A)
	return pure_math(limit) > 1

/obj/machinery/apc/proc/two_arg_user(datum/act/eval/A)
	return two_arg_helper(cell, limit) > 1

/// read_once(): evaluated when the question opens, never subscribed: `mode` is an unknown read without it.
/obj/machinery/apc/proc/once_user(datum/act/eval/A)
	return read_once(mode) == 2

/obj/machinery/apc/proc/calls_ctx_free(datum/act/eval/A)
	return helper_same_type() > 0

/obj/machinery/apc/proc/helper_same_type()
	return cell ? cell.rating : 0

/// A context hop: the actor's tracked stat and relation hop (the pocket), the held cell's charge.
/obj/machinery/apc/proc/actor_busy(datum/act/op/A)
	return A.actor.stat == 0 && A.actor.pocket.charge > 0

/obj/machinery/apc/proc/held_charge(datum/act/op/A)
	return A.held.charge > 0

/obj/machinery/apc/proc/loops(datum/act/eval/A)
	var/n = 0
	for(var/i in 1 to 3)
		n += i
	return n + on

// ---- READS_AS ----

/// Stands for PAD_KEY, which something publishes: covered.
/obj/machinery/apc/proc/pad_occupied()
	READS_AS(pad_occupied, PAD_KEY)
	return pad_count > 0

/// Reads an untracked var and nothing publishes SECRET_KEY: uncovered.
/obj/machinery/apc/proc/secret_count()
	READS_AS(secret_count, SECRET_KEY)
	return secrets

/obj/machinery/apc/proc/bump_pad()
	pad_count++
	secrets++
	mode = 3
	PUBLISH_CHANGE(src, PAD_KEY)

// ---- the condition and stat graph ----

/obj/machinery/loop
	var/a_in = 0
	var/b_in = 0
	var/derived_a = 0
	var/derived_b = 0

/obj/machinery/loop/proc/derive_derived_a()
	return derived_b + 1

/obj/machinery/loop/proc/derive_derived_b()
	return derived_a * 2

/obj/machinery/chain
	var/base = 0
	var/c1 = 0
	var/c2 = 0
	var/c3 = 0
	var/obj/machinery/chain/next

REL(/obj/machinery/chain, next)
TRACKED(/obj/machinery/chain, base)

/obj/machinery/chain/proc/derive_c1()
	return base + 1

/obj/machinery/chain/proc/derive_c2()
	return c1 + 1

/obj/machinery/chain/proc/derive_c3()
	return c2 + c1 + (next ? next.c1 : 0)
