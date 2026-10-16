# Fence and biowaste constructor draft

Five init rows: fence2 and biowaste3. Source generation and full ratchets pass; DM/runtime verification remains pending. Wire dq_init_objects_structure_context_tests.dm, with dq_init_objects_fence_shape and dq_init_objects_biowaste_start.

Fence originally updates child door state then base cut state BEFORE the parent. A typed PREINIT capability preserves that same ordered pair before stat setup and movable_instance_setup's generic emissive overlay snapshot. Root flags/color/integrity now precede these writes, but the shape routines read only static door/cut configuration. An opened door remains dense after old parent-cut normalization; the test explicitly preserves this existing behavior.

Biowaste binds the first actual crusher in PREINIT, before existing starting occupants. INIT then names and calls init_vore on the same owned monster. The inherited tails read neither monster name nor crusher. Entered for the starting monster is not food/organ/egg/debris and muffin_mode defaults FALSE. Existing refs/ownership and runtime behavior remain unchanged. The test checks actual borrowed crusher, owned monster, customized real belly and deletion lifetime.

Lattice16 and NTpod13 were rejected from the early hook proposal: movable_instance_setup snapshots icon/icon_state into a generic emissive blocker after the root hook but BEFORE old post-parent assignments. Moving their visual changes to holder-init changes that actual inherited visual snapshot. Neither simple setup (no mapload context) nor a delayed after_init preserves the original mapload-sensitive synchronous transaction. They need a post-parent context form or an explicitly approved appearance migration; no missing A.mapload claim is made.
