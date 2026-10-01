# Iterator subtype checks and budget

Native 516.1687 category masks replace the subtype check only for the exact
`/mob`, `/turf` and `/area` roots, with masks 1, 32 and 256 respectively.
The extra `IsType; Test; JzLoop` is observable even when its condition always
succeeds: JzLoop charges execution budget on both outcomes.

Twenty complete native bodies are compared in both debug modes. Negative
controls retain native checks for `/obj`, `/atom/movable`, `/atom` and specific
subtypes. An explicit `as anything` retains its separate native mask behavior.
The emitter requires both the exact root path and the exact proven category
mask; it does not apply this rule to mixed masks or other roots. Native and
OpenDream compilation produce zero warnings. No server is launched.

Inline orange loops also match native iterator mode 14 through filter
metadata, with default argument padding for zero/one arguments. Conditional
list inputs and ordinary orange list results retain their separate native
operations. Typed, untyped, subtype and `as anything` spatial loops are paired.
