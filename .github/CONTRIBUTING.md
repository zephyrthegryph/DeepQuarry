# Contributing to DeepQuarry

:+1::tada: First off, thanks for taking the time to contribute! :tada::+1:

The following is a set of guidelines for contributing to DeepQuarry, a BYOND/DM
Space Station 13 codebase.

> **Note:** DeepQuarry is a **hard fork** of the Baystation → Polaris → VOREStation
> → CHOMPStation lineage. It no longer tracks or merges from any upstream, and the
> old "modular folder / upstream parity / edit marker" rules no longer apply — the
> codebase is a single unified tree. See `AGENTS.md` for the layout and build,
> and `doc/testing.md` for how to test.

#### Table Of Contents

[What should I know before I get started?](#what-should-i-know-before-i-get-started)

- [Code of Conduct](#code-of-conduct)

[How Can I Contribute?](#how-can-i-contribute)

- [Your First Code Contribution](#your-first-code-contribution)
- [Map Edits](#map-edits)
- [Coding Standards](#coding-standards)
- [Pull Requests](#pull-requests)
- [Git Commit Messages](#git-commit-messages)

[Licensing](#Licensing)

## What should I know before I get started?

### Code of Conduct

This project adheres to the Contributor Covenant [code of conduct](code_of_conduct.md).
By participating, you are expected to uphold this code.

## How Can I Contribute?

### Your First Code Contribution

Unsure where to begin? Start by looking through the issues tab. Read `AGENTS.md`
for the repository layout, build pipeline, and DM coding standards, and
`doc/testing.md` for running tests.

### Map Edits

- The live map is `maps/southern_cross/`. The unit tests boot the small
  `maps/virgo_minitest/`. Loaded templates live in `maps/submaps/` (engines,
  shelters), `maps/overmap/` and `maps/common*/`; expedition sites are generated
  at runtime from `maps/expedition/`. New atmospherics turf presets use the
  turfpacks system (`maps/~turfpacks/turfpacks.dm`).
- Map changes must be in TGM format. See the [Mapmerge2 Readme](../tools/mapmerge2/readme.md),
  or use [StrongDMM](../tools/StrongDMM/README.md) which saves TGM automatically.
- Map lint (`tools/maplint/lints/`) forbids some var-edits, such as `icon`, SMES
  state and cable directions. Make a subtype instead; Southern Cross keeps its
  map-specific subtypes in `maps/southern_cross/southern_cross_map_subtypes.dm`.
- Permanent maps cost a limited RAM budget — discuss new permanent maps / station
  designs with the community and staff (post a floor plan) before investing effort.

### Coding Standards

See `AGENTS.md` §3 for the full DM standards (absolute type paths, `..()` chaining,
list-allocation patterns, signal handlers, `qdel`, time defines, SQL parameters,
etc.). Highlights:

#### General

- **DO NOT** create joke or meme PRs. The GitHub is a technical-review space.
- **NO** CKEY / personally-locked content. Anything created must be available to all
  or none.
- **NO** "naming" in coded content — no shoutouts or naming a player as an owner.
  All names/descriptions/lore must be free of an individual's name. NPC names are fine.
- Avoid `usr` outside verb procs — use `src` or plumb the user reference through.
- Use defines where they exist (job/faction/access/channel names, sounds).
- Override via vars/subtypes rather than rewriting unrelated base code.
- New `.dm` files must be `#include`d in `deepquarry.dme`.

#### Scene devices

- A scene device/tool is any object or mechanic designed primarily to service
  in-game roleplay scenes (often private).
- Scene devices **MUST** avoid giving a purely mechanical/gameplay advantage.
- Scene devices **MUST** respect OOC consent where applicable.
- Scene devices **MUST** react to the 'OOC Escape' command where possible.

#### Art

- Editable icon sources are `*.png` + `*.dmi.toml`; the build repacks them into
  `icons/gen/`. Never hand-edit `icons/gen/`. Add new art as `png` + `dmi.toml` and
  point the object's `icon` / `icon_state` at it.

#### TGUI

- **ALL** TGUI files require TypeScript with properly defined types.
- Run `tools/build/build.sh lint tgui-test` (and `bin/tgui-fix.cmd` to auto-fix)
  before submitting.

### Pull Requests

- Your submission must pass CI (`doc/testing.md` lists every check and how to
  run it locally). If you think CI has a bug, open an issue. (Known CI gotcha: don't put comments in the middle of
  a multi-line `list(...)`.)
- WIP PRs must be marked `[WIP]` in the title **and** be a draft. They can't sit forever.
- A PR with many no-conflict merge commits ("merge from master" into your branch)
  can't be merged — squash or force-push your branch. PRs are squash-merged.
- Include a changelog YAML stub in `html/changelogs/` for user-visible changes
  (see `html/changelogs/example.yml`).

### Git Commit Messages

- Limit the first line to 72 characters or less.
- Reference issues and pull requests liberally.
- Use GitHub magic words ("Fixes #1928", "Closes #1928") to auto-close issues on merge.

## Licensing

DeepQuarry is licensed under the GNU Affero General Public License version 3
(`LICENSE-AGPL3.txt`).

Commits with a git authorship date prior to `1420675200 +0000` (2015/01/08 00:00)
are licensed under the GNU General Public License version 3 (`LICENSE-GPL3.txt`).

All commits whose authorship dates are not prior to `1420675200 +0000` are assumed
to be AGPL v3; if you wish to license under GPL v3, make this clear in the commit
message and any added files.
