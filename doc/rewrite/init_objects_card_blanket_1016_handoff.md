# POI loader, robot ID and mapped blanket source review

Six retained init fingerprints (POI 1, borg card 4, blanket 1). No descendants have Initialize overrides for these exact families. The borg card's parent reset_icon and ID expiry initializer remain inline and complete before its new setup, preserving their ordering. It binds only a real robot location, retains the existing reference and attempted-move observer, and changes no ownership policy.

POI enqueue is exactly rel_add(poi_queue) plus wake_work_item(place_pois), with no synchronous placement. The parent landmark has no coordinate registration branch for the default PoI Loader name; no subclass initializer exists. Setup still queues before the constructor returns or any scheduler yield. Existing dq_system_pois is the focused regression for actual queue insertion, waking a parked worker and processing/draining the queue; it must be in the verification list.

Mapped blanket unfold is post-parent today, uses no dropped constructor params and has no descendant initializer. Setup retains the same immediate map-placement point, not after_init or a frame delay. The real eight-neighbor fixture verifies actual side placement, metadata and native ownership/deletion. This does not change the existing requirement to place mapped blankets after their surroundings.

Two new focused leaves dq_init_objects_card_blanket and /blanket plus existing dq_system_pois cover the cohort. No generation, builds or tests have run. Root must wire dq_init_objects_card_blanket_tests.dm. This patch is disjoint from the earlier reviewed drafts.
