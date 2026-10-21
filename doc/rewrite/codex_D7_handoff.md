# D7 ordering and administrative deletion

Branch: codex/D7. Verification pending; no push.

The relative-priority ceiling shrank from 27 to 13. Fourteen hand/tool anchors now use declared click_order entries with the same holder, binding and key direction. Existing numeric tiers are unchanged. The SDQL deletion macro is removed; its real deletion handler calls lifeform_end(d, END_ENGINE), preserving qdel's original cause, source and force behavior. The lifecycle qdel ceiling shrank from 1 to 0.

Remaining production anchors: ashtray add_butt (ITEM); paint/reagent_container fill and spray (AT_TARGET/cross-holder); bible invoke, box crumple and dog-module choose (IN_HAND); lockbox and secure storage locked_click (ITEM); personal closet swipe (ITEM); buckle_drag (item/mob plus drag); vending open_with_item (ITEM); reinforced-table construction (drag versus tool). click_order supports hand and tool qualities, not these mixed/other bindings. No numeric substitute or renamed helper was added. Test-only numeric-grid priority fixture is retained.

Planned focused verification (not yet run on the refreshed branch): dx_menu_order, dx_menu_order_static, dq_d7_sdql_delete. The new test runs the real bounded SDQL parser and yielding query, asserting only matched inventory dies and its ending cause/source remain identical.
