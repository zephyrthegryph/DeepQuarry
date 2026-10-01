# Branch entry and safe receiver cleanup

Eight named native 516.1687 procedures are checked in full in both debug modes.
They cover incoming condition branches to indexed augmented assignments, RHS-first
receiver ordering, and logical/ternary branches that skip guarded receivers.

The skipped edge must bypass receiver PopCache frames it never acquired. Inner
safe guards still unwind their enclosing frames. Cases include nested logic and
an enclosing method-argument cache frame. Authored goto is not treated as a
conditional-expression edge. No runtime hosting is required by these fixtures.
