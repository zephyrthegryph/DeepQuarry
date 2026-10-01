# Iterator type checks and execution budget

Fresh Dream Maker 516.1687 compilation establishes these exact root rules:

| Declared iterator root | Native mask | Native subtype check |
| --- | ---: | --- |
| `/mob` | 1 | omitted |
| `/turf` | 32 | omitted |
| `/area` | 256 | omitted |
| `/obj` | 2 | retained |
| `/atom/movable` | 3 | retained |
| `/atom` | 291 | retained |

The former translator emitted `GetVar; PushVal(type); IsType; Test; JzLoop`
for all six roots. The extra check affects execution budget even when its
condition always succeeds. The native dispatch table at `10154278` maps FA
(`JzLoop`) to `10150315`; both condition outcomes reach the budget decrement
at `1015029f`. Ordinary Jz does not perform this decrement. The observed game
witness is `/datum/event/prison_break/end`, whose area iterator already uses
mask 256, but translated output added the extra FA check.

The emitter now omits the subtype check only when the authored type path is
exactly one of the three proven roots and the actual iterator mask is exactly
its proven category. Subtypes, other roots and mixed masks retain their checks.
Explicit `as anything` follows its existing separate native contract.

`tests/iterator_root_budget.rs` compares twenty complete native bodies in both
debug modes and separately asserts the presence or absence of FA. It includes
all six roots, area/object/mob/datum subtypes, and `as anything`. Native and
OpenDream compilation have zero warnings. Focused Cargo verification passes.
No runtime process is used for these checks.

The same matrix preserves inline `orange` iterator mode 14 across the
exporter's intervening filter metadata. It covers typed and untyped loops,
subtypes, `as anything`, zero/one/two arguments, and default argument padding.
A conditional list expression keeps ordinary list iteration: an incoming
branch to the filter/enumerator boundary prevents spatial iterator fusion.
An ordinary `orange` list result is a negative control and retains the native
list-producing operation.
