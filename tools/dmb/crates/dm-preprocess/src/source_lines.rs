use super::*;

/// Conservative identifier closure includes strings/interpolations, directive operands,
/// undefined names, and identifiers in transitive replacement text. Token pasting can
/// synthesize arbitrary names, so those files retain the whole environment checkpoint.
pub(super) fn macro_dependencies(
    source: &str,
    macros: &BTreeMap<String, Macro>,
) -> Option<Vec<String>> {
    pub(super) fn identifiers(text: &str, names: &mut BTreeSet<String>) -> bool {
        let mut chars = text.char_indices().peekable();
        while let Some((start, character)) = chars.next() {
            if character == '#' && text[start + 1..].trim_start().starts_with('#') {
                return false;
            }
            if character == '_' || character.is_alphabetic() {
                let mut end = start + character.len_utf8();
                while let Some(&(index, next)) = chars.peek() {
                    if next == '_' || next.is_alphabetic() || next.is_ascii_digit() {
                        end = index + next.len_utf8();
                        chars.next();
                    } else {
                        break;
                    }
                }
                names.insert(text[start..end].to_owned());
            }
        }
        true
    }
    let mut names = BTreeSet::new();
    if !identifiers(source, &mut names) || names.len() > 8192 {
        return None;
    }
    let mut visited = BTreeSet::new();
    loop {
        let pending: Vec<_> = names.difference(&visited).cloned().collect();
        if pending.is_empty() {
            break;
        }
        for name in pending {
            visited.insert(name.clone());
            if let Some(definition) = macros.get(&name) {
                if !identifiers(&definition.replacement, &mut names) {
                    return None;
                }
            }
        }
        // Bound metadata and adversarial replacement closures.
        if names.len() > 8192 {
            return None;
        }
    }
    Some(names.into_iter().collect())
}

pub(super) fn dependency_digest(
    names: Option<&[String]>,
    macro_hashes: &BTreeMap<String, [u8; 32]>,
    full: [u8; 32],
    directories: [u8; 32],
) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(directories);
    if let Some(names) = names {
        hasher.update(b"selective\0");
        for name in names {
            hasher.update((name.len() as u64).to_le_bytes());
            hasher.update(name.as_bytes());
            if let Some(hash) = macro_hashes.get(name) {
                hasher.update([1]);
                hasher.update(hash);
            } else {
                hasher.update([0]);
            }
        }
    } else {
        hasher.update(b"complete\0");
        hasher.update(full);
    }
    hasher.finalize().into()
}

pub(super) fn has_include_directive(source: &str) -> bool {
    source.lines().any(|line| {
        let Some(directive) = line.trim_start().strip_prefix('#') else {
            return false;
        };
        split_word(directive.trim_start()).0 == "include"
    })
}

pub(super) fn normalize(path: PathBuf) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                out.pop();
            }
            _ => out.push(part.as_os_str()),
        }
    }
    out
}

pub(super) struct LogicalLine {
    pub(super) text: String,
    pub(super) source_lines: usize,
}

pub(super) fn logical_lines(source: &str) -> Vec<LogicalLine> {
    let mut lines = Vec::new();
    let mut joined = String::new();
    let mut source_lines = 0;
    let mut state = LogicalState::default();
    for physical in source.split_inclusive('\n') {
        if physical.trim_start().starts_with('#')
            && !joined.trim_start().starts_with("#define ")
            && !joined.is_empty()
            && !state.open_literal
        {
            lines.push(LogicalLine {
                text: std::mem::take(&mut joined),
                source_lines,
            });
            source_lines = 0;
            state = LogicalState::default();
        }
        source_lines += 1;
        let content = physical.trim_end_matches(['\r', '\n']);
        if !state.open_block_string {
            if let Some(prefix) = content.trim_end().strip_suffix('\\') {
                joined.push_str(prefix);
                state = logical_state(&joined);
                continue;
            }
        }
        joined.push_str(physical);
        state = logical_state(&joined);
        if state.open_literal || (!joined.trim_start().starts_with('#') && state.open_expression) {
            continue;
        }
        lines.push(LogicalLine {
            text: std::mem::take(&mut joined),
            source_lines,
        });
        source_lines = 0;
        state = LogicalState::default();
    }
    if !joined.is_empty() {
        lines.push(LogicalLine {
            text: joined,
            source_lines,
        });
    }
    lines
}

/// Remove comments before line-oriented preprocessing. Keep every newline and
/// byte position so directives inside a block comment cannot become active.
pub(super) fn strip_source_comments(source: &str) -> Cow<'_, str> {
    let mut bytes = None;
    let _ = dm_syntax::visit_tokens(source, |token| {
        if token.kind != TokenKind::Comment {
            return;
        }
        let bytes = bytes.get_or_insert_with(|| source.as_bytes().to_vec());
        for byte in &mut bytes[token.span.range()] {
            if !matches!(*byte, b'\r' | b'\n') {
                *byte = b' ';
            }
        }
    });
    match bytes {
        None => Cow::Borrowed(source),
        Some(bytes) => {
            Cow::Owned(String::from_utf8(bytes).expect("comment removal preserves UTF-8"))
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct LogicalState {
    pub(super) open_literal: bool,
    pub(super) open_block_string: bool,
    pub(super) open_expression: bool,
}

/// One borrowed tokenization answers all continuation questions. The caller
/// retains this state until the joined text changes; token spans are temporary.
pub(super) fn logical_state(source: &str) -> LogicalState {
    if source.is_empty() {
        return LogicalState::default();
    }
    let mut last = None;
    let mut depth = 0isize;
    let diagnostics = dm_syntax::visit_tokens(source, |token| {
        match token.text(source) {
            "(" | "[" => depth += 1,
            ")" | "]" => depth -= 1,
            _ => {}
        }
        last = Some(token);
    });
    let open_literal = last.is_some_and(|token| {
        token.kind == TokenKind::String
            && diagnostics
                .iter()
                .any(|diagnostic| diagnostic.span.start == token.span.start)
    });
    let open_block_string = last.is_some_and(|token| {
        token.kind == TokenKind::String
            && token.text(source).starts_with("{\"")
            && token.span.end == source.len()
            && !token.text(source).ends_with("\"}")
    });
    LogicalState {
        open_literal,
        open_block_string,
        open_expression: depth > 0,
    }
}

#[cfg(test)]
#[path = "source_lines_tests.rs"]
mod lexical_allocation_tests;

pub(super) fn split_word(input: &str) -> (&str, &str) {
    let end = input.find(char::is_whitespace).unwrap_or(input.len());
    (&input[..end], input[end..].trim_start())
}

pub(super) fn parse_include(rest: &str) -> Option<PathBuf> {
    let rest = rest.trim();
    let inner = rest.strip_prefix('"')?.split('"').next()?;
    if inner.is_empty() {
        return None;
    }
    Some(PathBuf::from(inner.replace('\\', "/")))
}

pub(super) fn parse_define(rest: &str) -> Result<(String, Macro), String> {
    let rest = rest.trim_start();
    let end = rest
        .find(|c: char| !(c == '_' || c.is_ascii_alphanumeric()))
        .unwrap_or(rest.len());
    if end == 0 || rest[..end].chars().next().unwrap().is_ascii_digit() {
        return Err("invalid macro name".into());
    }
    let name = rest[..end].to_owned();
    let tail = &rest[end..];
    if let Some(args) = tail.strip_prefix('(') {
        let Some(close) = args.find(')') else {
            return Err("unterminated macro parameter list".into());
        };
        let parameters = if args[..close].trim().is_empty() {
            Vec::new()
        } else {
            args[..close]
                .split(',')
                .map(|s| s.trim().to_owned())
                .collect::<Vec<_>>()
        };
        let variadic = parameters.last().is_some_and(|name| name.ends_with("..."));
        if parameters
            .iter()
            .take(parameters.len().saturating_sub(1))
            .any(|name| name.ends_with("..."))
        {
            return Err("variadic macro parameter must be last".into());
        }
        let parameters = parameters
            .into_iter()
            .map(|name| {
                if name == "..." {
                    "__VA_ARGS__".to_owned()
                } else {
                    name.strip_suffix("...").unwrap_or(&name).to_owned()
                }
            })
            .collect::<Vec<_>>();
        if parameters
            .iter()
            .any(|s| s.is_empty() || !s.chars().all(|c| c == '_' || c.is_ascii_alphanumeric()))
        {
            return Err("invalid macro parameter".into());
        }
        Ok((
            name,
            Macro {
                parameters: Some(parameters),
                variadic,
                replacement: strip_macro_comments(&args[close + 1..]),
            },
        ))
    } else {
        Ok((
            name,
            Macro {
                parameters: None,
                variadic: false,
                replacement: strip_macro_comments(tail),
            },
        ))
    }
}
