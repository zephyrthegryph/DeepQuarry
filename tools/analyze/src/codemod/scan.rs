//! Call-node scanner: turns the text of a call (`name(a, b, c = d)`) into a node with byte spans for
//! the callee, the parentheses and every argument.
//!
//! The dreammaker AST says WHERE a call is (its line and column) and how many arguments it has; it
//! has no end spans. This scanner finds the spans on the file's own text, using
//! [`crate::strip::sanitize`] (same byte length as the text; comments and string text blanked, the
//! `[expr]` inside a string kept) so a comma or a parenthesis inside a string or a comment is never
//! structure. Argument spans are trimmed of whitespace and comments: an edit that replaces or
//! brackets a span never touches the comment beside it.

/// A half-open byte range into the file text.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

impl Span {
    pub fn text<'a>(&self, src: &'a str) -> &'a str {
        &src[self.start..self.end]
    }
    pub fn len(&self) -> usize {
        self.end - self.start
    }
    pub fn is_empty(&self) -> bool {
        self.end == self.start
    }
}

/// One argument of a call.
#[derive(Clone, Debug)]
pub struct Arg {
    /// The whole argument, trimmed (for `a = b`, all of it).
    pub span: Span,
    /// `Some((name, value span))` for a named argument at the top level of the call.
    pub named: Option<(String, Span)>,
    /// The separator after this argument: from the end of `span` through the comma (or to the closing
    /// parenthesis for the last one), whitespace and comments included.
    pub trailing: Span,
}

impl Arg {
    /// The text the argument contributes as a value (the `b` of `a = b`).
    pub fn value_span(&self) -> Span {
        self.named.as_ref().map(|(_, v)| *v).unwrap_or(self.span)
    }
}

/// A call as the scanner sees it.
#[derive(Clone, Debug)]
pub struct CallNode {
    pub name: Span,
    pub open: usize,
    /// Byte offset of the closing parenthesis.
    pub close: usize,
    pub args: Vec<Arg>,
}

impl CallNode {
    /// The whole call, from the callee to the closing parenthesis inclusive.
    pub fn whole(&self) -> Span {
        Span { start: self.name.start, end: self.close + 1 }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum ScanError {
    /// The text at the offset is not `name(`.
    NotACall,
    /// Parentheses, brackets or braces do not balance before the end of the file.
    Unbalanced,
}

fn is_ident(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// True when `name` starts at `off` as a whole identifier (the byte before is not an identifier byte
/// or a `.`/`:`, i.e. it is an unscoped call).
pub fn is_unscoped_ident_at(text: &str, off: usize, name: &str) -> bool {
    let b = text.as_bytes();
    if !text[off..].starts_with(name) {
        return false;
    }
    if off > 0 {
        let p = b[off - 1];
        if is_ident(p) || p == b'.' || p == b':' || p == b'/' {
            return false;
        }
    }
    !b.get(off + name.len()).copied().map(is_ident).unwrap_or(false)
}

/// Scans the call whose callee starts at `name_off` (a whole identifier `name`, then optional
/// blanks, then `(`). `clean` is `sanitize(text)`.
pub fn scan_call(text: &str, clean: &str, name_off: usize, name: &str) -> Result<CallNode, ScanError> {
    let cb = clean.as_bytes();
    if !is_unscoped_ident_at(text, name_off, name) {
        return Err(ScanError::NotACall);
    }
    let mut i = name_off + name.len();
    while i < cb.len() && (cb[i] == b' ' || cb[i] == b'\t') {
        i += 1;
    }
    if cb.get(i) != Some(&b'(') {
        return Err(ScanError::NotACall);
    }
    let open = i;
    // Walk to the matching parenthesis, splitting at top-level commas.
    let mut depth: Vec<u8> = Vec::new();
    let mut seps: Vec<usize> = Vec::new();
    let mut close = None;
    let mut j = open;
    while j < cb.len() {
        match cb[j] {
            b'(' | b'[' | b'{' => depth.push(cb[j]),
            b')' | b']' | b'}' => {
                let want = match cb[j] {
                    b')' => b'(',
                    b']' => b'[',
                    _ => b'{',
                };
                if depth.pop() != Some(want) {
                    return Err(ScanError::Unbalanced);
                }
                if depth.is_empty() {
                    close = Some(j);
                    break;
                }
            }
            b',' if depth.len() == 1 => seps.push(j),
            _ => {}
        }
        j += 1;
    }
    let Some(close) = close else { return Err(ScanError::Unbalanced) };
    // Slice the arguments between the separators.
    let mut bounds: Vec<(usize, usize)> = Vec::new();
    let mut from = open + 1;
    for &s in &seps {
        bounds.push((from, s));
        from = s + 1;
    }
    bounds.push((from, close));
    let blank_only = bounds.len() == 1 && clean[bounds[0].0..bounds[0].1].trim().is_empty();
    let mut args = Vec::new();
    if !blank_only {
        for (idx, &(a, b)) in bounds.iter().enumerate() {
            let seg = &clean[a..b];
            let lead = seg.len() - seg.trim_start().len();
            let trail = seg.len() - seg.trim_end().len();
            let (s, e) = if seg.trim().is_empty() { (a, a) } else { (a + lead, b - trail) };
            let span = Span { start: s, end: e };
            let named = named_arg(clean, span);
            let tend = if idx + 1 < bounds.len() { b + 1 } else { b };
            args.push(Arg { span, named, trailing: Span { start: e, end: tend.max(e) } });
        }
    }
    Ok(CallNode { name: Span { start: name_off, end: name_off + name.len() }, open, close, args })
}

/// `name = value` at the top level of an argument (not `==`, `<=`, `>=`, `!=`).
fn named_arg(clean: &str, span: Span) -> Option<(String, Span)> {
    let seg = &clean[span.start..span.end];
    let b = seg.as_bytes();
    let mut i = 0;
    if b.is_empty() || !(b[0].is_ascii_alphabetic() || b[0] == b'_') {
        return None;
    }
    while i < b.len() && is_ident(b[i]) {
        i += 1;
    }
    let name_end = i;
    while i < b.len() && (b[i] == b' ' || b[i] == b'\t') {
        i += 1;
    }
    if b.get(i) != Some(&b'=') || b.get(i + 1) == Some(&b'=') {
        return None;
    }
    i += 1;
    while i < b.len() && b[i].is_ascii_whitespace() {
        i += 1;
    }
    Some((seg[..name_end].to_string(), Span { start: span.start + i, end: span.end }))
}

/// Offsets where `name(` occurs as an unscoped call in `clean` (comments and strings blanked), in
/// order. Used to find calls the AST did not report (a macro body, an inactive `#if`).
pub fn call_offsets(clean: &str, name: &str) -> Vec<usize> {
    let mut out = Vec::new();
    let b = clean.as_bytes();
    let mut from = 0;
    while let Some(p) = clean[from..].find(name) {
        let off = from + p;
        from = off + name.len();
        if !is_unscoped_ident_at(clean, off, name) {
            continue;
        }
        let mut k = off + name.len();
        while k < b.len() && (b[k] == b' ' || b[k] == b'\t') {
            k += 1;
        }
        if b.get(k) == Some(&b'(') {
            out.push(off);
        }
    }
    out
}

/// Offsets where `name` occurs as a whole identifier that is NOT a call (`PROC_REF(name)`, a
/// definition, a passed-around reference).
pub fn mention_offsets(clean: &str, name: &str) -> Vec<usize> {
    let mut out = Vec::new();
    let b = clean.as_bytes();
    let mut from = 0;
    while let Some(p) = clean[from..].find(name) {
        let off = from + p;
        from = off + name.len();
        if off > 0 && (is_ident(b[off - 1])) {
            continue;
        }
        if b.get(off + name.len()).copied().map(is_ident).unwrap_or(false) {
            continue;
        }
        let mut k = off + name.len();
        while k < b.len() && (b[k] == b' ' || b[k] == b'\t') {
            k += 1;
        }
        if b.get(k) != Some(&b'(') {
            out.push(off);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strip::sanitize;

    fn scan(src: &str, name: &str) -> Result<CallNode, ScanError> {
        let clean = sanitize(src);
        scan_call(src, &clean, src.find(name).unwrap(), name)
    }

    #[test]
    fn splits_at_top_level_commas_only() {
        let src = "om_after(src, list(1, 2), \"a, b\", PROC_REF(x)) // tail, with comma";
        let n = scan(src, "om_after").unwrap();
        let t: Vec<&str> = n.args.iter().map(|a| a.span.text(src)).collect();
        assert_eq!(t, vec!["src", "list(1, 2)", "\"a, b\"", "PROC_REF(x)"]);
        assert_eq!(&src[n.close..n.close + 1], ")");
    }

    #[test]
    fn comments_between_arguments_are_outside_the_spans() {
        let src = "f(a, // note, here\n   b /* c, d */, c)";
        let n = scan(src, "f").unwrap();
        let t: Vec<&str> = n.args.iter().map(|a| a.span.text(src)).collect();
        assert_eq!(t, vec!["a", "b", "c"]);
    }

    #[test]
    fn named_arguments_and_comparisons() {
        let src = "f(a, user = M, x == y, z <= 3)";
        let n = scan(src, "f").unwrap();
        assert_eq!(n.args[1].named.as_ref().unwrap().0, "user");
        assert!(n.args[2].named.is_none());
        assert!(n.args[3].named.is_none());
    }

    #[test]
    fn empty_call_has_no_arguments_and_embedded_expressions_balance() {
        assert!(scan("f()", "f").unwrap().args.is_empty());
        let src = "f(\"x [g(1, 2)] y\", b)";
        assert_eq!(scan(src, "f").unwrap().args.len(), 2);
    }

    #[test]
    fn unbalanced_and_scoped_calls_are_refused() {
        assert_eq!(scan("f(a, (b)", "f").unwrap_err(), ScanError::Unbalanced);
        let clean = sanitize("x.f(a)");
        assert_eq!(scan_call("x.f(a)", &clean, 2, "f").unwrap_err(), ScanError::NotACall);
    }

    #[test]
    fn occurrence_finders_separate_calls_from_mentions() {
        let src = "om_after(a); PROC_REF(om_after); x.om_after(1); my_om_after(2);";
        let clean = sanitize(src);
        assert_eq!(call_offsets(&clean, "om_after"), vec![0]);
        assert_eq!(mention_offsets(&clean, "om_after").len(), 1);
    }
}
