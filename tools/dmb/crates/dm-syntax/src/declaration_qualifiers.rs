//! Compiler-issued declaration-path qualifier projection. Consumes ONLY tokens
//! from the existing primary lexical pass; never lexes/parses source itself.
//! VarTypeFlags names/meaning: pinned SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc
//! dreammaker ast.rs583-593, parser.rs803-813 (GPL-3.0).
use crate::{Span, TokenKind, TokenWindow};
pub const CHECKER_VAR_FINAL: u8 = 16;
pub const CHECKER_VAR_PRIVATE: u8 = 32;
pub const CHECKER_VAR_PROTECTED: u8 = 64;
pub const CHECKER_VAR_MASK: u8 = CHECKER_VAR_FINAL | CHECKER_VAR_PRIVATE | CHECKER_VAR_PROTECTED;
pub const UNKNOWN_HEADER_QUALIFIERS: u8 = 255;
const VAR_NAMESPACE: u8 = 8;
const CONTAINER: u8 = 1;
const ABSOLUTE: u8 = 2;
fn flag(name: &str) -> u8 {
    match name {
        "final" | "SpacemanDMM_final" => CHECKER_VAR_FINAL,
        "SpacemanDMM_private" => CHECKER_VAR_PRIVATE,
        "SpacemanDMM_protected" => CHECKER_VAR_PROTECTED,
        _ => 0,
    }
}
/// Local path fact. A trailing variable NAME is excluded; a container's trailing
/// namespace component is included. Encountering `var` resets prior qualifiers,
/// exactly as the existing pinned declaration-path builder does.
pub(crate) fn primary_header_qualifiers(
    source: &str,
    tokens: TokenWindow<'_>,
    header: Span,
    has_children: bool,
) -> u8 {
    if source.get(header.range()).is_none() {
        return UNKNOWN_HEADER_QUALIFIERS;
    }
    let first = tokens.partition_point(|token| token.span.end <= header.start);
    let end = tokens.partition_point(|token| token.span.start < header.end);
    let Some(tokens) = tokens.range(first, end) else {
        return UNKNOWN_HEADER_QUALIFIERS;
    };
    let mut flags = 0;
    let mut saw_var = false;
    let mut pending = None;
    let mut saw_ident = false;
    let mut container = has_children;
    let mut leading = true;
    let mut absolute = false;
    let commit = |name: &str, flags: &mut u8, saw_var: &mut bool| {
        if name == "var" {
            *saw_var = true;
            *flags = 0;
        } else {
            *flags |= flag(name);
        }
    };
    for token in tokens.iter() {
        if token.span.start < header.start || token.span.end > header.end {
            return UNKNOWN_HEADER_QUALIFIERS;
        }
        if matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Comment | TokenKind::Newline
        ) {
            continue;
        }
        let text = token.text(source);
        if text == "/" {
            if leading {
                absolute = true;
            }
            if let Some(name) = pending.take() {
                commit(name, &mut flags, &mut saw_var);
            } else if !leading {
                return UNKNOWN_HEADER_QUALIFIERS;
            }
            leading = false;
            continue;
        }
        if token.kind == TokenKind::Ident {
            if pending.is_some() {
                container = false;
                break;
            } // native as/in suffix
            pending = Some(text);
            saw_ident = true;
            leading = false;
            continue;
        }
        // A top-level comma ends this first declaration path exactly as '='
        // does. The same primary group's later declarators need their own
        // native sibling path receipts; this proves no invented sibling flags.
        if matches!(text, "=" | "[" | "(" | "{" | ";" | "}" | ",") {
            container = false;
            break;
        }
        return UNKNOWN_HEADER_QUALIFIERS;
    }
    if !saw_ident {
        return UNKNOWN_HEADER_QUALIFIERS;
    }
    if container {
        if let Some(name) = pending {
            commit(name, &mut flags, &mut saw_var);
        }
    }
    flags
        | if saw_var { VAR_NAMESPACE } else { 0 }
        | if container { CONTAINER } else { 0 }
        | if absolute { ABSOLUTE } else { 0 }
}
/// Namespace inheritance over the EXISTING primary Item hierarchy. A bare child
/// outside a proved var namespace is Unknown, never an invented flags=0 proof.
pub fn inherit_header_qualifiers(local: u8, parent: Option<u8>) -> (u8, Option<u8>) {
    if local == UNKNOWN_HEADER_QUALIFIERS {
        return (UNKNOWN_HEADER_QUALIFIERS, None);
    }
    let flags = if local & VAR_NAMESPACE != 0 {
        local & CHECKER_VAR_MASK
    } else if local & ABSOLUTE != 0 {
        return (UNKNOWN_HEADER_QUALIFIERS, None);
    } else if let Some(parent) = parent {
        parent | (local & CHECKER_VAR_MASK)
    } else {
        return (UNKNOWN_HEADER_QUALIFIERS, None);
    };
    (flags, (local & CONTAINER != 0).then_some(flags))
}
#[cfg(test)]
mod tests {
    use super::*;
    fn local(source: &str, container: bool) -> u8 {
        let tokens = crate::lex_spans(source);
        assert!(tokens.diagnostics.is_empty());
        primary_header_qualifiers(
            source,
            TokenWindow::from_vec(&tokens.tokens),
            Span::new(0, source.len()),
            container,
        )
    }
    #[test]
    fn source_path_flags_are_issued_without_initializer_or_name_confusion() {
        assert_eq!(
            inherit_header_qualifiers(
                local(
                    "var/SpacemanDMM_private/datum/x = list(\"SpacemanDMM_protected\")",
                    false
                ),
                None
            )
            .0,
            CHECKER_VAR_PRIVATE
        );
        assert_eq!(
            inherit_header_qualifiers(local("var/SpacemanDMM_private", false), None).0,
            0
        );
        assert_eq!(
            inherit_header_qualifiers(local("/SpacemanDMM_private/var/x", false), None).0,
            0
        );
        assert_eq!(
            inherit_header_qualifiers(
                local("var/SpacemanDMM_private/SpacemanDMM_protected/x[2]", false),
                None
            )
            .0,
            CHECKER_VAR_PRIVATE | CHECKER_VAR_PROTECTED
        );
    }
    #[test]
    fn inherited_namespace_flags_are_original_context_not_header_string_search() {
        let (_, var) = inherit_header_qualifiers(local("var", true), None);
        let (_, private) = inherit_header_qualifiers(local("SpacemanDMM_private", true), var);
        assert_eq!(
            inherit_header_qualifiers(local("datum/x", false), private).0,
            CHECKER_VAR_PRIVATE
        );
        assert_eq!(
            inherit_header_qualifiers(local("x", false), None).0,
            UNKNOWN_HEADER_QUALIFIERS
        );
        assert_eq!(
            inherit_header_qualifiers(local("var/x", false), private).0,
            0
        );
        assert_eq!(
            inherit_header_qualifiers(local("/datum/x", false), private).0,
            UNKNOWN_HEADER_QUALIFIERS
        );
    }
    #[test]
    fn native_qualifier_projection_does_not_interpret_comment_or_default_bytes() {
        assert_eq!(
            inherit_header_qualifiers(
                local("var/x /* é漢 SpacemanDMM_private */ = 1", false),
                None
            )
            .0,
            0
        );
        assert_eq!(
            inherit_header_qualifiers(local("var/final/SpacemanDMM_protected/x", false), None).0,
            CHECKER_VAR_FINAL | CHECKER_VAR_PROTECTED
        );
        assert_eq!(
            inherit_header_qualifiers(local("var//x", false), None).0,
            UNKNOWN_HEADER_QUALIFIERS
        );
    }
}

#[cfg(test)]mod primary_comma_qualifier_tests{
 use super::*;
 fn actual(source:&str,container:bool)->u8{let tokens=crate::lex_spans(source);assert!(tokens.diagnostics.is_empty());primary_header_qualifiers(source,TokenWindow::from_vec(&tokens.tokens),Span::new(0,source.len()),container)}
 #[test]fn actual_primary_comma_ends_the_authored_first_variable_path_without_guessing_zero(){
  assert_eq!(inherit_header_qualifiers(actual("var/datum/first, second",false),None).0,0);
  assert_eq!(inherit_header_qualifiers(actual("var/SpacemanDMM_private/datum/first, second",false),None).0,CHECKER_VAR_PRIVATE);
  assert_eq!(inherit_header_qualifiers(actual("var/final/datum/first, second",false),None).0,CHECKER_VAR_FINAL);
  let namespace=inherit_header_qualifiers(actual("var/SpacemanDMM_protected",true),None).1;
  assert_eq!(inherit_header_qualifiers(actual("datum/first, second",false),namespace).0,CHECKER_VAR_PROTECTED);
  assert_eq!(inherit_header_qualifiers(actual("first, second",false),None).0,UNKNOWN_HEADER_QUALIFIERS,"no var context was proved");
  assert_eq!(inherit_header_qualifiers(actual("var//first, second",false),None).0,UNKNOWN_HEADER_QUALIFIERS);
 }
 #[test]fn primary_qualifier_comma_in_default_or_comment_cannot_add_path_flags(){
  assert_eq!(inherit_header_qualifiers(actual("var/first=list(1,SpacemanDMM_private)",false),None).0,0);
  assert_eq!(inherit_header_qualifiers(actual("var/first /* ,SpacemanDMM_private */ , second",false),None).0,0);
  assert_eq!(inherit_header_qualifiers(actual("var/first, SpacemanDMM_private/second",false),None).0,0,"later path is not the first declaration's qualifiers");
 }
}
