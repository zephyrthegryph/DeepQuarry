# Native typed variable/field cohort

Pinned checker 0290db5c752fa292f9824521515b603a2afd11dc emits ten untagged
errors on this fixture. No reference diagnostic is filtered. Native policy uses
the same issued syntax, scope visitor, source formal declarations and fixed
checker builtin facts. Local/parameter/source-field type annotations are shared
native declaration projections, not an inference tree or second DM parser.

Unknown-receiver field warnings/fix hints, private/protected notes, static ::
fields/global-ident terms, nested lists, array declarations, stored locals and
missing type paths remain explicitly unsupported. `global.missing_global` in
this fixture is a normal root-object field and the reference says “undefined
field … on (global)”, not “undefined global var”.
