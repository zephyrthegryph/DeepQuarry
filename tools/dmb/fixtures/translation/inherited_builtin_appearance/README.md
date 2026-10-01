# Inherited native appearance records

Twenty-two authored classes compile with DreamMaker516.1687 without errors or warnings. The fixture includes a PNG asset and native DMB/RSC snapshots. Native compilation only; no DreamDaemon was run for this matrix.

The parent assigns name, description, icon, icon_state, direction, layer, maptext and geometry, packed appearance flags, alpha, color, plane, pixels, luminosity, glide size and blend mode. An alpha-only child and direction-only grandchild retain every unrelated parent setting. Reopening a grandchild to add ordinary fields also retains them. A second parent tests six-element transform and twenty-element color matrix inheritance.

Name/text require source-aware handling. An implicit parent name does not replace a child's implicit leaf name: implicit_base becomes 'implicit base', its child becomes 'child'. An explicitly named ancestor supplies descendants' name and name-derived text. Changing name recomputes derived text; an explicitly assigned ancestor text remains unchanged when a child changes name. Explicit name=null resets the implicit leaf name, including for its descendants: a child of null_name is named child despite an older explicitly named ancestor. Explicit text=null remains inherited as absent, even when a descendant changes name; description/icon null remove their respective values.

The matrix includes an ordinary /obj descendant with explicit parent_type and a lexical /custom_appearance alias whose actual parent is /obj. The alias and its child are legal native atom types and retain authored/inherited appearances despite their non-/obj path prefix. Field classification must follow actual ancestry.

Translated effective-header comparisons belong to the coordinated emitter regression; this fixture records the native contract and does not claim pending translated gates passed.

The Rust emitter regression compares all dedicated class header fields and builtin override values for every authored owner, in both debug modes. It also corrupts a child icon_state to verify that inherited appearance differences are detected. Class identities and strings are compared by contents; table/list/procedure allocation IDs are excluded from this appearance comparison.

The confirmed runtime defect was allocation-time inheritance: child class records were cloned before their parents' authored icon_state/name/appearance settings were applied. The declaration pass now refreshes effective headers in parent order while preserving each class's own declaration/procedure tables. Actual parent ancestry identifies appearance classes, including a root path outside /obj whose parent_type is /obj. Implicit names remain local to each leaf; nearest authored name=null resets that inheritance, whereas explicitly authored text=null remains inherited.

The paired matrix also exercises a six-number transform followed by a twenty-number color list. Only that verified complete initializer shape is baked into the native header; unrelated initializer tails are not discarded.
