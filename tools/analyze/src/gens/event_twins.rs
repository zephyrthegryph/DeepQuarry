//! `analyze gen event_twins` -> `code/engine/_generated/event_twins.dm` (E4: the PUBLISH / OM_EMIT twins).
//!
//! During phases 2 and 3 old and new forms run side by side (doc/rewrite/final_api.html, "Coexistence rules"): PUBLISH and on_notice against
//! OM_EMIT and om_hook, both ways, each side emitting the other's twin, generated from `tools/dx/codemods/om_event_map.json`. This reads that map
//! and writes one row per after-fact event that has a notice (`target` is `/datum/notice/x`, no emit site reads its result):
//!
//! `GLOBAL_LIST_INIT(event_twin_notice, list(/datum/om/event/x = list(/datum/notice/x, "field", ...)))`
//!
//! The row's fields are the notice's vars in the order of the event's New() arguments. code/engine/actions/twins.dm builds the reverse table
//! and does the bridging. The last event deletes the map (step A7), and with it this generator's rows.

use std::collections::BTreeMap;

use crate::sem::gen::{GenCx, GenOut, Generator};

const MAP: &str = "tools/dx/codemods/om_event_map.json";

#[derive(Default)]
struct Row {
    target: String,
    notice_fields: Vec<String>,
    reads_result: bool,
}

/// The map is the regular output of `json.dumps(indent=1, sort_keys=True)`: event keys at one space of indent, scalar rows at two, list items at three.
fn parse(text: &str) -> BTreeMap<String, Row> {
    let mut rows: BTreeMap<String, Row> = BTreeMap::new();
    let mut cur: Option<String> = None;
    let mut list_key: Option<String> = None;
    for line in text.lines() {
        let indent = line.len() - line.trim_start().len();
        let t = line.trim();
        if indent == 1 && t.ends_with(": {") {
            let k = t.trim_end_matches(": {").trim_matches('"').to_string();
            rows.insert(k.clone(), Row::default());
            cur = Some(k);
            list_key = None;
            continue;
        }
        let Some(k) = &cur else { continue };
        let row = rows.get_mut(k).unwrap();
        if indent == 2 {
            list_key = None;
            if let Some(rest) = t.strip_prefix("\"target\": ") {
                row.target = rest.trim_end_matches(',').trim_matches('"').to_string();
            } else if let Some(rest) = t.strip_prefix("\"reads_result\": ") {
                row.reads_result = rest.trim_end_matches(',') == "true";
            } else if t.starts_with("\"notice_fields\": [") {
                list_key = Some("notice_fields".into());
            }
        } else if indent == 3 && list_key.as_deref() == Some("notice_fields") {
            row.notice_fields.push(t.trim_end_matches(',').trim_matches('"').to_string());
        }
    }
    rows
}

struct EventTwins;

impl Generator for EventTwins {
    fn name(&self) -> &'static str {
        "event_twins"
    }

    fn output(&self) -> &'static str {
        "event_twins.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let Ok(text) = std::fs::read_to_string(cx.root.join(MAP)) else {
            out.diag(MAP, 1, "the event map is missing");
            return;
        };
        let rows = parse(&text);
        // A notice type only counts when some file declares it.
        let mut declared: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
        for f in cx.tree.select(&crate::tree::CODE_DM) {
            if f.rel == "code/engine/_generated/event_twins.dm" {
                continue;
            }
            let t = f.text();
            if !t.contains("/datum/notice/") {
                continue;
            }
            for l in t.lines() {
                if l.starts_with("/datum/notice/") && !l.contains(|c: char| c.is_whitespace() || c == '(') && !l.contains("/proc") {
                    declared.insert(l.trim().to_string());
                }
            }
        }
        out.line("GLOBAL_LIST_INIT(event_twin_notice, list(");
        let wanted: Vec<(&String, &Row)> = rows.iter().filter(|(_, r)| r.target.starts_with("/datum/notice/") && !r.reads_result && declared.contains(&r.target)).collect();
        for (i, (event, row)) in wanted.iter().enumerate() {
            let mut parts = vec![row.target.clone()];
            parts.extend(row.notice_fields.iter().map(|f| format!("\"{}\"", f)));
            out.line(format!("\t{} = list({}){}", event, parts.join(", "), if i + 1 == wanted.len() { "" } else { "," }));
        }
        out.line("))");
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(EventTwins));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_map_rows() {
        let text = "{\n \"/datum/om/event/a\": {\n  \"emits\": [],\n  \"notice_fields\": [\n   \"x\",\n   \"y_\"\n  ],\n  \"reads_result\": false,\n  \"target\": \"/datum/notice/a\"\n },\n \"/datum/om/event/b\": {\n  \"reads_result\": true,\n  \"target\": \"review\"\n }\n}\n";
        let rows = parse(text);
        assert_eq!(rows["/datum/om/event/a"].target, "/datum/notice/a");
        assert_eq!(rows["/datum/om/event/a"].notice_fields, vec!["x", "y_"]);
        assert!(rows["/datum/om/event/b"].reads_result);
    }
}
