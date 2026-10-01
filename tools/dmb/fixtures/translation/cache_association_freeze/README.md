# Field-chain association and frozen receivers

Thirteen named procedures are compared in full against DreamMaker 516.1687,
with and without debug markers. Left/right associated field-only SetCache chains
perform the same ordered reads and cache writes. Recognizing both lets a native
captured child survive a callback that replaces its binding.

The cases separately require fresh selection after explicit binding writes,
statement field assignment, augmented/postfix mutation, other receiver selection
and branch joins. Ordinary assignment-expression and local-result stores retain
native frontend context. Computed/indexed/Initial-owner chains are excluded.
