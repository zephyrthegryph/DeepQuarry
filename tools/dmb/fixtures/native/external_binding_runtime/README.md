# External runtime library binding

`run.py` compares direct and procedure-static `load_ext`/`call_ext` calls against
independently expected ABI values using the same pinned library bytes in both
trusted runtimes. Supply the compiler, template, DreamMaker and DreamDaemon pins
required by the shared launcher, plus `--library` and `--library-sha256`.

The default uses an absolute library path. `--library-name verdigris
--stage-library` instead copies the pinned library beside each isolated DMB and
tests BYOND's relative library lookup. The copy uses exclusive creation and is
hashed before launch. Evidence records both actual hosted paths and requested
runtime spelling; the source pin is checked again after both children finish.

Both modes passed the bounded paired probe. Relative lookup without an adjacent
library failed on BYOND itself. Native acquired DMB slots must therefore stage
the current worktree library before hosting. These probes establish external
binding behavior, not whole-game runtime parity.
