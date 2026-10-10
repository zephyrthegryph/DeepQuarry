# Ordered input filters

Pinned BYOND516.1687 compile-only capture: receipt.json authenticates executable SHA/version, exact source/manifest and DMB. The48 statements cover24 ordered type lists with/without choices. No world or native compiler was run during capture.

With choices, each nonobject type following an object filter warns `filter_rightmost: object type filter should be right-most`. Object types tested: mob, obj, turf, area. Each later non-anything type after anything warns the same code with message `'anything' should be right-most`. `obj|text|obj` remains warned; `obj|text|null` produces two warnings. No-choice object ordering is silent. The source-backed producer fixture preserves multiplicity and current statement ordinals.

The receipt also contains four `anything_no_list` warnings from no-choice anything inputs. Those are preserved evidence and remain outside this implementation; this fixture does not claim complete warning parity.
