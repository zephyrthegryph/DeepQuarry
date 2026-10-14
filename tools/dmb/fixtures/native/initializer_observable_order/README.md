# Observable initializer and membership ordering

Unexecuted observation fixture. Constant-argument `new` initializers reuse the
legal form admitted in initializer_dependent_order. Global, type-static and
procedure-static constructor traces are recorded at boot, holder creation and
first explicit procedure call. No lazy/eager static timing is assumed.

The fixture records filtered holder.vars iteration and typesof(/datum/orderkind)
order verbatim. It does not normalize those lists, timestamps, or traces.

`run.py --reference-only` reuses the existing machine-slotted, owned paired
initializer core for forward/reverse compile-only admission. Next capture a
pinned BYOND runtime observation before interpreting expected order; the normal
paired route compares exact marker strings. No runtime or compilation has been
performed for these new sources, and no complete source-closure claim is made.
