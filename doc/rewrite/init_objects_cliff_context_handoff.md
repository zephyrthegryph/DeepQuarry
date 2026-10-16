# Cliff constructor context (review draft)

Three init rows become a typed holder-init capability receiving actual `A.mapload`. No verification has run. Wire the new test file and run `/datum/unit_test/dq_turf_edges/init_cliff_mapload_registry` plus existing `/datum/unit_test/dq_turf_edges/cliff_blocks_and_releases_edges`.

The old post-parent body registers only an actual danger handle on the current turf and asks neighboring turf-edge readers to recompute for runtime construction. Neither operation reads later object-tail state; the atom root has already initialized flags and type density/opacity at the native hook. There are no descendant cliff Initialize overrides. Automatic cliff shaping is already after_init and remains later, including creation of the lower cliff. The maploader owns final edge recomputation; the hook uses its real A.mapload rather than a constructor-param proxy. Movement and destruction retain their existing unregister/refresh behavior.

The new regression uses a real maploader batch, actual adjacent deep/shallow water, actual turf danger-handle membership, movement and qdel cleanup. Existing runtime edge coverage checks addition/removal without explicit manual edge refresh. No mapload-only synthetic callback invocation or saved flag is introduced.
