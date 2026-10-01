# OpenDream opcode lowering status

Source: [OpenDream `DreamProcOpcode.cs`](https://github.com/OpenDreamProject/OpenDream/blob/master/DMCompiler/Bytecode/DreamProcOpcode.cs). This table covers every declared opcode in that enum. It describes the current Rust lowerer for BYOND 516, not the complete DM language.

`Translated` means a lowering branch exists. `Limited` means only the documented operand pattern is accepted. `Rejected` means the lowerer returns a byte offset and explicit error; it never silently emits a no-op. All translated opcodes still require every referenced string, resource, type, proc, and variable to resolve.

| OD opcode | Name | Status |
|---|---|---|
| `0x01` | BitShiftLeft | Translated |
| `0x02` | PushType | Limited |
| `0x03` | PushString | Translated |
| `0x04` | FormatString | Translated |
| `0x05` | SwitchCaseRange | Limited |
| `0x06` | PushReferenceValue | Limited |
| `0x07` | Rgb | Limited |
| `0x08` | Add | Translated |
| `0x09` | Assign | Translated |
| `0x0a` | Call | Limited |
| `0x0b` | MultiplyReference | Limited |
| `0x0c` | JumpIfFalse | Limited |
| `0x0d` | CreateStrictAssociativeList | Translated — paired NewAList |
| `0x0e` | Jump | Translated |
| `0x0f` | CompareEquals | Translated |
| `0x10` | Return | Translated |
| `0x11` | PushNull | Limited |
| `0x12` | Subtract | Translated |
| `0x13` | CompareLessThan | Translated |
| `0x14` | CompareGreaterThan | Translated |
| `0x15` | BooleanAnd | Limited |
| `0x16` | BooleanNot | Translated |
| `0x17` | DivideReference | Limited |
| `0x18` | Negate | Translated |
| `0x19` | Modulus | Translated |
| `0x1a` | Append | Translated — paired expression `+=` with PushEval |
| `0x1b` | CreateRangeEnumerator | Translated — paired unit and explicit-step numeric `for` ranges |
| `0x1c` | Input | Limited — direct references and indexed savefile reads into direct, field, or list destinations |
| `0x1d` | CompareLessThanOrEqual | Translated |
| `0x1e` | CreateAssociativeList | Translated |
| `0x1f` | Remove | Limited |
| `0x20` | DeleteObject | Translated |
| `0x21` | PushResource | Translated |
| `0x22` | CreateList | Translated |
| `0x23` | CallStatement | Limited — paired literal path and object/name positional calls |
| `0x24` | BitAnd | Translated |
| `0x25` | CompareNotEquals | Translated |
| `0x26` | PushProc | Translated |
| `0x27` | Divide | Translated |
| `0x28` | Multiply | Translated |
| `0x29` | BitXorReference | Limited |
| `0x2a` | BitXor | Translated |
| `0x2b` | BitOr | Translated |
| `0x2c` | BitNot | Translated |
| `0x2d` | Combine | Limited |
| `0x2e` | CreateObject | Limited |
| `0x2f` | BooleanOr | Limited |
| `0x30` | CreateMultidimensionalList | Limited |
| `0x31` | CompareGreaterThanOrEqual | Translated |
| `0x32` | SwitchCase | Limited |
| `0x33` | Mask | Limited |
| `0x35` | Error | Rejected |
| `0x36` | IsInList | Limited |
| `0x38` | PushFloat | Translated |
| `0x39` | ModulusReference | Limited |
| `0x3a` | CreateListEnumerator | Limited |
| `0x3b` | Enumerate | Limited |
| `0x3c` | DestroyEnumerator | Limited |
| `0x3d` | Browse | Translated |
| `0x3e` | BrowseResource | Translated |
| `0x3f` | OutputControl | Translated |
| `0x40` | BitShiftRight | Translated |
| `0x41` | CreateFilteredListEnumerator | Limited |
| `0x42` | Power | Translated |
| `0x43` | EnumerateAssoc | Limited — paired ordinary list key/value iteration |
| `0x44` | Link | Translated |
| `0x45` | Prompt | Translated — native type unions, authored choice/anything provenance, and closed branching arguments |
| `0x46` | Ftp | Translated |
| `0x47` | Initial | Limited |
| `0x48` | AsType | Translated |
| `0x49` | IsType | Translated |
| `0x4a` | LocateCoord | Translated |
| `0x4b` | Locate | Translated |
| `0x4c` | IsNull | Translated |
| `0x4d` | Spawn | Limited |
| `0x4e` | OutputReference | Limited |
| `0x4f` | Output | Translated |
| `0x51` | Pop | Translated |
| `0x52` | Prob | Translated |
| `0x53` | IsSaved | Limited — paired direct owner/field form |
| `0x54` | PickUnweighted | Limited |
| `0x55` | PickWeighted | Limited — literal weights use PickSwitch; dynamic weights use PickProb; verified expression spans support computed candidates |
| `0x56` | Increment | Translated — indexed references cache evaluated list/key in place, including conditional expressions |
| `0x57` | Decrement | Limited |
| `0x58` | CompareEquivalent | Translated |
| `0x59` | CompareNotEquivalent | Translated |
| `0x5a` | Throw | Translated |
| `0x5b` | IsInRange | Limited |
| `0x5c` | MassConcatenation | Translated |
| `0x5d` | CreateTypeEnumerator | Limited — paired literal path type iterator |
| `0x5f` | PushGlobalVars | Translated |
| `0x60` | ModulusModulus | Translated — paired `%%` |
| `0x61` | ModulusModulusReference | Limited — paired statement `%%=` |
| `0x62` | PreIncrement | Limited |
| `0x63` | PreDecrement | Limited |
| `0x64` | JumpIfNull | Limited |
| `0x65` | JumpIfNullNoPop | Limited |
| `0x66` | JumpIfTrueReference | Translated |
| `0x67` | JumpIfFalseReference | Translated |
| `0x68` | DereferenceField | Limited |
| `0x69` | DereferenceIndex | Translated |
| `0x6a` | DereferenceCall | Limited |
| `0x6b` | PopReference | Rejected |
| `0x6d` | BitShiftLeftReference | Limited |
| `0x6e` | BitShiftRightReference | Limited |
| `0x6f` | Try | Limited |
| `0x70` | TryNoValue | Limited |
| `0x71` | EndTry | Limited |
| `0x72` | EnumerateNoAssign | Limited |
| `0x73` | Gradient | Limited |
| `0x74` | AssignInto | Limited — paired direct indexed statement assignment |
| `0x75` | GetStep | Translated |
| `0x76` | Length | Translated |
| `0x77` | GetDir | Translated |
| `0x78` | DebuggerBreakpoint | Rejected |
| `0x79` | Sin | Translated |
| `0x7a` | Cos | Translated |
| `0x7b` | Tan | Translated |
| `0x7c` | ArcSin | Translated |
| `0x7d` | ArcCos | Translated |
| `0x7e` | ArcTan | Translated |
| `0x7f` | ArcTan2 | Translated |
| `0x80` | Sqrt | Translated |
| `0x81` | Log | Translated |
| `0x82` | LogE | Translated |
| `0x83` | Abs | Translated |
| `0x84` | AppendNoPush | Translated |
| `0x85` | AssignNoPush | Limited |
| `0x86` | PushRefAndDereferenceField | Limited |
| `0x87` | PushNRefs | Limited |
| `0x88` | PushNFloats | Translated |
| `0x89` | PushNResources | Translated |
| `0x8a` | PushStringFloat | Translated |
| `0x8b` | JumpIfReferenceFalse | Translated |
| `0x8c` | PushNStrings | Translated |
| `0x8d` | SwitchOnFloat | Limited |
| `0x8e` | PushNOfStringFloats | Translated |
| `0x8f` | CreateListNFloats | Limited |
| `0x90` | CreateListNStrings | Limited |
| `0x91` | CreateListNRefs | Limited |
| `0x92` | CreateListNResources | Limited |
| `0x93` | SwitchOnString | Limited |
| `0x95` | IsTypeDirect | Limited |
| `0x96` | NullRef | Translated |
| `0x97` | ReturnReferenceValue | Translated |
| `0x98` | ReturnFloat | Translated |
| `0x99` | IndexRefWithString | Limited |
| `0x9a` | PushFloatAssign | Translated |
| `0x9b` | NPushFloatAssign | Translated |
| `0x9c` | Animate | Limited |
| `0x9d` / `0x9e` | Patched call_ext / call | Limited — legacy target inference; use the new native-order form for complex calls |
| `0x9f` | Patched modified type constant | Translated — native instance prototype value |
| `0xa0` | Patched native-order dynamic call | Limited — explicit target count, external-call marker, and argument mode; target expressions precede arguments |
| `0xa1` | Patched native-order constructor | Translated — type precedes positional, named, or arglist arguments |
| `0xa2` | Patched native-keyed associative list | Translated — explicit null keys and numeric positional keys preserved |
| `0xa3` | Patched method receiver boundary | Translated — direct references deferred until call; computed receivers cached before arguments |
| `0xa4` | Patched native-order membership | Translated — list precedes item, native IsInList flag result |
| `0xa5` | Patched native-order indexed assignment | Translated — discarded plain assignments evaluate value, list, key, then native ListSet |
| `0xa6` | Patched retained assignment value | Translated — native PushTop preserves the assigned value before evaluating the destination |
| `0xa7` | Patched native Animate arguments | Translated — positional, keyed, and argument-list forms preserve native evaluation order |
| `0xa8` | Patched native-order field assignment | Translated — value precedes owner; the owner is consumed into Cache before the field write |
| `0xa9` | Patched native-order field operation | Translated — compound updates evaluate value before owner; retained and discarded increment/decrement forms use native reference modifiers |
| `0xaa` | Patched native method target | Translated — site-specific procedure binding supplies the effective native display name, preserving literal call targets separately |

## Limited patterns

- `Call` supports inherited calls, authored global and self procs, paired builtins, positional and named arguments, and `arglist()` for global and parent calls.
- Full-game paired builtin calls now include `CRASH`, `isnum`, `round`, `rand`, `clamp`, `min`, `max`, and `fexists`; each has a native opcode and verified argument shape.
- `CreateObject` supports literal and direct dynamic type constructors with zero or more positional arguments, named arguments, or `arglist()` when argument expressions have known stack effects.
- `IsInList` supports the compact two direct reference form; operand order is reversed for BYOND.
- `OutputReference` supports `world.log`, direct receivers, fields and indexed receivers with verified closed conditional/short-circuit expressions. Native receiver resolution precedes RHS evaluation, including conditional field owners. Internal operand branches are relocated; outside-entry and unproved stack-effect spans reject.
- `DereferenceCall` supports a direct owner reference with positional, named, or `arglist()` arguments.
- Switch lowering accepts OpenDream float/string case chains ending in Pop and default Jump.
- Unoptimized numeric and string `SwitchCase` chains lower to a native Switch table. OpenDream may place the default body before case bodies, so native instruction ordering can differ while preserving branch targets.
- `JumpIfNull` and `EnumerateNoAssign` currently lower together for a safe field lvalue in a list loop. Both paths join at the native iterator exit check; unrelated forms reject.
- Dynamic `new T(...)` reorders a direct type reference ahead of zero or more positional constructor arguments; paired zero, one, and two argument procedures match native code.
- Named constructors for literal and direct dynamic types package keyed values into NewAssocList and call native NewArgList; paired examples match.
- Constructor `arglist(L)` for literal and direct dynamic types reorders the type before the list and calls native NewArgList; paired native procedures match.
- `arglist()` calls to global procedures and the parent procedure use native CallGlobalArgList and CallParentArgList, with paired direct and inherited examples.
- Dynamic `value in lower to upper` reorders the three evaluated expressions into native IsIn range order and reads its membership flag; a paired variable-bound procedure matches native code.
- Named global and parent calls package keyed arguments into a native associative list, then use the corresponding ArgList call opcode; paired two-key examples match.
- Implicit self procedure calls use a native Src/DynamicProc reference; positional, named, and `arglist()` forms have paired compiler examples.
- Method calls with `arglist()` or named arguments use native Call's `0xffff` argument sentinel; named values are first packaged as a native associative list.
- Output to `src`, `usr`, `world`, a direct local/argument/global, or an implicit `src` field places the target before a literal, reference, or simple computed RHS expression, matching paired native output procedures.
- Output through a field of a direct receiver, such as `M.client << value`, uses native GetVar(SetCache(receiver, field)) before evaluating the RHS; a paired procedure confirms the operand shape.
- `TryNoValue` uses native Try/Catch and discards the caught value with Pop. Nested handlers use a stack of pending catch targets and remap catch locals in native catch order; the paired nested fixture has no semantic discrepancies.
- `Gradient` supports paired list/index and three or four positional value forms. `Animate` supports a single target and paired one to three named property forms.
- `Error` is only emitted by OpenDream after a compile diagnostic in the inspected compiler; `PopReference` and `DebuggerBreakpoint` have declarations but no compiler emission sites. They remain explicit rejects until a valid paired source demonstrates behavior.
- List enumerator lowering covers the list form observed in fixtures; other enumerator types are rejected.
- Compact constructors retain each operand order and validate counts; dynamic reference kinds follow the reference decoder.
- Reference decoding currently accepts Null, Src, Dot (`.` result), Usr, Args, World, Arg, Local, Global, StaticProc, Src field, and Field.
- Branch targets must land on an instruction boundary. Unsupported argument modes, operands, and unresolved symbols return `LowerError`.

## Verification

DEBUG-mode translation is opt-in with `--debug-lines`: OpenDream SourceInfo becomes native DbgFile/DbgLine instructions, including paired class and global initializer ordering. An optimized OpenDream compile can omit source events that DreamMaker retains; compile with OpenDream `--no-opts` for the verified full line mapping in the `debug_lines` fixture.

Paired DreamMaker 516 and OpenDream fixtures live in `fixtures/translation/` and `fixtures/lowering/`. The seven translation fixtures have been lowered and run by the parent integration harness; this does not imply complete opcode coverage. The `od_lower` unit tests compare several precise BYOND instruction sequences from those paired fixtures.
- `PickUnweighted` lowers one candidate to BYOND Pick and multiple eager candidates to NewList + Pick; zero candidates are rejected.
- `PickWeighted` lowers literal weights to BYOND PickSwitch with cumulative 16-bit thresholds formed by truncating each normalized weight before summation. Dynamic weights use native PickProb. Computed candidates are evaluated only on their selected branch. Closed conditional and short-circuit weight/candidate spans retain relocated internal branches. Unknown stack effects, outside entries and cross-expression branches still reject; a forty-candidate fixture verifies counts beyond the former limit of 32.
- `CreateRangeEnumerator` lowers paired unit-step ranges to Check2Numbers/ForRange/PopN2 and explicit-step ranges to Check3Numbers/ForRangeStep/PopN3.
- `Initial` accepts a direct owner reference and a constant field name.
- `Remove` supports statement position with OpenDream Pop; `AssignNoPush` includes the verified direct three reference list index assignment form.
- `DereferenceField` folds direct GetVar owners into nested SetCache operands; computed owners use an explicit cache at the shared expression join.
- Range switches collect numeric ranges and exact null, numeric, and text cases into separate native tables. Try/Catch supports nested handlers and paired empty catch joins.
- Augmented reference operations (`-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`) use PushEval when their result is read and omit it in statement position. Paired return expressions for addition, multiplication, and left shift match native code.
- `Rgb` supports 3 component RGB and 4 component RGBA positional calls, as observed in paired 516 fixtures.
- `JumpIfNullNoPop` supports paired single, repeated, and three-field nested safe dereferences. Nested chains preserve DreamMaker's PushCache/PopCache stack and distinct null targets; multiple nested chains with different exits reject explicitly.
- Browser output forms (`browse`, `browse_rsc`, `output`, and `link`) have paired native opcode and stack-shape matches.
- `Prompt` reverses OpenDream's argument stack order into DreamMaker Input/PromptCheck. Text, number, nullable, and direct list choices match paired native procedures. Nullable file uses Input type 144; nullable color uses its native flags value and InputColor. Closed conditional and short-circuit argument spans stay together during reordering. Authored choice and explicit `as anything` metadata preserve distinctions lost by stock export. A 144-procedure paired matrix covers type unions, null choices, color and command text; unproved cross-expression branch spans reject.
- `CallStatement` reorders OpenDream's target after positional arguments to DreamMaker CallPath or CallName; paired literal path and direct object/name forms match native code. Computed target and complex argument forms reject.
- Consecutive calls through the same direct local or argument receiver reuse DreamMaker's cached DynamicProc owner; other calls emit an explicit SetCache receiver.
- `AssignInto` lowers paired statement-position `L[key] := value` to CacheKey/Cache/CacheIndex operations with direct list, key, and value expressions.
- `PushFloatAssign` to an indexed list reference reorders the literal value before list/key and emits native ListSet. A paired `L[i] = 1` procedure compares exactly; dynamic formatted keys use the same stack-effect analysis.
- `EnumerateAssoc` uses native IterLoad mode 20 and IterPairValue for paired `for(var/key, value in L)`; filtered or range iterators in this form reject.
- Multidimensional list declarations lower to `new /list(dimensions...)` when size expressions have known stack effects.
- Filtered list enumerators use a scratch slot after `MaxVariableId` locals and a BYOND IsType guard; the caller must pass `OpenDreamProc.max_variable_id` to the context-aware lowering API.
- Patched OpenDream `0x9d`/`0x9e` preserve `call_ext` versus ordinary `call`; stock `0x23` is rejected because both native calls share its old encoding. Paired direct, arglist, and computed owner forms are covered.
- Patched `0xa0` preserves native target-before-argument call order; `0xa1` preserves constructor type-before-argument order. Both include explicit argument mode/count and normalize positional keys in named calls.
- Patched `0xa2` preserves native associative keys: implicit positional entries receive numeric indices, while authored null keys remain null. Lowering emits native NewAssocList without guessing key provenance.
- Paired built-ins now include `jointext`, `isicon`, `ismob`, `ispath` (one and two arguments), `typesof`, `sorttext`, and `sorttextEx`. Only the paired argument counts lower.
- Paired list operations include indexed postincrement, indexed assignment of a dynamic `new path()`, assignment of an indexed value using a postincrement key, and membership against null or an assignment result.
- A direct recursive `.(args)` call maps to native `CallSelfArgs`. Method calls with argument expressions locate the receiver using stack effects; nested `rand` arguments are paired. A receiver cache choice can still differ from DreamMaker's optimizer while preserving the explicit receiver.
- Further paired procedures cover `isobj`, `isturf`, `copytext`, `copytext_char`, `winset`, `winget`, indexed augmented assignment, safe indexed assignment, safe field subtraction, computed method arglists, positional and named `image`, and named `icon` constructors. Native DeepQuarry procedures establish two-argument `time2text`, three-argument radix `num2text`, and two-argument `icon_states` mappings. Unsupported argument shapes continue to return an explicit lowering error.


### Additional closed-expression probes (2026-09-28)

Portable `multidimensional_branches`, `range_pick_branches`, and
`output_branches` fixtures verify conditional/short-circuit dimensions,
range bounds, weighted-pick operands and output receivers/RHS against native
instructions in both debug modes. Only closed spans with verified stack effects
and no outside branch entry qualify. An original return-list multidimensional
probe also exhibited the existing local store-result optimization; its dimension
expression was accepted, and the exact fixture reads `L.len` to isolate that
new lowering behavior from the separately bounded store-reload equivalence.
