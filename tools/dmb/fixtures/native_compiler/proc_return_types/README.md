# Procedure return annotations

`probe.native.bin` was compiled offline with DreamMaker 516.1687. No runtime
was launched. The fixture compares calls followed by typed member selection,
including safe calls, globals, and unannotated overrides across two generations.
Another class deliberately declares `attachment` with a different type so the
selected owner determines the inferred type.

Additional offline probes established these native errors:

- A child override cannot redeclare a return annotation, including an identical
  annotation or an annotation on an override of an unannotated parent.
- `as /datum/message|null` is not a valid return annotation.
- `istype(current())` has no inferred variable type even when `current()` has a
  concrete return annotation.
- `istype(global.get_message().attachment)` does not infer the qualified call's
  result type.

The compiler gate retains those negative forms. Atomic restrictions such as
`as anything` do not supply a concrete class path. Native's broader inference
from globally unique member names is outside this fixture.
