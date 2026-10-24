// Rare and scratch per-instance state of objects, items and machines: sparse slots (code/engine/declare/sparse_slots.dm), nothing on the type until one is set.
// The default each slot reads as is the one the var it replaced was declared with (sparse_get_or(O, slot, default)); a write of null clears it.
// Read and write them through sparse_get() / sparse_get_or() / sparse_set(), never through a var of the same name.

// /obj
sparse(/obj, being_shocked, type = bool)
sparse(/obj, burn_ended_by, type = text)
sparse(/obj, burn_fuel, type = num)
sparse(/obj, burn_overlay)
sparse(/obj, burn_particle_type)
sparse(/obj, burning_particles)
sparse(/obj, custom_fire_overlay)
sparse(/obj, debris_amount, type = num)
sparse(/obj, economic_department, type = text)
sparse(/obj, economic_export_value, type = num)
sparse(/obj, economic_producer_account, type = num)
sparse(/obj, economic_sale_invoice_id, type = num)
sparse(/obj, micro_accepted_scale, type = num)

// /obj/item
sparse(/obj/item, cleandesc, type = text)
sparse(/obj/item, cleanname, type = text)
sparse(/obj/item, d_mult_old, type = num)
sparse(/obj/item, digest_stage, type = num)
sparse(/obj/item, item_tf_spawn_allowed, type = bool)
sparse(/obj/item, mat_luminescence, type = num)
sparse(/obj/item, mat_radioactivity, type = num)
sparse(/obj/item, mat_toxicity, type = num)
sparse(/obj/item, oldname, type = text)
sparse(/obj/item, tether_path)
sparse(/obj/item, trash_eatable, type = bool)
sparse(/obj/item, worn_layer, type = num)

// /obj/machinery
sparse(/obj/machinery, gas_dependency_wake_count, type = num)
sparse(/obj/machinery, power_init_complete, type = bool)
sparse(/obj/machinery, recursive_set, type = bool)

// base_vars wave 3
sparse(/obj/item, cleaving, type = bool)
sparse(/obj/item, ckeys_allowed_itemspawn, type = list)
sparse(/obj/machinery, rebuilding, type = bool)
sparse(/obj/machinery, heat_output_now, type = num)
