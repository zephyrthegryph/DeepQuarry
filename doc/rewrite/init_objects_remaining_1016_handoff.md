# Residual object-init follow-up review

This is a source-only proposal; no compilation, tests or analyzer update has run.
Nine remaining baseline rows are covered by the patch.

- Full flamethrower: secure its completed assembly through set_status in setup; its starting igniter already exists. No descendant initializer reads the status.
- Shock maul: setup invokes its existing real update_held_icon override, after parent cell/materialization, preserving unwielded force and launch/weakening state. No descendant initializer exists.
- Powder: setup invokes existing get_appearance after the actual reagent capability exists. The test override proves one call and a real reagent holder; it does not invent a reagent recipe.
- Mercenary card: setup resolves existing blast doors by the original shuttle-door code. No descendant initializer exists; positive and negative real-door membership is tested.
- Pressurized phoron tank: setup applies the existing adjust_scale(.8), after the tank's real gas/blueprint/proxy initialization. No descendant initializer exists; scale and gas pressure are tested.
- Confetti and smoke: the complete affected hierarchy is converted together. Owned sprayers exist before setup; ancestor setup attaches smoke before descendant primed setup activates its fuse. A global source search found no other descendant initializers. Real holder identity, active state and owned destruction are tested.
- Reset AI module: its existing owned laws slot receives a subtype starts factory using the same using_map.default_law_type. The parent has no initializer or law-consuming construction action and no descendant initializer exists. Map identity, per-instance law datums and owned destruction are tested.

Wire code/modules/unit_tests/dq_init_objects_remaining_tests.dm in the root-owned manifest. Planned focused selectors: dq_init_objects_remaining and its sprayers, mercenary and map_laws leaves.

These are supported source migrations, not declared framework gaps. The retained larger base-item/material hierarchies require separate timing proof; they are not dismissed by this small proposal.
