//! `in_precedence`: an `in` expression must not share a parenthesis level with another operator.
//!
//! In DreamMaker `in` is the loosest operator of all (looser than `=`, `?:`, `||`): `!x in L` is
//! `(!x) in L`, `a && b in L` is `(a && b) in L`, `var/v = x in L` is `(var/v = x) in L`, and its right
//! operand swallows everything tighter: `x in L || y` is `x in (L || y)` and `x in L ? a : b` is
//! `x in (L ? a : b)`. Every such site compiles and silently computes something else.
//!
//! The rule `mixed`: an `in` token (outside a `for(...)` header, a verb argument with `as`, and the
//! `locate(...) in X` form, which binds as one unit) has another operator at its own parenthesis level
//! and comma-separated segment, before or after it. Parenthesize the `in` expression: `(x in L) || y`.
//! The check is per line; a condition continued over several lines is judged line by line.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::{SourceFile, CODE_DM};

static META: Meta = Meta {
    name: "in_precedence",
    group: "",
    label: "in_precedence",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "mixed",
        hint: "`in` is the loosest DM operator: `!x in L` is `(!x) in L`, `x in L || y` is `x in (L || y)`, `var/v = x in L` stores x. Write `(x in L)` and combine that",
    }],
    allow: &[],
    lists: &[],
};

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Word,
    Op,
    Open,
    Close,
}

struct Tok<'a> {
    kind: Kind,
    text: &'a str,
    /// Id of the bracket group this token sits in directly (0 = the line itself).
    group: usize,
    /// Comma-separated segment within that group.
    seg: usize,
    /// For a Close: the token index of its Open (if seen on this line).
    opener: Option<usize>,
}

fn is_word_byte(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_'
}

fn lex(line: &str) -> Vec<Tok<'_>> {
    let b = line.as_bytes();
    let mut toks: Vec<Tok> = Vec::new();
    // (group id, opener token index, current segment)
    let mut stack: Vec<(usize, usize, usize)> = vec![(0, usize::MAX, 0)];
    let mut next_group = 1;
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c.is_ascii_whitespace() {
            i += 1;
            continue;
        }
        let (group, seg) = {
            let top = stack.last().unwrap();
            (top.0, top.2)
        };
        if is_word_byte(c) {
            let s = i;
            while i < b.len() && (is_word_byte(b[i]) || b[i] == b'.') {
                i += 1;
            }
            toks.push(Tok { kind: Kind::Word, text: &line[s..i], group, seg, opener: None });
            continue;
        }
        match c {
            b'(' | b'[' | b'{' => {
                let idx = toks.len();
                toks.push(Tok { kind: Kind::Open, text: &line[i..i + 1], group, seg, opener: None });
                stack.push((next_group, idx, 0));
                next_group += 1;
                i += 1;
            }
            b')' | b']' | b'}' => {
                let opener = if stack.len() > 1 { Some(stack.pop().unwrap().1) } else { None };
                let (g, s) = {
                    let top = stack.last().unwrap();
                    (top.0, top.2)
                };
                toks.push(Tok { kind: Kind::Close, text: &line[i..i + 1], group: g, seg: s, opener });
                i += 1;
            }
            b',' => {
                stack.last_mut().unwrap().2 += 1;
                i += 1;
            }
            // Path separators, safe-navigation, the ternary's colon, the macro hash and the rest carry no precedence here.
            b'/' | b':' | b'#' | b'\\' | b';' | b'@' | b'.' | b'"' | b'\'' | b'`' | b'$' => i += 1,
            b'?' if matches!(b.get(i + 1), Some(b'.') | Some(b'[')) => i += 1,
            _ => {
                let two = if i + 1 < b.len() { &line[i..i + 2] } else { "" };
                let len = if matches!(two, "&&" | "||" | "==" | "!=" | "<=" | ">=" | "<<" | ">>" | "**" | "<>") { 2 } else { 1 };
                if line.is_char_boundary(i + len) {
                    toks.push(Tok { kind: Kind::Op, text: &line[i..i + len], group, seg, opener: None });
                }
                i += len.max(1);
            }
        }
    }
    toks
}

struct InPrecedence;

impl Lint for InPrecedence {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        for (i, line) in f.code().lines().enumerate() {
            if !line.contains("in") {
                continue;
            }
            let toks = lex(line);
            for (k, t) in toks.iter().enumerate() {
                if t.kind != Kind::Word || t.text != "in" {
                    continue;
                }
                // locate(...) in X is one form.
                if k > 0 && toks[k - 1].kind == Kind::Close {
                    if let Some(o) = toks[k - 1].opener {
                        if o > 0 && toks[o - 1].kind == Kind::Word && toks[o - 1].text == "locate" {
                            continue;
                        }
                    }
                }
                // The for(...) header and verb/proc arguments (`as mob in view()`) are syntax, not an expression.
                let group_open = group_opener(&toks, t.group);
                if group_open.is_some_and(|o| o > 0 && toks[o - 1].kind == Kind::Word && toks[o - 1].text == "for") {
                    continue;
                }
                let same = |u: &&Tok| u.group == t.group && u.seg == t.seg;
                if toks.iter().filter(same).any(|u| u.kind == Kind::Word && u.text == "as") {
                    continue;
                }
                if toks.iter().filter(same).any(|u| u.kind == Kind::Op) {
                    out.site("mixed", i + 1);
                    break;
                }
            }
        }
    }
}

/// The token index of the opener of bracket group `group` (None for the line level).
fn group_opener(toks: &[Tok], group: usize) -> Option<usize> {
    if group == 0 {
        return None;
    }
    // Groups are numbered in the order their openers appear, starting at 1.
    toks.iter().enumerate().filter(|(_, t)| t.kind == Kind::Open).nth(group - 1).map(|(k, _)| k)
}

pub fn register(reg: &mut Registry) {
    reg.add(InPrecedence);
}
