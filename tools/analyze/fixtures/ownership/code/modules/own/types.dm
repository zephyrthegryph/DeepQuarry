// Types and declarations for the ownership lint fixture.
REGISTRY_TYPE(/datum/reg_thing, REG)

/datum/reg_thing
	var/name = "reg"

/obj/item/widget
	var/label = "w"
	var/untyped_w

/obj/holder
	var/obj/item/held
	var/mob/occupant
	var/list/obj/stuff
	var/list/roster
	var/datum/reg_thing/shared_thing
	var/datum/reg_thing/proto_thing
	var/datum/gas_mixture/air
	var/obj/item/shared_item
	var/obj/item/owned_decl
	var/obj/item/rel_decl
	var/obj/item/mixed
	var/datum/blob/spilled
	var/obj/item/spilled_ok
	var/tmp/obj/item/cached
	var/count = 0
	var/untyped_thing
	var/obj/item/unique_ent
	var/obj/item/label
	var/obj/item/ann
	var/obj/item/rel_owned
	var/obj/item/rel_proto
	var/obj/item/rel_good

/obj/holder/ownership()
	. = ..()
	. += owns(nameof(owned_decl))
	. += shares(nameof(shared_item))
	. += owns(nameof(shared_thing))
	. += owns(nameof(proto_thing), policy = OWN_PRIVATE_COPY)
	. += owns(nameof(spilled), policy = OWN_SPILL)
	. += owns(nameof(spilled_ok), policy = OWN_CONTAINED)
	. += owns(nameof(ann), policy = OWN_NONE)
	. += rel_one(nameof(rel_owned), kind = RELK_OWNED)
	. += rel_many(nameof(rel_proto), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY) // trailing comment

	. += owns(nameof(after_blank))

/obj/holder/relations()
	. = ..()
	. += rel_one(nameof(rel_decl))
	. += rel_one(nameof(rel_good))

/obj/holder/sub
	var/obj/item/subvar

// one kind per var across the hierarchy
/obj/kinds_base
	var/obj/item/kv

/obj/kinds_base/sub

/obj/kinds_base/ownership()
	. += owns(nameof(kv))

/obj/kinds_base/sub/relations()
	. += rel_one(nameof(kv))

/obj/other
	var/list/rosterless
	var/obj/item/label

/obj/holder/var/obj/item/abs_held

OM_FIELD(/obj/holder, om_plain, 1)
OM_FIELD_TYPED(/obj/holder, /obj/item, om_item, null)
OM_FIELD_VIEW(/obj/holder, /obj/item, om_view, null)

/obj/holder/ownership_note
	var/obj/item/not_declared
