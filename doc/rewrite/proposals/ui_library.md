# The DQ UI layer: one token set and one small component set on tgui-core

Status: landing in slices (2026-11-07). Slices 1-5 below are on master; section 6 is the open work.

## 1. Why

The DQ front end grew four surfaces that each styled the same things: the chat (`tgui-panel`), the stat panel
(`tgui-panel/statpanel`), the say popup (`tgui-say`) and tgui windows in the `console` theme. Before this work:

| Piece | Copies | Where |
|---|---|---|
| Tab rows | 4 | chat (tgui-core `Tabs` + its own CSS), stat panel (tgui-core `Tabs` + other CSS), Inspect sub-tabs (hand-rolled buttons), MC view tabs (tgui-core `Tabs` + a third CSS) |
| Title bar (name, subtitle, boxed close) | 2 | right-click menu, Inspect tab |
| Frame + scanline overlay | 3 | `ChatConsole.scss`, `statpanel.scss`, `themes/console.scss`, each with its own strength |
| tgui-core custom property block (`--button-*`, `--tab-*`, `--input-*`) | 3 | the same 30 lines in chat, stat panel and console theme |
| Speech-mode colours (Say, Me, OOC, ...) | 2 | `tgui-say/styles/colors.scss`, `tgui-panel/styles/components/ChatInput.scss` |
| Chat message stylesheets | 1 (done) | `tgchat/chat.scss` coloured by `chat-tokens.scss`; the chat has one theme, dark (the light/vchat themes were removed 2026-11) |
| Scanline-preference hook | 2 | `tgui/layouts/consoleTheme.ts`, `tgui-panel/consoleScanlines.ts` |

## 2. What the layer is

**Tokens** — `tgui/packages/tgui/styles/console.scss`. The console colours (`$console-panel`, `$console-border`,
`$console-accent`, `$console-button`, `$console-button-hover`, `$console-text`, `$console-muted`, `$console-dim`, ...), the font, the border
width, and the effect knobs as CSS custom properties with subtle defaults on `:root`:

| Knob | Controls |
|---|---|
| `--console-scanline-strength` | scanline darkness (0 = off; the lobby "Disable Scanlines" preference sets 0) |
| `--console-fringe-strength` | the red/green/blue phosphor stripes |
| `--console-glow` | box-shadow bloom round panels, the title bar, notice boxes |
| `--console-glow-inset` | a pane frame's inner bloom |
| `--console-vignette` | the lobby's darkened edges |

Mixins: `console-component-vars` (the tgui-core custom properties in console colours), `console-frame` (the pane's `::before` border
and `::after` scanlines), `console-scanlines`, `console-panel`, `console-glow`. The radio and speech-mode colours are
`tgui/styles/radio-colors.scss` (`$radio-colors`, `$mode-colors`). Chat message colours are `--chat-*` tokens per theme
(`tgui-panel/styles/tgchat/chat-tokens.scss`) read by one sheet (`tgchat/chat.scss`).

**Components** — `tgui/packages/tgui/dq/` (`import { Tabs, TitleBar, ListRow } from 'tgui/dq'`), styles in
`tgui/styles/dq/` (loaded through `dq/index.scss` by the tgui, chat and stat panel bundles). They live in the `tgui` package because
`tgui-panel` and `tgui-say` already depend on it; a separate workspace package would need a `bun install` and new links in every
worktree for no gain.

| Component | Use it for | Users |
|---|---|---|
| `Tabs` | any horizontal tab strip; `layout` wrap/scrollable/classic, `size="small"` for a sub-tab row, `onReorder` for drag-to-reorder, `afterTabs`/children for row content | chat tabs, stat panel tabs, Inspect sub-tabs, MC tabs, window dock tabs |
| `TitleBar`, `CloseButton` | a header with a name, a subtitle line and a boxed close | right-click menu, Inspect tab |
| `ListRow`, `ListRows` | a column of full-width choice rows, a blocked row with its reason | right-click menu |
| `moveBefore` | reorder helper for any drag list | `Tabs`, abilities grid |

## 3. Rules

1. **tgui-core first.** `Button`, `Section`, `Stack`, `Input`, `LabeledList`, `ProgressBar`, ... are used directly. The DQ layer adds
   only what tgui-core lacks or what DQ needs to look one way everywhere. Never fork or re-implement a tgui-core component.
2. **A pattern used by two surfaces is a DQ component.** Before writing a tab strip, a header with a close button, a choice list, a
   frame or an overlay, use the one in `tgui/dq`. If it does not fit, extend it (a prop, a variant) instead of styling a copy.
3. **No inline styles for colour, spacing, borders or fonts.** `style={{ color: ... }}`, `margin`, `padding`, `border*`, `fontSize`
   go in a stylesheet class or a tgui-core prop (`color=`, `mt=`, `p=`, `fontSize=`) that reads the tokens. Inline `style` is for
   values computed at runtime (a position, a width from data, a colour the server sends).
4. **Colours come from tokens.** A console surface reads `console.$console-*`; a chat message colour is a `--chat-*` token with a
   value in every chat theme's mixin; a radio or speech-mode colour comes from `radio-colors.scss`. No hex literal in a component
   stylesheet for a colour the palette already has.
5. **One knob per effect.** Scanlines, glow, fringe and vignette read the `--console-*` knobs; a surface never sets its own
   strength. Tone an effect by changing its default in `console.scss`.
6. **A theme is data.** A new theme sets tokens; it does not restyle components. Themes nothing selects are deleted (section 5).

## 4. Landed

| Slice | Commit | What |
|---|---|---|
| 1 | 79505d148a | Shared tab row (chat = stat panel), chat tabs clickable and reorderable, effect knobs, one frame mixin |
| 2 | 43682b70d0 | Four chat sheets -> `chat.scss` + `chat-tokens.scss` (132 tokens; verified per theme against the old compiled CSS) |
| 3 | 0a63e7fdaa | `tgui/dq`: Tabs, TitleBar, ListRow; right-click menu, Inspect and MC tabs on them; speech-mode colours shared; say popup on the console tokens |
| 4 | this commit | Dead themes and interfaces deleted; this document |

## 5. Deleted as unused

Themes no window, device or DM data names: `ntOS95`, `ntos_cat`, `ntos_darkmode`, `ntos_lightmode`, `ntos_spooky`, `ntos_synth`,
`ntos_terminal`, `pda-retro` (26 -> 18). `device_theme` is only ever `"ntos"`; the NIF theme list is `abductor`, `cardtable`,
`hackerman`, `malfunction`, `ntos`, `paper`, `retro`, `syndicate`.

Interfaces nothing opens: `AmControl` (the antimatter engine was deleted), `MechaLog` (no `interface("MechaLog")`).
The `Ntos*` program windows are
opened as `"Ntos" + name` (`code/library/ui/tgui/modules/_base.dm`), so a plain grep reports them unused; they are not.

## 6. Open work (not started)

- **Inline styles in interfaces.** 586 `style={{` sites in 171 interface files (multi-line objects included). Worst:
  `deepquarry/PreferencesMenu/editors/MindBodyEditor.tsx` (42), `BodyMarkingsEditor.tsx` (25), `LoadoutBuilder.tsx` (23),
  `deepquarry/PreferencesMenu/colors.tsx` (19), `DisposalBin.tsx` (17), `deepquarry/PreferencesMenu/LooksPage.tsx` (16),
  `editors/SpeciesPicker.tsx` (15), `RIGSuit/animated_logos/Commonwealth.tsx` (15, SVG positions: legitimate), `DQMedicalBook.tsx` (13),
  `editors/OccupationEditor.tsx` (12), `editors/TraitPicker.tsx` (11), `editors/RobotChassisPicker.tsx` (11). The most common
  properties are `borderRadius`, `color`, `fontSize`, `border` and margins: rule 3 applies when a file is next touched.
- **The window dock frame** (`tgui-panel/statpanel/DockArea.tsx`) draws its own group header; it should wear `TitleBar` once the
  docking work settles (owned by the window-system lane, `window_system.md`).
- **The settings panel** uses tgui-core vertical `Tabs` directly; `dq/Tabs` is horizontal only. Add a vertical variant when a second
  vertical strip appears.
- **The tgui `Window` title bar** (`tgui/layouts/TitleBar.tsx`) stays tgui's; the console theme styles it through the tokens.
- **18 themes remain.** Most are flavour themes for one machine (`abductor`, `algae`, `bingle`, `crtsoul`, `spookyconsole`); each
  should become a token block over the console look rather than a full restyle.
