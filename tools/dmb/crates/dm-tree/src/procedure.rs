//! Parsing of the shared declaration model; data structures live in dm-ir.
use dm_ir::{
    ExpressionToken, Parameter, ProcedureSetting, ProcedureSignature, SettingOperation, SymbolId,
    SymbolTable, SymbolicExpression,
};
use dm_syntax::{Span, TokenKind};
mod header;
pub(crate) mod header_input;
use header::{HeaderView, LexedHeader};
pub(crate) use header_input::{HeaderAllocationReceipt, OriginalProcedureHeaders};
fn intern(symbols: &mut SymbolTable, text: &str) -> Result<SymbolId, String> {
    symbols.intern(text).map_err(|error| error.to_string())
}
pub(crate) fn expression(
    text: &str,
    symbols: &mut SymbolTable,
) -> Result<SymbolicExpression, String> {
    let lexed = LexedHeader::new(text);
    if !lexed.valid() {
        return Err("invalid expression tokens in procedure declaration".into());
    }
    expression_view(lexed.view(), symbols)
}
/// A variable input annotation follows its initializer, but is not part of it.
/// Use the shared lexer so quoted or nested `as` text remains expression text.
pub(crate) fn variable_initializer(text: &str) -> Result<&str, String> {
    let lexed = LexedHeader::new(text);
    if !lexed.valid() {
        return Err("invalid variable initializer tokens".into());
    }
    let end = lexed
        .view()
        .top_level()
        .into_iter()
        .find(|(token, _)| *token == "as")
        .map_or(text.len(), |(_, span)| span.start);
    Ok(text[..end].trim_end())
}
fn expression_view(
    view: HeaderView<'_>,
    symbols: &mut SymbolTable,
) -> Result<SymbolicExpression, String> {
    let mut tokens = Vec::new();
    for token in view.tokens() {
        if matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        ) {
            continue;
        }
        tokens.push(ExpressionToken {
            kind: token.kind,
            text: intern(symbols, view.spelling(token))?,
            relative_span: view.relative_span(token),
        });
    }
    if tokens.is_empty() {
        return Err("empty procedure declaration expression".into());
    }
    Ok(SymbolicExpression {
        tokens: tokens.into(),
    })
}
fn top_level_tokens(text: &str) -> Vec<(String, Span)> {
    LexedHeader::new(text)
        .view()
        .top_level()
        .into_iter()
        .map(|(text, span)| (text.to_owned(), span))
        .collect()
}
#[derive(Debug)]
pub(crate) struct SignatureError {
    pub(crate) message: String,
    pub(crate) source_span: Option<Span>,
    pub(crate) after_header: bool,
}
impl From<String> for SignatureError {
    fn from(message: String) -> Self {
        Self {
            message,
            source_span: None,
            after_header: false,
        }
    }
}
impl From<&str> for SignatureError {
    fn from(message: &str) -> Self {
        message.to_owned().into()
    }
}
impl From<SignatureError> for String {
    fn from(error: SignatureError) -> Self {
        error.message
    }
}
fn parameter(
    view: HeaderView<'_>,
    start: usize,
    symbols: &mut SymbolTable,
) -> Result<Parameter, SignatureError> {
    let text = view.text();
    let (equal, annotation, source) = view.parameter_markers()?;
    let positions = [
        equal,
        annotation.map(|span| span.start),
        source.map(|span| span.start),
    ];
    let name_end = positions
        .iter()
        .flatten()
        .copied()
        .min()
        .unwrap_or(text.len());
    let declaration = text[..name_end].trim();
    // In BYOND a leading slash here issues an absolute type declaration and
    // contributes no argument. The signature-only model cannot issue that
    // declaration; do not silently reinterpret it as a relative typed argument.
    if declaration.starts_with('/') {
        return Err("unsupported absolute declaration in procedure argument list: requires an issued type declaration, not a parameter".into());
    }
    let declaration = declaration.strip_prefix("var/").unwrap_or(declaration);
    let path = declaration.split('[').next().unwrap().trim();
    let parts: Vec<_> = path.trim_matches('/').split('/').map(str::trim).collect();
    let name = parts.last().copied().unwrap_or("");
    if parts.iter().any(|part| {
        let offset = part.as_ptr() as usize - text.as_ptr() as usize;
        !view.slice(offset, offset + part.len()).ident()
    }) {
        for part in &parts {
            let offset = part.as_ptr() as usize - text.as_ptr() as usize;
            let part_view = view.slice(offset, offset + part.len());
            if part_view
                .tokens()
                .iter()
                .any(|token| token.kind == TokenKind::Number)
            {
                return Err(SignatureError {
                    message: "bad argument definition".into(),
                    source_span: Some(Span::new(start + offset, start + offset + part.len())),
                    after_header: false,
                });
            }
        }
        return Err("unsupported procedure argument declaration path".into());
    }
    let mut flags = 0;
    let mut type_parts = Vec::new();
    for part in &parts[..parts.len() - 1] {
        flags |= match *part {
            "static" => 1,
            "const" => 2,
            "tmp" => 4,
            "global" => 8,
            _ => {
                type_parts.push(*part);
                0
            }
        };
    }
    let element_type = if type_parts.is_empty() {
        None
    } else {
        Some(intern(symbols, &format!("/{}", type_parts.join("/")))?)
    };
    let declaration_start = declaration.as_ptr() as usize - text.as_ptr() as usize;
    let array = parse_array_view(
        view.slice(declaration_start, declaration_start + declaration.len()),
        element_type,
        symbols,
    )?;
    let authored_type = format!("/{}", type_parts.join("/"));
    let projection = dm_syntax::project_declaration_type(&authored_type);
    let list_element_type = projection
        .list_element_path
        .map(|path| intern(symbols, &format!("/{path}")))
        .transpose()?;
    let declared_type = if array.is_some() {
        Some(intern(symbols, "/list")?)
    } else if type_parts.is_empty() {
        None
    } else {
        Some(intern(
            symbols,
            dm_syntax::project_declaration_type(&format!("/{}", type_parts.join("/"))).runtime_path,
        )?)
    };
    fn end(positions: &[Option<usize>], start: usize, len: usize) -> usize {
        positions
            .iter()
            .flatten()
            .copied()
            .filter(|position| *position > start)
            .min()
            .unwrap_or(len)
    }
    let default = equal
        .map(|index| {
            let limit = end(&positions, index, text.len());
            if text[index + 1..limit].trim().is_empty() {
                return Err(SignatureError {
                    message: "missing expression".into(),
                    source_span: Some(Span::new(start + index, start + limit)),
                    after_header: false,
                });
            }
            expression_view(view.slice(index + 1, limit).trim(), symbols)
                .map_err(SignatureError::from)
        })
        .transpose()?;
    let input_annotation = annotation
        .map(|span| {
            expression_view(
                view.slice(span.end, end(&positions, span.start, text.len()))
                    .trim(),
                symbols,
            )
        })
        .transpose()?;
    let source_expression = source
        .map(|span| {
            expression_view(
                view.slice(span.end, end(&positions, span.start, text.len()))
                    .trim(),
                symbols,
            )
        })
        .transpose()?;
    Ok(Parameter {
        name: intern(symbols, name)?,
        declared_type,
        list_element_type,
        flags,
        array,
        default,
        input_annotation,
        source_expression,
        relative_span: Span::new(start, start + text.len()),
    })
}
pub(crate) struct HeaderTypeDeclaration {
    pub(crate) path: SymbolId,
    pub(crate) relative_span: Span,
}
pub(crate) struct ParsedSignature {
    pub(crate) signature: ProcedureSignature,
    pub(crate) declarations: Vec<HeaderTypeDeclaration>,
}
#[cfg(test)]
pub(crate) fn parse_signature(
    arguments: &str,
    trailing: &str,
    symbols: &mut SymbolTable,
) -> Result<ProcedureSignature, String> {
    let parsed = parse_signature_declarations(arguments, trailing, symbols)?;
    if !parsed.declarations.is_empty() {
        return Err("unsupported absolute declaration in signature-only adapter".into());
    }
    Ok(parsed.signature)
}
pub(crate) fn parse_signature_declarations(
    arguments: &str,
    trailing: &str,
    symbols: &mut SymbolTable,
) -> Result<ParsedSignature, SignatureError> {
    // Standalone compatibility entry. The native frontend calls the original
    // issued token-view route below and never enters this lexical adapter.
    let args = LexedHeader::new(arguments);
    let tail = LexedHeader::new(trailing);
    if !args.valid() || !tail.valid() {
        return Err("invalid procedure header tokens".into());
    }
    parse_signature_views(args.view(), tail.view(), symbols)
}
fn parse_signature_views(
    arguments_view: HeaderView<'_>,
    trailing_view: HeaderView<'_>,
    symbols: &mut SymbolTable,
) -> Result<ParsedSignature, SignatureError> {
    #[cfg(test)]
    SIGNATURE_INTERPRETATIONS.with(|n| n.set(n.get() + 1));
    let arguments = arguments_view.text();
    let trailing = trailing_view.text();
    let mut parameters = Vec::new();
    let mut declarations = Vec::new();
    let mut variadic = false;
    let mut start = 0;
    let mut stops: Vec<_> = arguments_view
        .top_level()
        .into_iter()
        .filter(|(token, _)| *token == ",")
        .map(|(_, span)| span.start)
        .collect();
    stops.push(arguments.len());
    for stop in stops {
        let untrimmed = &arguments[start..stop];
        let leading = untrimmed.len() - untrimmed.trim_start().len();
        let text = untrimmed.trim();
        // BYOND accepts an empty signature and a final comma, but an empty
        // slot before a comma is an invalid formal, not an omitted parameter.
        if text.is_empty() && stop < arguments.len() {
            return Err(SignatureError {
                message: "bad argument definition".into(),
                source_span: Some(Span::new(start, stop)),
                after_header: true,
            });
        }
        if text == "..." {
            variadic = true
        } else if !text.is_empty() {
            if variadic {
                return Err("procedure argument follows variadic marker".into());
            }
            if text.starts_with('/') {
                // An absolute path in a formal header declares that type; it
                // does not name a parameter (BYOND 516.1687 compile oracle).
                // More elaborate declaration effects remain explicit gaps.
                dm_ir::TypePath::parse(text).map_err(|_| {
                    "unsupported absolute declaration in procedure argument list".to_string()
                })?;
                let view = arguments_view.slice(start + leading, start + leading + text.len());
                if text.trim_matches('/').split('/').any(|part| {
                    let offset = part.as_ptr() as usize - text.as_ptr() as usize;
                    matches!(part, "var" | "proc" | "verb")
                        || !view.slice(offset, offset + part.len()).ident()
                }) {
                    return Err(
                        "unsupported absolute declaration in procedure argument list".into(),
                    );
                }
                declarations.push(HeaderTypeDeclaration {
                    path: intern(symbols, text)?,
                    relative_span: Span::new(start + leading, start + leading + text.len()),
                });
            } else {
                parameters.push(parameter(
                    arguments_view.slice(start + leading, start + leading + text.len()),
                    start + leading,
                    symbols,
                )?);
            }
        }
        start = stop + 1;
    }
    let trailing = trailing.trim();
    let return_annotation = if trailing.is_empty() {
        None
    } else {
        let annotation = trailing
            .strip_prefix("as ")
            .ok_or("unsupported procedure return annotation")?;
        let trimmed = trailing_view.trim();
        Some(expression_view(
            trimmed.slice(3, 3 + annotation.len()),
            symbols,
        )?)
    };
    Ok(ParsedSignature {
        signature: ProcedureSignature {
            parameters: parameters.into(),
            variadic,
            return_annotation,
        },
        declarations,
    })
}
pub(crate) struct ParsedSetting {
    pub(crate) setting: ProcedureSetting,
    /// RHS extent relative to this exact original setting header, not an Expr.
    pub(crate) value_span: Span,
}
pub(crate) fn parse_setting(
    text: &str,
    symbols: &mut SymbolTable,
) -> Result<ProcedureSetting, String> {
    let text = text
        .trim()
        .strip_prefix("set ")
        .ok_or("expected set declaration")?;
    let (name, operation, value) = if let Some(index) = dm_syntax::top_level_assignment_index(text)
    {
        (
            text[..index].trim(),
            SettingOperation::Assign,
            text[index + 1..].trim(),
        )
    } else {
        let span = top_level_tokens(text)
            .into_iter()
            .find(|(token, _)| token == "in")
            .map(|(_, span)| span)
            .ok_or("set declaration missing assignment or in")?;
        (
            text[..span.start].trim(),
            SettingOperation::In,
            text[span.end..].trim(),
        )
    };
    // Checker annotations are shared source metadata, not runtime ABI settings.
    // Only the native identifier spelling is admitted; ordinary unknown names
    // remain errors. Compile-command policy rejects these annotations separately.
    let checker_name = LexedHeader::new(name);
    let checker_tokens = checker_name.view();
    let checker_setting = name.starts_with("SpacemanDMM_")
        && checker_name.valid()
        && matches!(checker_tokens.tokens(), [token] if token.kind == TokenKind::Ident
            && checker_tokens.spelling(token) == name);
    construct_setting(name, checker_setting, operation, symbols, |symbols| {
        expression(value, symbols)
    })
}

/// Shared setting metadata partition over the SAME existing HeaderView grammar.
/// Native callers supply original cold tokens; compatibility above retains its lexical path.
struct SettingParts<'a> {
    name: HeaderView<'a>,
    operation: SettingOperation,
    value: HeaderView<'a>,
    value_span: Span,
}
fn setting_parts(view: HeaderView<'_>) -> Result<SettingParts<'_>, String> {
    let header = view;
    let view = view.trim();
    let text = view.text();
    let _rest = text
        .strip_prefix("set ")
        .ok_or("expected set declaration")?;
    let rest = view.slice(4, text.len());
    let (name, operation, value) = if let Some(index) = rest.assignment_index() {
        (
            rest.slice(0, index).trim(),
            SettingOperation::Assign,
            rest.slice(index + 1, rest.text().len()).trim(),
        )
    } else {
        let span = rest
            .first_top_level("in")
            .ok_or("set declaration missing assignment or in")?;
        (
            rest.slice(0, span.start).trim(),
            SettingOperation::In,
            rest.slice(span.end, rest.text().len()).trim(),
        )
    };

    let value_span = Span::new(
        value.span().start - header.span().start,
        value.span().end - header.span().start,
    );
    Ok(SettingParts {
        name,
        operation,
        value,
        value_span,
    })
}
#[cfg(test)]
thread_local! {static ORIGINAL_SETTING_PARSES:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
#[cfg(test)]
pub(crate) fn original_setting_metadata_parses() -> usize {
    ORIGINAL_SETTING_PARSES.with(|n| n.get())
}
fn parse_setting_view(view:HeaderView<'_>,symbols:&mut SymbolTable)->Result<ParsedSetting,String>{parse_setting_view_profile(view,symbols,false)}
fn parse_setting_view_profile(
    view: HeaderView<'_>,
    symbols: &mut SymbolTable,
    checker_diagnostics: bool,
) -> Result<ParsedSetting, String> {
    #[cfg(test)]
    ORIGINAL_SETTING_PARSES.with(|n| n.set(n.get() + 1));
    let parts = setting_parts(view)?;
    let spelling = parts.name.text();
    let checker_setting = (spelling.starts_with("SpacemanDMM_") || checker_diagnostics) && parts.name.ident();
    Ok(ParsedSetting {
        setting: construct_setting(
            spelling,
            checker_setting,
            parts.operation,
            symbols,
            |symbols| expression_view(parts.value, symbols),
        )?,
        value_span: parts.value_span,
    })
}

/// ONE existing setting-name/metadata policy; compatibility keeps its original
/// lexical/error-order path and native views reuse the original primary tokens.
fn construct_setting(
    name: &str,
    checker_setting: bool,
    operation: SettingOperation,
    symbols: &mut SymbolTable,
    value: impl FnOnce(&mut SymbolTable) -> Result<SymbolicExpression, String>,
) -> Result<ProcedureSetting, String> {
    if !checker_setting && !ordinary_compiler_setting_name(name)
    {
        return Err(format!("unknown procedure setting: {name}"));
    }
    Ok(ProcedureSetting {
        name: intern(symbols, name)?,
        operation,
        value: value(symbols)?,
    })
}

pub(crate) fn parse_array(
    declaration: &str,
    element_type: Option<SymbolId>,
    symbols: &mut SymbolTable,
) -> Result<Option<std::sync::Arc<dm_ir::ArrayDeclaration>>, String> {
    let tokens = LexedHeader::new(declaration);
    if !tokens.valid() {
        return Err("invalid array declaration tokens".into());
    }
    parse_array_view(tokens.view(), element_type, symbols)
}
/// Borrowed cursor for the SAME existing suffix grammar. It owns no tokens,
/// source, syntax or semantic roster; metadata and native roots consume it once.
#[cfg(test)]thread_local!{static ARRAY_DIMENSION_STEPS:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
#[cfg(test)]pub(crate) fn reset_array_dimension_steps(){ARRAY_DIMENSION_STEPS.with(|n|n.set(0));}
#[cfg(test)]pub(crate) fn array_dimension_steps()->usize{ARRAY_DIMENSION_STEPS.with(std::cell::Cell::get)}
pub(crate) struct ArrayDimensions<'a>{view:HeaderView<'a>,at:usize,depth:usize,start:Option<usize>,count:usize,done:bool}
pub(crate) fn array_dimensions(view:HeaderView<'_>)->ArrayDimensions<'_>{ArrayDimensions{view,at:0,depth:0,start:None,count:0,done:false}}
impl<'a> Iterator for ArrayDimensions<'a>{
 type Item=Result<HeaderView<'a>,String>;
 fn next(&mut self)->Option<Self::Item>{
  if self.done{return None}
  while let Some(token)=self.view.tokens().get(self.at){
   #[cfg(test)]ARRAY_DIMENSION_STEPS.with(|n|n.set(n.get()+1));
   self.at+=1;
   if self.depth==0&&self.count!=0&&self.view.spelling(token)!="["&&!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment){self.done=true;return Some(Err("unsupported text after array declaration".into()))}
   match self.view.spelling(token){
    "["=>{if self.depth==0{self.start=Some(self.view.relative_span(token).end)}self.depth+=1},
    "]"=>{if self.depth==0{self.done=true;return Some(Err("unmatched array declaration bracket".into()))}self.depth-=1;if self.depth==0{let start=self.start.take().expect("outer bracket issued start");let dimension=self.view.slice(start,self.view.relative_span(token).start).trim();self.count+=1;return Some(Ok(dimension))}},
    _=>{},
   }
  }
  self.done=true;if self.depth!=0{Some(Err("unterminated array declaration".into()))}else{None}
 }
}
pub(crate) fn visit_array_dimensions<'a>(view:HeaderView<'a>,mut emit:impl FnMut(usize,HeaderView<'a>)->Result<(),String>)->Result<usize,String>{
 let mut count=0;for dimension in array_dimensions(view){emit(count,dimension?)?;count+=1;}Ok(count)
}
fn parse_array_view(view:HeaderView<'_>,element_type:Option<SymbolId>,symbols:&mut SymbolTable)->Result<Option<std::sync::Arc<dm_ir::ArrayDeclaration>>,String>{
 let mut dimensions=Vec::new();
 visit_array_dimensions(view,|_,dimension|{dimensions.push(if dimension.text().is_empty(){None}else{Some(expression_view(dimension,symbols)?)});Ok(())})?;
 if dimensions.is_empty(){Ok(None)}else{Ok(Some(std::sync::Arc::new(dm_ir::ArrayDeclaration{dimensions:dimensions.into(),element_type})))}
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn typed_list_formals_retain_distinct_hints_in_signature_identity() {
        let mut symbols = SymbolTable::default();
        let first =
            parse_signature("list/datum/item/values, list/plain", "", &mut symbols).unwrap();
        let equivalent = parse_signature(
            " list / datum / item / values , list / plain ",
            "",
            &mut symbols,
        )
        .unwrap();
        assert_eq!(first.canonical_bytes(), equivalent.canonical_bytes());
        assert_eq!(
            first.parameters[0].declared_type,
            Some(SymbolId::of("/list"))
        );
        assert_eq!(
            first.parameters[0].list_element_type,
            Some(SymbolId::of("/datum/item"))
        );
        assert!(first.parameters[0].array.is_none());
        assert_eq!(first.parameters[1].list_element_type, None);
        let other =
            parse_signature("list/datum/other/values, list/plain", "", &mut symbols).unwrap();
        assert_ne!(first.canonical_bytes(), other.canonical_bytes());
    }
    #[test]
    fn argument_modifiers_arrays_defaults_and_sources_are_retained() {
        let mut symbols = SymbolTable::default();
        let signature = parse_signature(
            "var/tmp/const/datum/item/items[2][] = list() as anything in world, static/value = 3",
            "",
            &mut symbols,
        )
        .unwrap();
        let parameter = &signature.parameters[0];
        assert_eq!(parameter.flags, 2 | 4);
        assert_eq!(parameter.declared_type, Some(SymbolId::of("/list")));
        let array = parameter.array.as_ref().unwrap();
        assert_eq!(array.element_type, Some(SymbolId::of("/datum/item")));
        assert_eq!(array.dimensions.len(), 2);
        assert!(array.dimensions[0].is_some());
        assert!(array.dimensions[1].is_none());
        assert!(parameter.default.is_some());
        assert!(parameter.input_annotation.is_some());
        assert!(parameter.source_expression.is_some());
        assert_eq!(signature.parameters[1].flags, 1);
        assert_eq!(signature.parameters[1].declared_type, None);
        let plain = parse_signature("value", "", &mut symbols).unwrap();
        let temporary = parse_signature("tmp/value", "", &mut symbols).unwrap();
        let unsized_array = parse_signature("value[]", "", &mut symbols).unwrap();
        let sized = parse_signature("value[2]", "", &mut symbols).unwrap();
        assert_ne!(plain.canonical_bytes(), temporary.canonical_bytes());
        assert_ne!(unsized_array.canonical_bytes(), sized.canonical_bytes());
    }
    #[test]
    fn argument_array_paths_do_not_consume_dimension_paths_or_trailing_junk() {
        let mut symbols = SymbolTable::default();
        let signature =
            parse_signature("datum/item/items[length(/datum/item)]", "", &mut symbols).unwrap();
        assert_eq!(signature.parameters[0].name, SymbolId::of("items"));
        assert_eq!(
            signature.parameters[0].array.as_ref().unwrap().element_type,
            Some(SymbolId::of("/datum/item"))
        );
        for argument in [
            "value[2] garbage",
            "datum//value",
            "value[",
            "value]",
            "value[-\"",
        ] {
            assert!(
                parse_signature(argument, "", &mut symbols).is_err(),
                "{argument}"
            );
        }
    }
    #[test]
    fn absolute_header_declaration_is_not_a_relative_typed_parameter() {
        let mut symbols = SymbolTable::default();
        let relative = parse_signature("datum/marker_target/target", "", &mut symbols).unwrap();
        assert_eq!(relative.parameters.len(), 1);
        assert_eq!(relative.parameters[0].name, SymbolId::of("target"));
        assert_eq!(
            relative.parameters[0].declared_type,
            Some(SymbolId::of("/datum/marker_target"))
        );
        let absolute =
            parse_signature_declarations("/datum/marker_target/target", "", &mut symbols).unwrap();
        assert!(absolute.signature.parameters.is_empty());
        assert_eq!(absolute.declarations.len(), 1);
        assert_eq!(
            absolute.declarations[0].path,
            SymbolId::of("/datum/marker_target/target")
        );
        assert_eq!(absolute.declarations[0].relative_span, Span::new(0, 27));
        for declaration in [
            "/var/value",
            "/datum/marker_target/proc/call",
            "/datum/marker_target/target = 1",
        ] {
            assert!(parse_signature_declarations(declaration, "", &mut symbols).is_err());
        }
    }

    #[test]
    fn absolute_header_effects_do_not_consume_surrounding_parameters() {
        for arguments in [
            "/datum/marker_target/target, other",
            "other, /datum/marker_target/target",
            "other,/datum/marker_target/target",
            "other ,  /datum/marker_target/target",
            "datum/marker_target/other, /datum/marker_target/target, actual_power=1",
        ] {
            let mut symbols = SymbolTable::default();
            let parsed = parse_signature_declarations(arguments, "", &mut symbols).unwrap();
            let expected: &[&str] = if arguments.ends_with("actual_power=1") {
                &["other", "actual_power"]
            } else {
                &["other"]
            };
            let names: Vec<_> = parsed
                .signature
                .parameters
                .iter()
                .map(|parameter| parameter.name)
                .collect();
            assert_eq!(
                names,
                expected
                    .iter()
                    .map(|name| SymbolId::of(name))
                    .collect::<Vec<_>>()
            );
            assert_eq!(parsed.declarations.len(), 1);
            let effect = &parsed.declarations[0];
            assert_eq!(effect.path, SymbolId::of("/datum/marker_target/target"));
            assert_eq!(
                &arguments[effect.relative_span.start..effect.relative_span.end],
                "/datum/marker_target/target"
            );
        }
    }

    #[test]
    fn trailing_argument_path_separator_preserves_name_and_type() {
        let mut symbols = SymbolTable::default();
        let signature = parse_signature("obj/instance/", "", &mut symbols).unwrap();
        assert_eq!(signature.parameters[0].name, SymbolId::of("instance"));
        assert_eq!(
            signature.parameters[0].declared_type,
            Some(SymbolId::of("/obj"))
        );
        assert!(signature.parameters[0].array.is_none());
    }
    #[test]
    fn typed_default_input_and_source_are_separate() {
        let mut symbols = SymbolTable::default();
        let signature = parse_signature(
            "value as text, count = 3 as num, target as obj in view(1)",
            "",
            &mut symbols,
        )
        .unwrap();
        assert_eq!(signature.parameters.len(), 3);
        let count = &signature.parameters[1];
        assert_eq!(symbols.text(count.name), Some("count"));
        assert_eq!(
            symbols.text(count.default.as_ref().unwrap().tokens[0].text),
            Some("3")
        );
        assert_eq!(
            symbols.text(count.input_annotation.as_ref().unwrap().tokens[0].text),
            Some("num")
        );
        assert!(count.source_expression.is_none());
        assert!(signature.parameters[2].source_expression.is_some());
    }
    #[test]
    fn nested_defaults_and_variadic_are_not_split_as_arguments() {
        let mut symbols = SymbolTable::default();
        let signature = parse_signature(
            "list/items = list(1, list(2,3)), ...",
            " as /datum/result",
            &mut symbols,
        )
        .unwrap();
        assert_eq!(signature.parameters.len(), 1);
        assert_eq!(
            signature.parameters[0].declared_type,
            Some(SymbolId::of("/list"))
        );
        assert!(signature.variadic);
        assert!(signature.return_annotation.is_some());
    }
    #[test]
    fn source_setting_is_typed_without_guessing_wire_flags() {
        let mut symbols = SymbolTable::default();
        let setting = parse_setting("set src in world", &mut symbols).unwrap();
        assert_eq!(setting.operation, SettingOperation::In);
        assert_eq!(symbols.text(setting.name), Some("src"));
        assert_eq!(symbols.text(setting.value.tokens[0].text), Some("world"));
        assert!(parse_setting("set imaginary = 1", &mut symbols).is_err());
    }
    #[test]
    fn checker_prefix_settings_preserve_native_symbolic_metadata() {
        let mut symbols = SymbolTable::default();
        let setting =
            parse_setting("set SpacemanDMM_should_be_pure = candidate", &mut symbols).unwrap();
        assert_eq!(
            symbols.text(setting.name),
            Some("SpacemanDMM_should_be_pure")
        );
        assert_eq!(setting.operation, SettingOperation::Assign);
        assert_eq!(
            symbols.text(setting.value.tokens[0].text),
            Some("candidate")
        );
        for malformed in [
            "set SpacemanDMM_x.y = 1",
            "set SpacemanDMM_x y = 1",
            "set SpacemanDMM_x =",
        ] {
            assert!(
                parse_setting(malformed, &mut symbols).is_err(),
                "{malformed}"
            );
        }
    }
    #[test]
    fn operator_adjacency_is_semantic_not_ordinary_position() {
        let mut symbols = SymbolTable::default();
        let joined = expression("seed++", &mut symbols).unwrap();
        let separated = expression("seed + +", &mut symbols).unwrap();
        assert_ne!(joined.fingerprint(), separated.fingerprint());
        assert_eq!(joined.source_text(&symbols).as_deref(), Some("seed++"));
        assert_eq!(separated.source_text(&symbols).as_deref(), Some("seed + +"));
    }
    #[test]
    fn expression_fingerprint_excludes_relative_whitespace_positions() {
        let mut symbols = SymbolTable::default();
        let compact = expression("seed+1", &mut symbols).unwrap();
        let spaced = expression("seed + 1", &mut symbols).unwrap();
        assert_eq!(compact.fingerprint(), spaced.fingerprint());
        assert_ne!(
            compact.tokens[1].relative_span,
            spaced.tokens[1].relative_span
        );
    }
    #[test]
    fn borrowed_header_views_match_owned_expression_tokens_and_local_spans() {
        fn owned_expression(text: &str, symbols: &mut SymbolTable) -> SymbolicExpression {
            let lexed = dm_syntax::lex(text);
            assert!(lexed.diagnostics.is_empty());
            SymbolicExpression {
                tokens: lexed
                    .tokens
                    .into_iter()
                    .filter(|token| {
                        !matches!(
                            token.kind,
                            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                        )
                    })
                    .map(|token| ExpressionToken {
                        kind: token.kind,
                        text: symbols.intern(&token.text).unwrap(),
                        relative_span: token.span,
                    })
                    .collect::<Vec<_>>()
                    .into(),
            }
        }
        let arguments = "  tmp/datum/item/values[ 2 + length(list(1, 2)) ][ ] = list(\"as\", \"in\", call(1, 2)) as anything | null in world.contents , resource = 'icons/Ã©.dmi' , ...";
        let mut symbols = SymbolTable::default();
        let signature = parse_signature(arguments, "as num | null", &mut symbols).unwrap();
        assert_eq!(signature.parameters.len(), 2);
        assert!(signature.variadic);
        let first = &signature.parameters[0];
        assert_eq!(first.name, SymbolId::of("values"));
        assert_eq!(first.flags, 4);
        assert_eq!(first.declared_type, Some(SymbolId::of("/list")));
        let array = first.array.as_ref().unwrap();
        assert_eq!(array.element_type, Some(SymbolId::of("/datum/item")));
        assert_eq!(
            array.dimensions.as_ref(),
            &[
                Some(owned_expression("2 + length(list(1, 2))", &mut symbols)),
                None
            ]
        );
        assert_eq!(
            first.default,
            Some(owned_expression(
                "list(\"as\", \"in\", call(1, 2))",
                &mut symbols
            ))
        );
        assert_eq!(
            first.input_annotation,
            Some(owned_expression("anything | null", &mut symbols))
        );
        assert_eq!(
            first.source_expression,
            Some(owned_expression("world.contents", &mut symbols))
        );
        let first_end = arguments.find(" , resource").unwrap();
        assert_eq!(first.relative_span, Span::new(2, first_end));
        assert_eq!(
            signature.parameters[1].default,
            Some(owned_expression("'icons/Ã©.dmi'", &mut symbols))
        );
        assert_eq!(
            signature.return_annotation,
            Some(owned_expression("num | null", &mut symbols))
        );
    }
}

#[cfg(test)]
thread_local! { static SIGNATURE_INTERPRETATIONS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) }; }
#[cfg(test)]
fn signature_interpretations() -> usize {
    SIGNATURE_INTERPRETATIONS.with(std::cell::Cell::get)
}

#[cfg(test)]
mod original_setting_partition_tests {
    use super::*;
    #[test]
    fn original_setting_partition_keeps_metadata_and_real_rhs_without_relex() {
        for source in [
            "set name = \"literal = in\"",
            "set src in view(1)",
            "set invisibility = invisibility",
            "set desc = list(1,2)",
            "set SpacemanDMM_should_be_pure = arbitrary",
        ] {
            let mut old_symbols = SymbolTable::default();
            let old = parse_setting(source, &mut old_symbols).unwrap();
            let tokens = dm_syntax::lex_spans(source);
            assert!(tokens.diagnostics.is_empty());
            let view =
                HeaderView::original(source, &tokens.tokens, Span::new(0, source.len())).unwrap();
            let mut native_symbols = SymbolTable::default();
            let before = header::lexical_header_calls();
            let parsed = parse_setting_view(view, &mut native_symbols).unwrap();
            assert_eq!(
                header::lexical_header_calls(),
                before,
                "original token partition must not lex setting/name/value text again"
            );
            assert_eq!(old, parsed.setting);
            if source == "set invisibility = invisibility" {
                assert_eq!(
                    parsed.value_span.start,
                    source.rfind("invisibility").unwrap()
                );
            }
        }
    }
    #[test]
    fn compatibility_setting_errors_keep_name_validation_before_value_lexing() {
        let mut symbols = SymbolTable::default();
        assert_eq!(
            parse_setting("set unknown = \"unterminated", &mut symbols).unwrap_err(),
            "unknown procedure setting: unknown"
        );
        assert_eq!(
            parse_setting("set name = \"unterminated", &mut symbols).unwrap_err(),
            "invalid expression tokens in procedure declaration"
        );
    }
}

fn ordinary_compiler_setting_name(name:&str)->bool{matches!(name,"name"|"desc"|"category"|"src"|"invisibility"|"waitfor"|"hidden"|"background"|"instant"|"popup_menu")}
pub(crate) fn compiler_setting_name(name:&str)->bool{name.starts_with("SpacemanDMM_")||ordinary_compiler_setting_name(name)}
pub(crate) fn settings_compilable(nodes:&[dm_ir::ProcedureSettingNode],symbols:&SymbolTable)->bool{
 fn walk(nodes:&[dm_ir::ProcedureSettingNode],symbols:&SymbolTable,depth:usize)->bool{if depth>256{return false}nodes.iter().all(|node|match node{dm_ir::ProcedureSettingNode::Setting(setting)=>symbols.text(setting.name).is_some_and(compiler_setting_name),dm_ir::ProcedureSettingNode::Conditional{then_branch,else_branch,..}=>walk(then_branch,symbols,depth+1)&&walk(else_branch,symbols,depth+1),dm_ir::ProcedureSettingNode::UnsupportedContext{children,..}=>walk(children,symbols,depth+1)})}walk(nodes,symbols,0)
}
