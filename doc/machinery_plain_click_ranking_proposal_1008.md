# Plain-click window and loading ranking proposal

Status: proposal only. This batch does not edit the click resolver or operation priorities.

An interface-generated `ui_open` currently has default priority and a hand binding. A hand binding also matches when an item is held. Painter insertion and bomb-tester loading have default-minus-one priority, so their plain item clicks open the window despite a matching loading operation. The comparator considers priority before binding specificity.

Proposed contract: on a non-harm plain click, a matching item/tool operation should outrank a generic window-opening hand operation. Empty-hand clicks should open the window. Explicitly bound operations and their existing requirements should keep their refusal behavior; a refused loading operation should show its reason rather than silently open the window. An operation whose selection condition is false should fall through to the window. Harm intent should retain the ordinary hit choice.

| Case | Expected choice |
| --- | --- |
| Painter with supported clothing, insert slot empty | Insert clothing |
| Painter with supported clothing, slot occupied | Insert refusal: machine already loaded |
| Painter with unsupported item | Open window, if no other item operation selects |
| Bomb tester with a tank and either bay empty | Load tank |
| Bomb tester with a tank and both bays occupied | Selection falls through to the window |
| Teleporter with coordinate card | Insert card, subject to its requirements |
| Console with empty hand | Open window |
| Matching maintenance tool | Selected tool operation, subject to its requirements |
| Any of these with harm intent | Hit, unless an explicit harm operation selects |
| Explicit loading menu action or UI button | Resolve that requested operation, without plain-click competition |

Implementation options for the click-resolution owner: make generated window openings an explicit fallback class, or give the generated `ui_open` a documented fallback priority below normal loading actions. A universal specificity-before-priority change is broader than this defect and would affect deliberate overrides, so it needs separate case coverage. Any implementation should test both plain clicks and refused/fallthrough cases before re-recording pins, with class-specific causes.
