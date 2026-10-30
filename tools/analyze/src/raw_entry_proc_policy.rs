//! Existing unique global-entry-proc raw first-statement projection.
//! No general declaration/parser/model or semantic type lookup.
use crate::raw_marker_policy::{matching_paren, split_args};
pub const ENTRY_PROC: &str = "ENTRY_PROC";
pub(crate) const ENTRY_CALLS: &[&str] = &[
    "op(",
    "extend(",
    "interface(",
    "ui_shape(",
    "on_notice(",
    "on_change(",
    "without(",
    "configure(",
];
#[derive(Default)]
pub struct Head(Option<(String, u32)>);
impl Head {
    pub fn begin(&mut self, line: &str, ln: u32) {
        self.0 = crate::pat_match!(r"^/proc/(\w+)\([^)]*\)\s*$")
            .captures(line)
            .map(|m| (m.s(1).to_string(), ln));
    }
    pub fn take(&mut self) -> Option<(String, u32)> {
        self.0.take()
    }
}
pub struct Projection {
    pub line: u32,
    pub args: Vec<String>,
    pub body: String,
    pub body_offset: usize,
}
pub fn project_first_return(
    stripped: &str,
    starts: &[u32],
    ln0: usize,
    line: &str,
    t: &str,
    name: String,
    head_line: u32,
) -> Option<Projection> {
    let Some(rest) = t.strip_prefix("return") else {
        return None;
    };
    let rest = rest.trim_start();
    let Some(after) = rest.strip_prefix("list") else {
        return None;
    };
    if !after.trim_start().starts_with('(') {
        return None;
    }
    let open = starts[ln0] as usize + (line.len() - rest.len()) + rest.find('(').unwrap();
    let Some(close) = matching_paren(stripped, open) else {
        return None;
    };
    let body = stripped[open + 1..close].to_string();
    if !ENTRY_CALLS.iter().any(|c| body.contains(c)) {
        return None;
    }
    let mut args = vec![name];
    args.extend(split_args(&body));
    Some(Projection {
        line: head_line,
        args,
        body,
        body_offset: open + 1,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_old_first_return_list_projection_keeps_original_head_and_body() {
        let source = "/proc/p()\n    return list(interface(\"X\"), ui_shape(a))\n";
        let starts = vec![0, 10, source.len() as u32];
        let line = source.split('\n').nth(1).unwrap();
        let mut head = Head::default();
        head.begin("/proc/p()", 1);
        let (name, ln) = head.take().unwrap();
        let p =
            project_first_return(source, &starts, 1, line, line.trim_start(), name, ln).unwrap();
        assert_eq!(p.line, 1);
        assert_eq!(p.args, ["p", "interface(\"X\")", "ui_shape(a)"]);
        assert_eq!(&source[p.body_offset..p.body_offset + p.body.len()], p.body);
        assert!(head.take().is_none());
    }
    #[test]
    fn a_nonreturn_first_statement_and_nonentry_list_do_not_issue_a_bundle() {
        let source = "/proc/p()\n    value = 1\n    return list(1)\n";
        let line = "    value = 1";
        assert!(project_first_return(
            source,
            &[0, 10, 24],
            1,
            line,
            line.trim_start(),
            "p".into(),
            1
        )
        .is_none());
        let source = "/proc/p()\n    return list(1)\n";
        let line = "    return list(1)";
        assert!(
            project_first_return(source, &[0, 10], 1, line, line.trim_start(), "p".into(), 1)
                .is_none()
        );
    }
}
