// Exercises the concrete adapters across extracted engine foundations.
#define ENGINE_ADAPTER_SLOT "engine_adapter_sealed"

/datum/unit_test/dq_engine_foundation_adapters

/datum/unit_test/dq_engine_foundation_adapters/Run()
	var/obj/holder = allocate(/obj)
	var/obj/item/paper/paper = allocate(/obj/item/paper)
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	var/datum/relation_definition/slot/slot_def = declared_slot_def(holder.type, ENGINE_ADAPTER_SLOT, 2, null, /obj/item/paper, TRUE, SLOT_EXPOSURE_SEALED)
	TEST_ASSERT(istype(slot_def, /datum/om/relation/slot), "declared slots retain their legacy slot ancestry")
	TEST_ASSERT(istype(slot_def, /datum/om/relation/slot/declared/sealed), "sealed factory keeps the original concrete type")
	TEST_ASSERT_EQUAL(slot_def.capacity_for(holder), 2, "factory configuration reaches the engine slot")
	TEST_ASSERT(!slot_def.passes_gas(), "sealed slot retains its propagation policy")
	TEST_ASSERT_NULL(slot_def.refusal(holder, paper, null), "concrete declared accepts permits paper")
	TEST_ASSERT_NOTNULL(slot_def.refusal(holder, pen, null), "concrete declared accepts refuses a pen")
	TEST_ASSERT_EQUAL(declared_slot_def(holder.type, ENGINE_ADAPTER_SLOT, 99, null, null, FALSE), slot_def, "declared slots retain their shared identity")

	var/datum/relation_definition/slot/canonical = containment_slot_factory().canonical_create(SLOT_EXPOSURE_SEALED)
	TEST_ASSERT(istype(canonical, /datum/relation_definition/slot/declared/sealed), "standalone engine factory constructs its genuine canonical sealed slot")
	TEST_ASSERT(!istype(canonical, /datum/om/relation/slot), "canonical and compatibility factories have distinct concrete identities")
	canonical.set_declared_accepts(/obj/item/paper)
	var/allowed = canonical.refusal(holder, paper, null)
	var/denied = canonical.refusal(holder, pen, null)
	var/passes_gas = canonical.passes_gas()
	qdel(canonical)
	TEST_ASSERT_NULL(allowed, "canonical slot uses the same real acceptance implementation")
	TEST_ASSERT_NOTNULL(denied, "canonical slot rejects a mismatched concrete item")
	TEST_ASSERT(!passes_gas, "canonical sealed slot is sealed without a legacy provider")

	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool)
	var/datum/predicate/tool_check = dq_predicate_for("[type]/tool", list(REQ_TOOL_TIER(TOOL_WELDER, 1)), "engine tool adapter")
	TEST_ASSERT(!length(tool_check.errors), "real tool predicate compiles")
	TEST_ASSERT(tool_check.check(actor, paper, welder), "concrete tool adapter accepts an actual welding tool")
	TEST_ASSERT(!tool_check.check(actor, paper, pen), "concrete tool adapter rejects a pen")
	TEST_ASSERT_NOTNULL(tool_check.why_not(actor, paper, pen), "rejected tool produces an actual reason")

	var/datum/material/steel = GLOB.name_to_material[MAT_STEEL]
	TEST_ASSERT_NOTNULL(steel, "actual material registry contains steel")
	var/list/identity = state_registry_id(steel)
	TEST_ASSERT_NOTNULL(identity, "concrete material adapter recognizes its singleton")
	TEST_ASSERT_EQUAL(state_registry_lookup(identity), steel, "material lookup keeps singleton identity")
	var/datum/state_context/encoder = allocate(/datum/state_context, NONE)
	var/datum/state_context/decoder = allocate(/datum/state_context, NONE)
	var/encoded = encoder.encode_value(steel, "engine material adapter")
	TEST_ASSERT(!length(encoder.errors), "material singleton encodes without refusal")
	TEST_ASSERT_EQUAL(decoder.decode_value(json_decode(json_encode(encoded))), steel, "material singleton survives the actual JSON codec path")
	TEST_ASSERT(!length(decoder.errors), "material singleton decodes without refusal")

#undef ENGINE_ADAPTER_SLOT

/datum/unit_test/dq_engine_foundation_lazy_providers

/datum/unit_test/dq_engine_foundation_lazy_providers/Run()
	var/datum/containment_slot_factory/saved_containment_slot_factory = GLOB.containment_slot_factory
	GLOB.containment_slot_factory = null
	var/datum/containment_slot_factory/created_containment_slot_factory = containment_slot_factory()
	var/reused_containment_slot_factory = created_containment_slot_factory == containment_slot_factory()
	GLOB.containment_slot_factory = saved_containment_slot_factory
	var/created_containment_slot_factory_valid = istype(created_containment_slot_factory, /datum/containment_slot_factory)
	qdel(created_containment_slot_factory)
	TEST_ASSERT(created_containment_slot_factory_valid, "containment_slot_factory can initialize before managed globals")
	TEST_ASSERT(reused_containment_slot_factory, "containment_slot_factory retains one lazy provider identity")
	TEST_ASSERT_EQUAL(GLOB.containment_slot_factory, saved_containment_slot_factory, "containment_slot_factory original provider is restored")

	var/datum/state_construction/saved_construction = GLOB.state_construction
	GLOB.state_construction = null
	var/datum/state_construction/created_construction = state_construction()
	var/reused_construction = created_construction == state_construction()
	GLOB.state_construction = saved_construction
	var/created_construction_valid = istype(created_construction, /datum/state_construction)
	qdel(created_construction)
	TEST_ASSERT(created_construction_valid, "state_construction can initialize before managed globals")
	TEST_ASSERT(reused_construction, "state_construction retains one lazy provider identity")
	TEST_ASSERT_EQUAL(GLOB.state_construction, saved_construction, "state_construction original provider is restored")

	var/datum/state_registry_adapter/saved_registry_adapter = GLOB.state_registry_adapter
	GLOB.state_registry_adapter = null
	var/datum/state_registry_adapter/created_registry_adapter = state_registry_adapter()
	var/reused_registry_adapter = created_registry_adapter == state_registry_adapter()
	GLOB.state_registry_adapter = saved_registry_adapter
	var/created_registry_adapter_valid = istype(created_registry_adapter, /datum/state_registry_adapter)
	qdel(created_registry_adapter)
	TEST_ASSERT(created_registry_adapter_valid, "state_registry_adapter can initialize before managed globals")
	TEST_ASSERT(reused_registry_adapter, "state_registry_adapter retains one lazy provider identity")
	TEST_ASSERT_EQUAL(GLOB.state_registry_adapter, saved_registry_adapter, "state_registry_adapter original provider is restored")

/datum/unit_test/dq_engine_containment_runtime_state

/datum/unit_test/dq_engine_containment_runtime_state/Run()
	var/obj/holder = allocate(/obj)
	var/obj/successor = allocate(/obj)
	var/datum/rx_state/before = holder.rx
	TEST_ASSERT_EQUAL(holder.containment_move_flags(), 0, "new holder has no move flags")
	TEST_ASSERT_NULL(holder.containment_successor(), "new holder has no lifecycle successor")
	TEST_ASSERT(!holder.latent_is_declared(), "new holder has no declared generator")
	TEST_ASSERT(!holder.latent_policy_disabled(), "new holder has not disabled latency")
	TEST_ASSERT_EQUAL(holder.latent_pin_count(type), 0, "new holder has no pins")
	TEST_ASSERT_EQUAL(holder.rx, before, "all cold containment reads preserve existing state identity")
	holder.latent_pin(type)
	holder.latent_pin(type)
	TEST_ASSERT_EQUAL(holder.latent_pin_count(type), 2, "repeated real pins retain their count")
	holder.latent_unpin(type)
	TEST_ASSERT(holder.latent_explicitly_pinned(), "one unpin preserves independent demand")
	holder.latent_unpin(type)
	TEST_ASSERT(!holder.latent_explicitly_pinned(), "last unpin releases demand")
	holder.set_containment_move_flags(MOVE_HOOK_SUBTREE)
	TEST_ASSERT_EQUAL(holder.containment_move_flags(), MOVE_HOOK_SUBTREE, "runtime move flags remain writable")
	holder.set_containment_move_flags(0)
	holder.set_containment_successor(successor)
	TEST_ASSERT_EQUAL(holder.containment_successor(), successor, "successor identity is retained")
	holder.set_containment_successor(null)
	holder.set_latent_declared(TRUE)
	TEST_ASSERT(holder.latent_is_declared(), "generator declaration remains instance state")
	holder.set_latent_declared(FALSE)
	holder.set_latent_policy_disabled(TRUE)
	TEST_ASSERT(holder.latent_policy_disabled(), "latency opt-out remains instance state")
	holder.set_latent_policy_disabled(FALSE)
	TEST_ASSERT_EQUAL(holder.containment_move_flags(), 0, "cleared flags return to zero")
	TEST_ASSERT_NULL(holder.containment_successor(), "cleared successor releases reference")
	TEST_ASSERT(!holder.latent_is_declared() && !holder.latent_policy_disabled(), "cleared flags return to defaults")
