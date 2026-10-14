//! The two comment/string strippers every lint used, ported once.
//!
//! * [`code_only`] is `state_schema_lint.code_only`: blanks comments and string *contents*, keeps
//!   newlines and string delimiters (`""`), so the line structure survives. It is NOT
//!   length-preserving, and, like the Python, an unbalanced `'` swallows text up to the next `'`
//!   (including newlines). Findings must match the Python, so that behaviour is kept.
//! * [`sanitize`] is `sys_rules/_dx_dm.sanitize_text`: same byte length, same newlines, comments
//!   and string text blanked to spaces, code inside an embedded `[expr]` kept.
//!
//! Both are computed at most once per file ([`crate::tree::SourceFile::code`] / `clean`).

use std::sync::LazyLock;

use regex::Regex;

fn count_nl(b: &[u8]) -> usize {
    b.iter().filter(|&&c| c == b'\n').count()
}

fn find_bytes(hay: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    if from > hay.len() {
        return None;
    }
    hay[from..].windows(needle.len()).position(|w| w == needle).map(|p| p + from)
}

fn into_string(out: Vec<u8>) -> String {
    match String::from_utf8(out) {
        Ok(s) => s,
        Err(e) => String::from_utf8_lossy(e.as_bytes()).into_owned(),
    }
}

/// `state_schema_lint.code_only`.
pub fn code_only(text: &str) -> String {
    let b = text.as_bytes();
    let n = b.len();
    let mut out: Vec<u8> = Vec::with_capacity(n);
    let mut i = 0;
    while i < n {
        let c = b[i];
        if c == b'/' && b.get(i + 1) == Some(&b'/') {
            match b[i..].iter().position(|&x| x == b'\n') {
                Some(k) => i += k,
                None => i = n,
            }
            continue;
        }
        if c == b'/' && b.get(i + 1) == Some(&b'*') {
            let j = match find_bytes(b, b"*/", i + 2) {
                Some(j) => j + 2,
                None => n,
            };
            out.extend(std::iter::repeat(b'\n').take(count_nl(&b[i..j])));
            i = j;
            continue;
        }
        if c == b'{' && b.get(i + 1) == Some(&b'"') {
            let j = match find_bytes(b, b"\"}", i + 2) {
                Some(j) => j + 2,
                None => n,
            };
            out.extend_from_slice(b"\"\"");
            out.extend(std::iter::repeat(b'\n').take(count_nl(&b[i..j])));
            i = j;
            continue;
        }
        if c == b'"' {
            let mut j = i + 1;
            let mut depth = 0usize;
            while j < n {
                let d = b[j];
                if d == b'\\' {
                    if j + 1 < n && b[j + 1] == b'\n' {
                        out.push(b'\n');
                    }
                    j += 2;
                    continue;
                }
                if d == b'[' {
                    depth += 1;
                } else if d == b']' && depth > 0 {
                    depth -= 1;
                } else if d == b'"' && depth == 0 {
                    break;
                } else if d == b'\n' {
                    break;
                }
                j += 1;
            }
            out.extend_from_slice(b"\"\"");
            // A string cut off by the end of the line keeps its newline.
            i = if j < n && b[j] == b'\n' { j } else { j + 1 };
            continue;
        }
        if c == b'\'' {
            match b[i + 1..].iter().position(|&x| x == b'\'') {
                Some(k) => i = i + 1 + k + 1,
                None => i = n,
            }
            continue;
        }
        out.push(c);
        i += 1;
    }
    into_string(out)
}

static CODE_SPECIAL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"//|/\*|@\{"|@"|\{"|"|'"#).unwrap());
static EMBED_SPECIAL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"//|/\*|@\{"|@"|\{"|"|'|\[|\]"#).unwrap());
static BLOCK_SPECIAL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\*/|/\*").unwrap());
static STR_SPECIAL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"\\|"|\[|\n"#).unwrap());
static MSTR_SPECIAL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"\\|"\}|\["#).unwrap());

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Code,
    Embed,
    Block,
    Str,
    MStr,
}

fn blank_into(out: &mut Vec<u8>, chunk: &[u8]) {
    out.extend(chunk.iter().map(|&c| if c == b'\n' { b'\n' } else { b' ' }));
}

/// `_dx_dm.sanitize_text`: comments and string text blanked, embedded `[expr]` kept; same byte
/// length and same newlines as `text`.
pub fn sanitize(text: &str) -> String {
    let b = text.as_bytes();
    let n = b.len();
    let mut out: Vec<u8> = Vec::with_capacity(n);
    let mut i = 0;
    let mut stack: Vec<Mode> = Vec::new();
    while i < n {
        let top = *stack.last().unwrap_or(&Mode::Code);
        match top {
            Mode::Code | Mode::Embed => {
                let re = if top == Mode::Embed { &*EMBED_SPECIAL } else { &*CODE_SPECIAL };
                let Some(m) = re.find_at(text, i) else {
                    out.extend_from_slice(&b[i..]);
                    break;
                };
                out.extend_from_slice(&b[i..m.start()]);
                let tok = m.as_str();
                let j = m.end();
                match tok {
                    "//" => {
                        let k = b[j..].iter().position(|&x| x == b'\n').map(|p| p + j).unwrap_or(n);
                        out.extend(std::iter::repeat(b' ').take(k - m.start()));
                        i = k;
                    }
                    "/*" => {
                        stack.push(Mode::Block);
                        out.extend_from_slice(b"  ");
                        i = j;
                    }
                    "@\"" | "@{\"" => {
                        let close: &[u8] = if tok == "@{\"" { b"\"}" } else { b"\"" };
                        let mut k = find_bytes(b, close, j);
                        if close == b"\"" {
                            let nl = b[j..].iter().position(|&x| x == b'\n').map(|p| p + j);
                            let cut = match (k, nl) {
                                (None, _) => true,
                                (Some(kk), Some(nn)) => nn < kk,
                                _ => false,
                            };
                            if cut {
                                let kk = nl.unwrap_or(n);
                                out.push(b' ');
                                out.extend_from_slice(&tok.as_bytes()[1..]);
                                blank_into(&mut out, &b[j..kk]);
                                i = kk;
                                continue;
                            }
                        }
                        let kk = k.take().unwrap_or(n);
                        out.push(b' ');
                        out.extend_from_slice(&tok.as_bytes()[1..]);
                        blank_into(&mut out, &b[j..kk]);
                        let end = (kk + close.len()).min(n);
                        out.extend_from_slice(&b[kk..end]);
                        i = kk + close.len();
                    }
                    "{\"" => {
                        stack.push(Mode::MStr);
                        out.extend_from_slice(b"{\"");
                        i = j;
                    }
                    "\"" => {
                        stack.push(Mode::Str);
                        out.push(b'"');
                        i = j;
                    }
                    "'" => {
                        let mut k = j;
                        while k < n && b[k] != b'\'' && b[k] != b'\n' {
                            k += if b[k] == b'\\' { 2 } else { 1 };
                        }
                        let k = k.min(n - 1);
                        out.push(b'\'');
                        let spaces = (k as isize - m.start() as isize - 1).max(0) as usize;
                        out.extend(std::iter::repeat(b' ').take(spaces));
                        let last = if k > m.start() && b[k] == b'\'' {
                            b'\''
                        } else if b[k].is_ascii() {
                            b[k]
                        } else {
                            b' '
                        };
                        out.push(last);
                        i = k + 1;
                    }
                    "[" => {
                        stack.push(Mode::Embed);
                        out.push(b'[');
                        i = j;
                    }
                    _ => {
                        // "]" closes an embed
                        stack.pop();
                        out.push(b']');
                        i = j;
                    }
                }
            }
            Mode::Block => {
                let Some(m) = BLOCK_SPECIAL.find_at(text, i) else {
                    blank_into(&mut out, &b[i..]);
                    break;
                };
                blank_into(&mut out, &b[i..m.start()]);
                out.extend_from_slice(b"  ");
                if m.as_str() == "*/" {
                    stack.pop();
                } else {
                    stack.push(Mode::Block);
                }
                i = m.end();
            }
            Mode::Str | Mode::MStr => {
                let re = if top == Mode::MStr { &*MSTR_SPECIAL } else { &*STR_SPECIAL };
                let Some(m) = re.find_at(text, i) else {
                    blank_into(&mut out, &b[i..]);
                    break;
                };
                blank_into(&mut out, &b[i..m.start()]);
                let tok = m.as_str();
                match tok {
                    "\\" => {
                        let nxt = b.get(m.end()).copied();
                        out.push(b' ');
                        match nxt {
                            Some(b'\n') => out.push(b'\n'),
                            Some(_) => out.push(b' '),
                            None => {}
                        }
                        i = m.end() + usize::from(nxt.is_some());
                    }
                    "\"" => {
                        stack.pop();
                        out.push(b'"');
                        i = m.end();
                    }
                    "\"}" => {
                        stack.pop();
                        out.extend_from_slice(b"\"}");
                        i = m.end();
                    }
                    "[" => {
                        stack.push(Mode::Embed);
                        out.push(b'[');
                        i = m.end();
                    }
                    _ => {
                        // a newline ends an unterminated plain string: recover at the line end
                        stack.pop();
                        out.push(b'\n');
                        i = m.end();
                    }
                }
            }
        }
    }
    into_string(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn code_only_blanks_comments_and_strings() {
        let t = "spawn(1) // trailing\nto_chat(\"hello [x]\")\n/* a\nb */\nvar/x = 'icon.dmi'\n";
        let c = code_only(t);
        assert_eq!(c, "spawn(1) \nto_chat(\"\")\n\n\nvar/x = \n");
        assert_eq!(c.matches('\n').count(), t.matches('\n').count());
    }

    #[test]
    fn code_only_multiline_string_keeps_newlines() {
        let t = "x = {\"a\nb\nc\"}\ny = 1\n";
        let c = code_only(t);
        assert_eq!(c, "x = \"\"\n\n\ny = 1\n");
    }

    #[test]
    fn sanitize_is_same_length_and_keeps_embedded_code() {
        let t = "to_chat(\"hi [usr.name] there\") // note\nfoo(1)\n";
        let s = sanitize(t);
        assert_eq!(s.len(), t.len());
        assert!(s.contains("usr.name"));
        assert!(!s.contains("hi"));
        assert!(!s.contains("note"));
        assert!(s.contains("foo(1)"));
    }

    #[test]
    fn sanitize_block_comment_and_newlines() {
        let t = "a /* x\ny */ b\n";
        let s = sanitize(t);
        assert_eq!(s.len(), t.len());
        assert_eq!(s.matches('\n').count(), 2);
        assert!(s.contains('a') && s.contains('b'));
        assert!(!s.contains('x') && !s.contains('y'));
    }
}
