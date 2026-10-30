//! `analyze gen ui_types` -> `tgui/packages/tgui/interfaces/generated/<Window>.d.ts`, one file per window an entry list declares.
//!
//! The E5 generator for the UI shape (doc/rewrite/final_api.html, section 13 "UI", section 15 "Tests", E0 proof 10): a type that declares
//! `interface("Window", ...)` and `ui_shape(var, ...)` in its `CAPABILITIES` list gets the TypeScript types of the window. The data type has one
//! field per name `ui_shape` lists, typed from the tracked var's schema (`TRACKED_SCHEMA(T, var, schema)` or `SCHEMA(T, var, schema)`), and the
//! doc comment on the field is the schema's own range text ("num 0..MAX_PUMP_PRESSURE step 1"), the text `schema_range_text()` returns at runtime,
//! so the two cannot disagree (proof 10 compares them). The actions type has one entry per `ui_act()` op of the list, with its `arg()`s typed the
//! same way. The generated TypeScript type of a numeric field stays `number`: the range is documentation, not a brand.
//!
//! These files live beside the ones `tools/build/lib/ui_types.ts` writes from the legacy UI tables; that script leaves a file that carries this
//! generator's header alone.

use crate::sem::gen::{GenCx, GenOut, Generator};

struct UiTypes;

impl Generator for UiTypes {
    fn name(&self) -> &'static str {
        "ui_types"
    }

    /// No DM file: the output is the TypeScript files of `files()`.
    fn output(&self) -> &'static str {
        ""
    }

    fn generate(&self, _cx: &GenCx, _out: &mut GenOut) {}

    fn files(&self, cx: &GenCx, out: &mut GenOut) -> Vec<(String, String)> {
        let markers: Vec<_> = cx
            .decls()
            .markers
            .iter()
            .map(|m| crate::declare_policy::Marker {
                name: &m.name,
                rel: &m.rel,
                line: m.line,
                body: &m.body,
                args: &m.args,
                body_offset: m.body_offset,
                line_starts: &m.line_starts,
            })
            .collect();
        let files = crate::ui_types_policy::generate(&crate::ui_types_policy::Input {
            markers: &markers,
            budget: None,
            poll: None,
        })
        .expect("legacy ui policy");
        for d in files.diags {
            out.diag(&d.rel, d.line, d.msg);
        }
        files.files
    }
}
#[cfg(test)]
use crate::ui_types_policy::{call_of, split_top, ts_type};
pub use crate::ui_types_policy::{describe, UI_TYPES_OUT};
pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(UiTypes));
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_range_text_is_the_runtime_text() {
        assert_eq!(
            describe("num(0, MAX_PUMP_PRESSURE, step = 1)"),
            "num 0..MAX_PUMP_PRESSURE step 1"
        );
        assert_eq!(describe("int(0, 10)"), "int 0..10");
        assert_eq!(describe("int(1)"), "int 1..");
        assert_eq!(describe("int()"), "int");
        assert_eq!(describe("schema_text(8)"), "text max 8");
        assert_eq!(describe("bool()"), "bool");
    }

    #[test]
    fn schemas_become_typescript_types() {
        assert_eq!(ts_type("num(0, 5)"), "number");
        assert_eq!(ts_type("enum(list(\"off\", \"on\"))"), "'off' | 'on'");
        assert_eq!(ts_type("list_of(int(0, 3))"), "number[]");
        assert_eq!(ts_type("schema_text(8)"), "string");
    }

    #[test]
    fn calls_split_at_the_top_level() {
        assert_eq!(
            split_top("\"a,b\", f(1, 2), x = [3, 4]"),
            vec!["\"a,b\"", "f(1, 2)", "x = [3, 4]"]
        );
        assert_eq!(call_of("op(\"x\", hand())"), Some(("op", "\"x\", hand()")));
    }
}
