# DeepQuarry

DeepQuarry is a Space Station 13 server codebase, hard-forked from CHOMPStation2
(lineage: Baystation12 → Polaris → VOREStation → Yawn-wider → CHOMPStation). It no
longer tracks or merges from any upstream. The project is a roleplay-focused rework:
contracts, a cascading medical model, material science, and on-demand expeditions,
built around the Southern Cross station.

Read [CONTRIBUTING.md](.github/CONTRIBUTING.md) before opening a pull request.
Architecture notes live in [doc/](doc/architecture.md); agent and contributor
conventions are in [AGENTS.md](AGENTS.md).

---

### Getting the code

    git clone https://github.com/zephyrthegryph/DeepQuarry.git

### Building and running

You need [BYOND](https://www.byond.com/) 516. Windows entry points live in `bin/`:

| Script | What it does |
|---|---|
| `bin/build.cmd` | Build everything (Rust extension, icons, TGUI, `deepquarry.dmb`). |
| `bin/server.cmd` | Build, then host a local server. |
| `bin/test.cmd` | Build and boot the unit-test world. |
| `bin/tgui-dev.cmd` | Run the TGUI hot-reload dev server. |
| `bin/clean.cmd` | Remove build outputs. |

On Linux use `tools/build/build.sh` with the same targets.

### Testing

`bin/test.cmd` runs the unit-test suite, and
`bash tools/dq_focused_test.sh /datum/unit_test/<name>` runs just the tests you
name. [doc/testing.md](doc/testing.md) covers every check CI runs and how to run
it locally. Compiling
`deepquarry.dme` directly in DreamMaker skips the asset and TGUI steps and is not
supported.

To host, open the built `deepquarry.dmb` in DreamDaemon with security set to
Trusted.

### Configuration

Copy every file from `config/example/` into `config/`, then edit `config.txt` and
`admins.txt`. Admin entries use the format `byondkey - Rank`, with the key in
lowercase.

The optional MySQL backend is configured in `config/dbconfig.txt`; schemas are in
`SQL/`.

When updating a live install, back up `config/` and `data/` first. They hold
server configuration, player preferences and bans.

---

### License

Code is licensed under the [GNU Affero General Public License v3](http://www.gnu.org/licenses/agpl.html)
(`LICENSE-AGPL3.txt`).

Code with a git authorship date before `1420675200 +0000` (2015/01/08 00:00) is
licensed under the GNU General Public License v3 (`LICENSE-GPL3.txt`). All later
code is AGPL v3 unless a commit states otherwise. If you host a server running
AGPL code, you must provide the full source, including your modifications, to its
users. See [why the AGPL](https://www.gnu.org/licenses/why-affero-gpl.html).

Files under `icons/goonstation/` and `sound/goonstation/`, and their
subdirectories, are licensed under
[Creative Commons BY-NC-SA 3.0](https://creativecommons.org/licenses/by-nc-sa/3.0)
(`LICENSE-CC-BY-NC-SA.txt`).

All other assets, including icons and sound, are under
[CC BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/) unless otherwise
indicated. Attributions are listed in [ATTRIBUTIONS.md](./ATTRIBUTIONS.md).
