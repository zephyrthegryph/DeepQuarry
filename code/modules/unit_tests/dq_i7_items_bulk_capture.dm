/**
 * I7: bulk domain snapshot for the items domain converted to interaction entries
 * (roadmap I7, doc/rewrite/interactions.md section 13). One snapshot covering every
 * converted item type, generated from the resolver's actual current output, the
 * same technique as dq_i7_bulk_capture.dm / dq_i7_structures_bulk_capture.dm for the
 * machinery and structures domains. Grows as more items subdomains are converted.
 */
/datum/unit_test/dq_interaction_domain_snapshot/i7_items_bulk
	snapshot_types = list(
		/obj/item/assembly,
		/obj/item/assembly/voice,
		/obj/item/assembly/igniter,
		/obj/item/assembly/shock_kit,
		/obj/item/assembly/mousetrap,
		/obj/item/assembly_holder,
		/obj/item/assembly/signaler,
		/obj/item/assembly/infra,
	)
	expected = list(
		"/obj/item/assembly|human|none => assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly|robot|none => assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly|ai|none => |",
		"/obj/item/assembly|ghost|none => |",
		"/obj/item/assembly/voice|human|none => assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/voice|robot|none => assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/voice|ai|none => |",
		"/obj/item/assembly/voice|ghost|none => |",
		"/obj/item/assembly/igniter|human|none => assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/igniter|robot|none => assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/igniter|ai|none => |",
		"/obj/item/assembly/igniter|ghost|none => |",
		"/obj/item/assembly/shock_kit|human|none => assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/shock_kit|robot|none => assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/shock_kit|ai|none => |",
		"/obj/item/assembly/shock_kit|ghost|none => |",
		"/obj/item/assembly/mousetrap|human|none => mousetrap_hand,assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/mousetrap|robot|none => mousetrap_hand,assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/mousetrap|ai|none => |",
		"/obj/item/assembly/mousetrap|ghost|none => |",
		"/obj/item/assembly_holder|human|none => assembly_holder_hand|assembly_holder_self:must be held in hand",
		"/obj/item/assembly_holder|robot|none => assembly_holder_hand|assembly_holder_self:must be held in hand",
		"/obj/item/assembly_holder|ai|none => |",
		"/obj/item/assembly_holder|ghost|none => |",
		"/obj/item/assembly/signaler|human|none => signaler_transfer,assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/signaler|robot|none => signaler_transfer,assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/signaler|ai|none => |",
		"/obj/item/assembly/signaler|ghost|none => |",
		"/obj/item/assembly/infra|human|none => infra_hand,assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/infra|robot|none => infra_hand,assembly_item|assembly_self:must be held in hand",
		"/obj/item/assembly/infra|ai|none => |",
		"/obj/item/assembly/infra|ghost|none => |",
	)
