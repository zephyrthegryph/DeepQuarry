//! `mouse_override`: BYOND's mouse and click procs are overridden in one place (doc/rewrite/final_api.html section 2 "The input inbox").
//!
//! `code/engine/kernel/entry.dm` overrides `Click`, `DblClick`, `MouseDrop`, `MouseDrag`, `MouseDown`, `MouseUp`, `MouseEntered`, `MouseExited`
//! and `MouseWheel` on `/atom` and `/client`, and `MouseDrop_T` (the engine's default drop) with it: each reads `usr` once, builds a typed
//! `/datum/input_event` and hands it to `input_submit()`. What a type does with its input is declared in its CAPABILITIES block (`click_on()`,
//! `double_click_on()`, `drag_onto()`, `drag_over()`, `hover()`, `tooltip()`, an `op()`), and the resolver finds it when the event resolves, on the
//! spot or from the inbox. A definition of any of those procs anywhere else (`/obj/x/Click()`, `/atom/movable/screen/y/proc/MouseDrop()`, a
//! `Click()` indented under a type path) would sit between the engine's override and the base and skip the inbox. A hard ban, no baseline; the
//! engine's file is exempt by path (`tools/ci/lint_scopes.toml`).

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "declare the input in the type's CAPABILITIES block: click_on(PROC_REF(x)), double_click_on(), drag_onto(PROC_REF(x), onto =), drag_over(), hover() or tooltip() (an op key works in their place); \
an input no entry takes goes on to the default handling, so a handler that wants it answers INPUT_FALLTHROUGH. Only code/engine/kernel/entry.dm overrides a native mouse proc (doc/rewrite/final_api.html section 2)";

static META: Meta = Meta {
    name: "mouse_override",
    group: "",
    label: "mouse_override",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "mouse_override", hint: HINT }],
    allow: &[],
    lists: &[],
};

const NAMES: &str = "Click|DblClick|MouseDrop|MouseDrop_T|MouseDrag|MouseDown|MouseUp|MouseEntered|MouseExited|MouseWheel";

struct MouseOverride {
    /// `/obj/x/Click(`, `/obj/x/proc/MouseDrop(`: the whole path is the definition.
    path_form: Pat,
    /// `Click(` or `proc/Click(` indented under a type path.
    block_form: Pat,
}

/// The leading tabs and spaces of a line, counted as one column each (the codebase indents with tabs).
fn indent_of(line: &str) -> usize {
    line.len() - line.trim_start_matches(['\t', ' ']).len()
}

/// A bare path segment line (`/obj/x`, `proc`, `verb`): a type block or a proc-kind block, as opposed to a proc, a var or a call.
fn is_bare_segment(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'/' || b == b'.')
}

impl Lint for MouseOverride {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        // The enclosing lines of the one being read: (indent, trimmed text), shallowest first.
        let mut stack: Vec<(usize, String)> = Vec::new();
        for (number, line) in f.code().numbered() {
            let text = line.trim();
            if text.is_empty() {
                continue;
            }
            let indent = indent_of(line);
            if indent == 0 {
                if self.path_form.is_match(text) {
                    out.site_msg("mouse_override", number, format!("{}: a native mouse proc is overridden outside code/engine/kernel/entry.dm", text));
                }
            } else if self.block_form.is_match(text) {
                // A definition only when every line above it that encloses it is a bare path (`/obj/x`, `proc`): a `Click()` in a proc body is a call.
                let mut chain: Vec<&(usize, String)> = Vec::new();
                let mut bound = indent;
                for entry in stack.iter().rev() {
                    if entry.0 < bound {
                        chain.push(entry);
                        bound = entry.0;
                    }
                }
                if !chain.is_empty() && chain.iter().all(|e| is_bare_segment(&e.1)) && chain.last().map(|e| e.1.starts_with('/')).unwrap_or(false) {
                    out.site_msg("mouse_override", number, format!("{}: a native mouse proc is overridden outside code/engine/kernel/entry.dm", text));
                }
            }
            while stack.last().map(|e| e.0 >= indent).unwrap_or(false) {
                stack.pop();
            }
            stack.push((indent, text.to_string()));
        }
    }
}

pub fn register(reg: &mut Registry) {
    let path_form = format!(r"^(?:/\w+)*/(?:proc/|verb/)?(?:{})\s*\(", NAMES);
    let block_form = format!(r"^(?:proc/|verb/)?(?:{})\s*\(", NAMES);
    reg.add(MouseOverride { path_form: Pat::new(&path_form), block_form: Pat::new(&block_form) });
}
