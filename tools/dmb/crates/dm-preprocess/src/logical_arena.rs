//! One logical-line planner for borrowed file ranges and explicit continuations.
use crate::source_lines::{logical_state, LogicalState};
use std::ops::Range;

pub(crate) struct LogicalRange {
    pub range: Range<usize>,
    pub transformed: bool,
    pub source_lines: usize,
}
pub(crate) struct LogicalPlan {
    pub lines: Vec<LogicalRange>,
    pub transformed: String,
}
struct Pending {
    original: Range<usize>,
    transformed_start: Option<usize>,
    source_lines: usize,
    state: LogicalState,
}
impl Pending {
    fn text<'a>(&self, original: &'a str, transformed: &'a str) -> &'a str {
        match self.transformed_start {
            Some(start) => &transformed[start..],
            None => &original[self.original.clone()],
        }
    }
    fn finish(&mut self, plan: &mut LogicalPlan) {
        plan.lines.push(LogicalRange {
            range: self.transformed_start.map_or_else(
                || self.original.clone(),
                |start| start..plan.transformed.len(),
            ),
            transformed: self.transformed_start.is_some(),
            source_lines: self.source_lines,
        });
        self.source_lines = 0;
        self.transformed_start = None;
        self.original = self.original.end..self.original.end;
        self.state = LogicalState::default();
    }
}

pub(crate) fn plan(source: &str) -> LogicalPlan {
    let mut plan = LogicalPlan {
        lines: Vec::new(),
        transformed: String::new(),
    };
    let mut pending = Pending {
        original: 0..0,
        transformed_start: None,
        source_lines: 0,
        state: LogicalState::default(),
    };
    let mut offset = 0;
    for physical in source.split_inclusive('\n') {
        let joined = pending.text(source, &plan.transformed);
        if physical.trim_start().starts_with('#')
            && !joined.trim_start().starts_with("#define ")
            && !joined.is_empty()
            && !pending.state.open_literal
        {
            pending.finish(&mut plan);
        }
        if pending.source_lines == 0 {
            pending.original = offset..offset;
        }
        pending.source_lines += 1;
        let content = physical.trim_end_matches(['\r', '\n']);
        if let Some(prefix) = content.trim_end().strip_suffix('\\') {
            // Literal continuations belong to the shared string decoder. Keeping
            // the slash/newline lets it discard indentation rather than turn it
            // into literal tabs; raw literals must retain their own semantics.
            let mut candidate = pending.text(source, &plan.transformed).to_owned();
            candidate.push_str(content);
            if !logical_state(&candidate).open_literal {
                if pending.transformed_start.is_none() {
                    let start = plan.transformed.len();
                    plan.transformed.push_str(&source[pending.original.clone()]);
                    pending.transformed_start = Some(start);
                }
                plan.transformed.push_str(prefix);
                pending.original.end = offset + physical.len();
                pending.state = logical_state(pending.text(source, &plan.transformed));
                offset += physical.len();
                continue;
            }
        }
        if pending.transformed_start.is_some() {
            plan.transformed.push_str(physical);
        }
        pending.original.end = offset + physical.len();
        pending.state = logical_state(pending.text(source, &plan.transformed));
        offset += physical.len();
        if pending.state.open_literal
            || (!pending
                .text(source, &plan.transformed)
                .trim_start()
                .starts_with('#')
                && pending.state.open_expression)
        {
            continue;
        }
        pending.finish(&mut plan);
    }
    if !pending.text(source, &plan.transformed).is_empty() {
        pending.finish(&mut plan);
    }
    plan
}
