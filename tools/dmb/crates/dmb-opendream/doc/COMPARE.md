# Static DMB comparison

`dev-scripts/output_parity.rs` compares complete emitted/native files, reports
uncapped metadata and map differences, pairs named procedures and class/world
initializers, and optionally compares RSC payloads. Its bytecode pass ignores
debug markers and remaps branches that target those markers to the next
executable instruction. See `doc/audits/PARITY_REPORT.md` for the latest results and limits.

`compare_dmbs(expected, actual, options)` reports differences between two
parsed `Dmb` values. It pairs classes and procedures by their compiled paths,
then compares class parents, declaration flags and initial values, explicit
class defaults and overrides, procedure metadata, argument and local layouts,
and decoded procedure instructions. String, type, procedure, and resource
references are resolved so changing table IDs alone does not imply a semantic
change. The `authored_prefixes` option limits the result to source paths of
interest; an empty list compares the entire file. `max_discrepancies` bounds
output.

For whole-program comparisons, the tool also checks world type references,
text and numeric settings, procedure membership, script files, the selected
skin resource, and global declarations. Text, type, and proc IDs are resolved
before comparison. Mob records are paired by class path and checked for their
key and visibility settings.

Argument `in` source expressions are anonymous procedures referenced through
`ProcArgument.value_source`. The comparator follows those references and
compares their metadata and bytecode through the owning argument slot.
Optional procedure string fields treat `0xffff` as the absent sentinel even
when a full game has more than 65,535 strings.

`dmb-map-compare EXPECTED.dmb ACTUAL.dmb` separately expands map runs and
compares turf and area instances at each coordinate plus ordered map objects.
It resolves instance class paths and compares each paired override initializer
once. Nonempty grid `contents` lists are reported as unverified until their
record semantics are established.

Pass `--semantic-values` to `dmb-map-compare` or `od-map-audit` to compare
straight-line constant map assignments by final field value. This accepts a
different write order only when both initializers contain constants, list
construction, and field writes without calls, reads, or branches; all other
initializers retain strict bytecode comparison.

`PushInt` and a numeric `PushVal` normalize to the same float value when
equivalent. The string operand of `Format` and `OutputFormat` resolves to text
before comparison, so reordered string tables do not appear as changes.
`DbgFile` resolves its source filename the same way.
Simple jump destinations are compared by instruction index rather than word
offset, which accounts for different instruction widths. This also applies to
`Try`, `Catch`, and `TryJmp` destinations.

This is a **diagnostic comparison**, not an execution equivalence proof:

- Procedures that share the same path are paired in table order. Different
  override-chain ordering may produce misleading differences.
- Bare bytecode operand words are compared raw. Some are literal numbers or
  branch targets, while others may be table IDs; a difference needs inspection.
  Switch operands are currently reported in their decoded raw form.
- Global-variable bytecode references currently resolve to their variable
  name. Two statics with the same name but different declaring types can
  compare as equal; the caller must inspect such matches until ownership is
  included in the normal form.
- Initial values constructed by a procedure use the hidden initializer marker;
  their runtime result cannot be inferred from the marker alone.
- Only explicit class declarations, defaults, and overrides are compared;
  inherited effective values are not recomputed. Global declarations are
  compared, but global values outside the declaration list and resource data
  are outside the main comparator's scope. Use `dmb-map-compare` for map cells.
- Anonymous class initializers and the world global initializer are compared
  through their owning class/world slots when the corresponding path is
  selected. Their generated proc names do not need to match.
- Matching static records does not show that DreamDaemon accepts or executes
  either DMB. Runtime validation is separate and requires explicit opt-in.
