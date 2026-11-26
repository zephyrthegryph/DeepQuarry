# DeepQuarry build script

`tools/build/build.ts` (Juke Build, run by Bun) builds the game: the DM code, the generated DM (`analyze gen`), the manifest,
icons, tgui, and the verdigris library. Steps whose inputs have not changed since the last run are skipped.

Enter through the wrappers, never `bun build.ts` directly: they pin `DQ_BUILD_ROOT` to their own checkout and turn off Bun's shared
transpiler cache (`build.ts` refuses to run when its root differs from the invoking worktree's).

- Windows: `bin\build.cmd` (and the other `bin\*.cmd` entry points), or `tools\build\build.bat <target>`.
- Git Bash / Linux: `tools/build/build.sh <target>`.
- VSCode: the tasks in `.vscode/tasks.json`.

`tools/build/build.sh --help` lists the targets. The usual ones and what they do are in `doc/testing.md` (quick reference) and
`AGENTS.md` section 4.

## Dependencies

The versions are pinned in `dependencies.sh`.

- BYOND 516.1682 or later (`dependencies.sh`: earlier versions crash at atmos init).
- Bun: `tools/bootstrap/javascript.sh` / `.bat` install the pinned version privately on first use.
- Rust (`cargo`): the analyzer (`tools/analyze`), the native DM compiler (`tools/dmb`) and verdigris (`verdigris/`, with the i686
  targets from `verdigris/rust-toolchain.toml`). Without cargo, a build that needs regenerated DM fails (see below), and
  verdigris is skipped with a warning (atmospherics and cave generation then fail at runtime).
- Python 3: `tools/build/gen_dme.py` and the icon repack.
- git.

## Generated DM

`deepquarry.dme` and the test tree's include lists (`code/tests/_tests.dm`, `code/tests/unit_tests/_unit_tests.dm`) are generated
from the files on disk (`gen_dme.py`, `gen_test_includes.py`) and committed. `code/engine/_generated/`, `code/_generated/reads.dm` and
the tgui interface types are written by `analyze gen` and gitignored. With no analyze binary the gen step fails rather than compile
generated files that may come from another branch; `DQ_ALLOW_STALE_GEN=1` compiles the copy on disk anyway, `DQ_SKIP_GEN=1` skips the
step.

## Named BYOND versions

To use a BYOND installation outside the standard locations, list it in `tools/build/dm_versions.json` (read by `lib/byond.ts`).
An entry with `"default": true` is used before the standard locations; otherwise pass `--dm-version=<name>`:

```json
[
  { "name": "516.1682", "path": "D:\\byond\\516.1682\\bin\\dm.exe", "default": true }
]
```

## DEBUG is off in production builds

`deepquarry.dme` does not define `DEBUG`. The production `dm` target (and `build`/`server`) compiles without it: runtimes lose their
file and line numbers, and the world loads about 56 MB smaller (doc/rewrite/init_and_turfs.md section 0.5). The custom runtime handler
in `code/content/error_handler/` stays on; without file and line it dedupes on the error text and proc name.

Test, bench and autowiki builds add `DEBUG` themselves (`TEST_DEFINES` in `build.ts`), so test runtimes keep their line numbers. For a
local debug build of the main .dmb, pass it explicitly: `tools/build/build.sh -DDEBUG`.
