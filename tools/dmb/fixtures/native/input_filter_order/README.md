# Ordered input filters

Pinned BYOND516.1687 compile-only capture: receipt.json authenticates executable SHA/version, exact source/manifest and DMB. The48 statements cover24 ordered type lists with/without choices. No world or native compiler was run during capture.

With choices, each nonobject type following an object filter warns `filter_rightmost: object type filter should be right-most`. Object types tested: mob, obj, turf, area. Each later non-anything type after anything warns the same code with message `'anything' should be right-most`. `obj|text|obj` remains warned; `obj|text|null` produces two warnings. No-choice object ordering is silent. The source-backed producer fixture preserves multiplicity and current statement ordinals.

The receipt also contains four `anything_no_list` warnings from no-choice mixed-type anything inputs. The same typed producer now emits these with the exact message and current statement ordinal, while corresponding inputs with choices remain silent for this code. The additional authenticated `diagnostic_anchor_cursor` matrix proves that a sole anything filter is silent and multiple type tokens warn once for each anything token, including duplicates. The fixture checks all19 captured warnings; it does not claim warning parity beyond these matrices.

Exact coordinate parity for `anything_no_list` remains open: BYOND reports lookahead lines51/55/59/63 (the following procedure headers), while the authored expressions occupy lines50/54/58/62. The test explicitly checks this captured mapping and independently checks the native current expression ordinal. Production does not move a warning into the next procedure. Matching BYOND's token location requires an issued end-token source receipt through the normal debug source interface.
