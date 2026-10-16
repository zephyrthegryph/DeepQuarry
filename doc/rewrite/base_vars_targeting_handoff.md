# Source-only cache cohort

Owner directory code/modules/projectiles/targeting: aimed starts null; existing rel_add/remove and LAZYLEN consumers already handle a nullable collection. This removes only list_init; the base_var ownership-home row is deliberately not claimed resolved. Actual aiming collection membership and target lifetime still need a distinct memory-home migration. `dq_targeting_cache_home` exercises real overlay construction, aim, reverse membership allocation and cancellation using the same live relation collection.

No generation, compile, tests, baseline update or stamp has run. Root owns verification and commits.
