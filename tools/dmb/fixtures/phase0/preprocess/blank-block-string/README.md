# Interior blank block-string line

Pinned BYOND 516.1687 accepts the captured source with zero errors/warnings.
The block string contains an interior blank line and is followed by another
variable and a world procedure. The native-v2 preprocessing regression preserves
all six source lines, source spans and following declarations. Compile only;
no DreamDaemon was run. `receipt.json` records exact compiler/input/output hashes.
