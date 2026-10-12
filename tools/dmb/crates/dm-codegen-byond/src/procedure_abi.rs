//! Pure BYOND procedure ABI policy. Inputs are typed source metadata and explicit
//! inherited ABI facts; physical string, variable and helper-proc IDs belong to
//! the linker. No project snapshot or filesystem is consulted here.
use crate::lower_resolver::ProcedureInputs;
use dm_ir::{
    ProcedureMetadata, ProcedureSetting, ProcedureSettingNode, SemanticValue, SettingOperation,
    SymbolTable, SymbolicExpression,
};
use dm_syntax::Item;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Category {
    Default,
    Null,
    Text(Vec<u8>),
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProcLayout {
    pub display_name: Option<Vec<u8>>,
    pub description: Option<Vec<u8>>,
    pub category: Category,
    pub source_kind: u8,
    pub source_parameter: u8,
    pub flags: u32,
    /// None is not authored; Some(0) is an explicit zero setting.
    pub invisibility: Option<u8>,
}
impl Default for ProcLayout {
    fn default() -> Self {
        Self {
            display_name: None,
            description: None,
            category: Category::Default,
            source_kind: 0,
            source_parameter: 255,
            flags: 4,
            invisibility: None,
        }
    }
}
impl ProcLayout {
    /// Same extended flag framing as the existing DMB writer. Authored zero
    /// invisibility uses sentinel 255, rather than becoming an absent setting.
    pub fn encoded_flags(&self) -> (u8, Option<(u32, u8)>) {
        let extended = self.flags & !0x7f != 0 || self.invisibility.is_some();
        (
            (self.flags as u8 & 0x7f) | if extended { 0x80 } else { 0 },
            extended.then_some((
                self.flags | 0x80,
                self.invisibility.filter(|v| *v != 0).unwrap_or(255),
            )),
        )
    }
}
pub enum InheritedAbi<'a> {
    Fresh,
    Known(&'a ProcLayout),
    Unsupported,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ArgumentSourceHelper {
    pub argument: usize,
    pub expression: SymbolicExpression,
    /// Helpers execute with the owning procedure's original argument frame.
    /// Their physical reference index is assigned later, never guessed here.
    pub frame_parameters: Vec<String>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ArgumentSource {
    Builtin { kind: u8, parameter: u8 },
    Helper { argument: usize },
}
pub struct PreparedProcedure {
    pub inputs: ProcedureInputs,
    pub layout: ProcLayout,
    pub source_helpers: Vec<ArgumentSourceHelper>,
    /// Authoritative argument source plan; Helper needs a linker-issued reference.
    pub argument_sources: Vec<ArgumentSource>,
    pub executable_body: Vec<Item>,
}
#[path = "procedure_abi_error.rs"]
mod error;
pub use error::{AbiError, AbiErrorKind};
fn fail(message: impl Into<String>) -> AbiError {
    AbiError::unsupported(message)
}
fn expression_text(value: &SymbolicExpression, symbols: &SymbolTable) -> Result<String, AbiError> {
    value
        .source_text(symbols)
        .ok_or_else(|| AbiError::invariant("unavailable or malformed symbolic expression spelling"))
}
fn compact(text: &str) -> Result<String, AbiError> {
    let lexed = dm_syntax::lex(text);
    if !lexed.diagnostics.is_empty() {
        return Err(AbiError::source("invalid ABI expression syntax"));
    }
    Ok(lexed
        .tokens
        .into_iter()
        .filter(|t| {
            !matches!(
                t.kind,
                dm_syntax::TokenKind::Whitespace
                    | dm_syntax::TokenKind::Newline
                    | dm_syntax::TokenKind::Comment
            )
        })
        .map(|t| t.text)
        .collect())
}
fn restriction(name: &str) -> Option<u32> {
    Some(match name {
        "anything" => 0x1000,
        "mob" => 1,
        "obj" => 2,
        "text" => 4,
        "num" => 8,
        "file" => 0x10,
        "turf" => 0x20,
        "null" => 0x80,
        "area" => 0x100,
        "icon" => 0x200,
        "sound" => 0x400,
        "message" => 0x800,
        _ => return None,
    })
}
/// Pinned native return annotations carry source type information without a
/// procedure-header field or return-value coercion. Keep their source metadata
/// intact and admit only the observed atomic/path union grammar.
fn validate_return_annotation(
    annotation: &SymbolicExpression,
    symbols: &SymbolTable,
    evaluate: &mut impl FnMut(&SymbolicExpression) -> Result<SemanticValue, AbiError>,
) -> Result<(), AbiError> {
    for tokens in annotation
        .tokens
        .split(|token| symbols.text(token.text) == Some("|"))
    {
        let fragment = SymbolicExpression {
            tokens: tokens.to_vec().into(),
        };
        let part = compact(&expression_text(&fragment, symbols)?)?;
        let part = part.as_str();
        let path = part.strip_prefix('/').is_some_and(|tail| {
            !tail.is_empty()
                && tail.split('/').all(|segment| {
                    let mut bytes = segment.bytes();
                    bytes
                        .next()
                        .is_some_and(|b| b.is_ascii_alphabetic() || b == b'_')
                        && bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_')
                })
        });
        if !path && restriction(part).is_none() && !matches!(part, "atom" | "list") {
            return Err(fail(format!(
                "unsupported procedure return annotation: {part}"
            )));
        }
        if path && evaluate(&fragment)? != SemanticValue::Type(dm_ir::SymbolId::of(part)) {
            return Err(fail(format!(
                "procedure return type is not positively captured: {part}"
            )));
        }
    }
    Ok(())
}
fn type_flags(path: Option<&str>) -> Result<u32, AbiError> {
    let path = path.unwrap_or("").trim_start_matches('/');
    Ok(match path.split('/').next().unwrap_or("") {
        "" | "datum" | "client" | "list" | "image" | "matrix" | "regex" | "savefile"
        | "mutable_appearance" | "appearance" | "generator" | "alist" | "database"
        | "exception" | "icon" | "sound" | "callee" => 0,
        "atom" if path == "atom/movable" || path.starts_with("atom/movable/") => 3,
        "atom" => 0x123,
        "mob" => 1,
        "obj" => 2,
        "turf" => 0x20,
        "area" => 0x100,
        _ => return Err(fail(format!("unsupported parameter type: /{path}"))),
    })
}
fn radius(text: &str, name: &str, default: Option<u8>) -> Option<Result<u8, AbiError>> {
    let inner = text
        .strip_prefix(name)?
        .strip_prefix('(')?
        .strip_suffix(')')?;
    Some(if inner.is_empty() {
        default.ok_or_else(|| fail("source radius is required"))
    } else {
        inner
            .parse::<u8>()
            .map_err(|_| fail("unsupported source radius"))
    })
}
fn source_mode(text: &str, argument: bool) -> Result<Option<(u8, u8)>, AbiError> {
    // BYOND 516.1687 encodes the observed explicit usr-centered verb source
    // view(usr, 1) as the same kind/radius pair as view(1). Argument sources
    // retain their expression-helper path; other centers remain unsupported.
    if !argument {
        if let Some(radius) = text
            .strip_prefix("view(usr,")
            .and_then(|s| s.strip_suffix(')'))
        {
            return radius
                .parse::<u8>()
                .map(|radius| Some((1, radius)))
                .map_err(|_| fail("unsupported source radius"));
        }
    }
    match text {
        "usr" if !argument => return Ok(Some((8, 127))),
        "usr.contents" => return Ok(Some((8, 127))),
        "usr.loc" if !argument => return Ok(Some((3, 255))),
        "world" => return Ok(Some((16, 127))),
        _ => {}
    }
    for (name, kind, default) in [
        ("view", 1, Some(125)),
        ("oview", 2, Some(125)),
        ("range", 5, None),
    ] {
        if let Some(value) = radius(text, name, default) {
            return match value {
                Ok(radius) => Ok(Some((kind, radius))),
                // Dynamic argument sources have a real expression helper.
                // Invalid numeric radii and non-argument settings stay strict.
                Err(_) if argument => {
                    let inner = &text[name.len() + 1..text.len() - 1];
                    if !inner.is_empty() && inner.parse::<f64>().is_err() {
                        Ok(None)
                    } else {
                        Err(fail("unsupported source radius"))
                    }
                }
                Err(error) => Err(error),
            };
        }
    }
    Ok(None)
}
fn number(value: SemanticValue) -> Result<u8, AbiError> {
    match value {
        SemanticValue::NumberBits(bits) => {
            let n = f32::from_bits(bits);
            if n.is_finite() && (0.0..=255.0).contains(&n) && n.fract() == 0.0 {
                Ok(n as u8)
            } else {
                Err(fail("unsupported numeric procedure setting"))
            }
        }
        _ => Err(fail("expected numeric procedure setting")),
    }
}
/// `evaluate` must provide exact captured constant meanings, including encoded
/// text bytes. Unsupported expressions must return an error, not a guessed value.
/// Nested settings are rejected while the tree's metadata only records immediate
/// settings. The actual body is checked, so a caller cannot silently omit them.
pub fn prepare_procedure(
    metadata: &ProcedureMetadata,
    symbols: &SymbolTable,
    body: &[Item],
    inputs: ProcedureInputs,
    inherited: InheritedAbi<'_>,
    evaluate: impl FnMut(&SymbolicExpression) -> Result<SemanticValue, AbiError>,
) -> Result<PreparedProcedure, AbiError> {
    fn nested(items: &[Item]) -> bool {
        items
            .iter()
            .any(|i| i.header.trim_start().starts_with("set ") || nested(&i.children))
    }
    if body.iter().any(|item| nested(&item.children)) {
        return Err(fail(
            "nested procedure settings require complete reachable-setting metadata",
        ));
    }
    let settings: Vec<_> = body
        .iter()
        .filter(|i| i.header.trim_start().starts_with("set "))
        .collect();
    if settings.len() != metadata.settings.len() {
        return Err(fail(
            "procedure setting metadata does not cover the unit body",
        ));
    }
    for (item, node) in settings.into_iter().zip(metadata.settings.iter()) {
        let ProcedureSettingNode::Setting(setting) = node else {
            return Err(fail(
                "guarded settings require verified setting-tree preparation",
            ));
        };
        let name = symbols
            .text(setting.name)
            .ok_or_else(|| AbiError::invariant("setting name spelling unavailable"))?;
        let operation = match setting.operation {
            SettingOperation::Assign => "=",
            SettingOperation::In => " in ",
        };
        if compact(&item.header)?
            != compact(&format!(
                "set {name}{operation}{}",
                expression_text(&setting.value, symbols)?
            ))?
        {
            return Err(AbiError::invariant(
                "procedure setting metadata differs from unit body",
            ));
        }
    }
    let executable_body: Vec<_> = body
        .iter()
        .filter(|item| !item.header.trim_start().starts_with("set "))
        .cloned()
        .collect();
    prepare_verified_procedure(
        metadata,
        symbols,
        &executable_body,
        inputs,
        inherited,
        evaluate,
    )
}
/// The host must verify this metadata with the same setting parser against the
/// actual unit body. This backend consumes typed facts, never semantic-tree APIs.
/// `body` has already had all setting leaves removed, preserving source spans.
pub fn prepare_verified_procedure(
    metadata: &ProcedureMetadata,
    symbols: &SymbolTable,
    body: &[Item],
    mut inputs: ProcedureInputs,
    inherited: InheritedAbi<'_>,
    mut evaluate: impl FnMut(&SymbolicExpression) -> Result<SemanticValue, AbiError>,
) -> Result<PreparedProcedure, AbiError> {
    fn setting_left(items: &[Item]) -> bool {
        items.iter().any(|item| {
            item.header.trim_start().starts_with("set ") || setting_left(&item.children)
        })
    }
    if setting_left(body) {
        return Err(AbiError::invariant(
            "executable body still contains procedure settings",
        ));
    }
    fn select<'a>(
        nodes: &'a [ProcedureSettingNode],
        output: &mut Vec<&'a ProcedureSetting>,
        evaluate: &mut impl FnMut(&SymbolicExpression) -> Result<SemanticValue, AbiError>,
    ) -> Result<(), AbiError> {
        for node in nodes {
            match node {
                ProcedureSettingNode::Setting(setting) => output.push(setting),
                ProcedureSettingNode::Conditional {
                    condition,
                    then_branch,
                    else_branch,
                } => {
                    let truth = match evaluate(condition)? {
                        SemanticValue::Null => false,
                        SemanticValue::NumberBits(bits) if f32::from_bits(bits).is_finite() => {
                            f32::from_bits(bits) != 0.0
                        }
                        _ => {
                            return Err(fail(
                                "setting guard requires a captured finite scalar constant",
                            ))
                        }
                    };
                    select(
                        if truth { then_branch } else { else_branch },
                        output,
                        evaluate,
                    )?;
                }
                ProcedureSettingNode::UnsupportedContext { .. } => {
                    return Err(fail("unsupported reachable procedure-setting context"))
                }
            }
        }
        Ok(())
    }
    let mut selected = Vec::new();
    select(&metadata.settings, &mut selected, &mut evaluate)?;
    if let Some(annotation) = &metadata.signature.return_annotation {
        validate_return_annotation(annotation, symbols, &mut evaluate)?;
    }
    let mut layout = match inherited {
        InheritedAbi::Fresh => ProcLayout::default(),
        InheritedAbi::Known(layout) => layout.clone(),
        InheritedAbi::Unsupported => {
            return Err(fail("inherited procedure ABI facts are unavailable"))
        }
    };
    inputs.parameters.clear();
    inputs.parameter_types.clear();
    inputs.readonly_parameters.clear();
    inputs.parameter_defaults.clear();
    inputs.parameter_type_flags.clear();
    inputs.parameter_value_sources.clear();
    let mut helpers = Vec::new();
    let mut argument_sources = Vec::new();
    for (index, param) in metadata.signature.parameters.iter().enumerate() {
        let restriction_type = match crate::parameter_abi::formal_shape(param)? {
            crate::parameter_abi::FormalShape::Scalar { declared_type } => {
                // A list/atom formal is lexically a list, while BYOND's
                // argument table restricts its input to the authored element
                // family. Keep that metadata separate from lexical lookup.
                if declared_type == Some(dm_ir::SymbolId::of("/list")) {
                    param.list_element_type.or(declared_type)
                } else {
                    declared_type
                }
            }
            // Native unsized formals are lexical lists, but their argument
            // restriction bits retain the authored element family.
            crate::parameter_abi::FormalShape::UnsizedList { element_type } => element_type,
        };
        let name = symbols
            .text(param.name)
            .ok_or_else(|| AbiError::invariant("parameter name spelling unavailable"))?;
        // BYOND preserves duplicate formal slots; lexical name lookup selects the last.
        inputs.parameters.push(name.to_owned());
        if param.flags & 2 != 0 {
            inputs.readonly_parameters.insert(index as u32);
        }
        let declared = param
            .declared_type
            .map(|id| {
                symbols
                    .text(id)
                    .ok_or_else(|| AbiError::invariant("parameter type spelling unavailable"))
            })
            .transpose()?;
        let restriction_path = restriction_type
            .map(|id| {
                symbols.text(id).ok_or_else(|| {
                    AbiError::invariant("parameter restriction spelling unavailable")
                })
            })
            .transpose()?;
        let mut flags = type_flags(restriction_path)?;
        if let Some(annotation) = &param.input_annotation {
            flags = 0;
            for part in compact(&expression_text(annotation, symbols)?)?.split('|') {
                flags |= restriction(part).ok_or_else(|| {
                    fail(format!("unsupported parameter input annotation: {part}"))
                })?;
            }
        }
        if let Some(path) = declared {
            inputs
                .parameter_types
                .insert(name.to_owned(), path.to_owned());
        }
        inputs.parameter_defaults.push(
            param
                .default
                .as_ref()
                .map(|v| expression_text(v, symbols))
                .transpose()?,
        );
        let source = param
            .source_expression
            .as_ref()
            .map(|v| expression_text(v, symbols))
            .transpose()?;
        let source = source.map(|s| compact(&s)).transpose()?;
        let encoded = match source.as_deref() {
            None => ArgumentSource::Builtin {
                kind: 1,
                parameter: 125,
            },
            Some(text) => match source_mode(text, true)? {
                Some((kind, parameter)) => {
                    if text == "world" && flags == 0 {
                        flags = 0x123;
                    }
                    ArgumentSource::Builtin { kind, parameter }
                }
                None => {
                    helpers.push(ArgumentSourceHelper {
                        argument: index,
                        expression: param.source_expression.clone().expect("present source"),
                        frame_parameters: Vec::new(),
                    });
                    ArgumentSource::Helper { argument: index }
                }
            },
        };
        inputs.parameter_type_flags.push(flags);
        argument_sources.push(encoded);
    }
    // A helper reference has no physical index yet. Do not expose a zero index
    // as valid wire metadata; the driver must encode argument_sources at link.
    if helpers.is_empty() {
        inputs.parameter_value_sources = argument_sources
            .iter()
            .map(|source| match source {
                ArgumentSource::Builtin { kind, parameter } => {
                    (u32::from(*parameter) << 8) | u32::from(*kind)
                }
                ArgumentSource::Helper { .. } => unreachable!("no helpers"),
            })
            .collect();
    }
    for helper in &mut helpers {
        helper.frame_parameters = inputs.parameters.clone();
    }
    for setting in selected {
        let name = symbols
            .text(setting.name)
            .ok_or_else(|| AbiError::invariant("setting name spelling unavailable"))?;
        if setting.operation == SettingOperation::In && name != "src" {
            return Err(AbiError::source("only src supports an in setting"));
        }
        match name {
            "name" | "desc" | "category" => match evaluate(&setting.value)? {
                SemanticValue::Text(value) => {
                    let value = value.to_vec();
                    match name {
                        "name" => layout.display_name = Some(value),
                        "desc" => layout.description = Some(value),
                        _ => {
                            layout.category = Category::Text(value);
                            layout.flags &= !0x20;
                        }
                    }
                }
                SemanticValue::Null if name == "category" => {
                    layout.category = Category::Null;
                    layout.flags |= 0x20;
                }
                _ => return Err(fail("unsupported textual procedure setting")),
            },
            "waitfor" | "hidden" | "background" | "instant" | "popup_menu" => {
                let enabled = match number(evaluate(&setting.value)?)? {
                    0 => false,
                    1 => true,
                    _ => return Err(AbiError::source("boolean setting must be zero or one")),
                };
                let (bit, enabled) = match name {
                    "waitfor" => (4, enabled),
                    "hidden" => (1, enabled),
                    "background" => (0x100, enabled),
                    "instant" => (0x200, enabled),
                    _ => (0x40, !enabled),
                };
                if enabled {
                    layout.flags |= bit;
                } else {
                    layout.flags &= !bit;
                }
            }
            "invisibility" => {
                let value = number(evaluate(&setting.value)?)?;
                if value > 127 {
                    return Err(AbiError::source("invisibility exceeds 127"));
                }
                layout.invisibility = Some(value);
                layout.flags |= 8;
                if value > 0 {
                    layout.flags |= 0x10;
                } else {
                    layout.flags &= !0x10;
                }
            }
            "src" => {
                let text = compact(&expression_text(&setting.value, symbols)?)?;
                let (mut kind, mut parameter) = source_mode(&text, false)?
                    .ok_or_else(|| fail("unsupported procedure source setting"))?;
                if text == "usr" && setting.operation == SettingOperation::Assign {
                    kind = 32;
                    parameter = 255;
                }
                layout.source_kind = kind;
                layout.source_parameter = parameter;
                if setting.operation == SettingOperation::Assign {
                    layout.flags |= 2;
                } else {
                    layout.flags &= !2;
                }
            }
            _ => return Err(fail(format!("unsupported procedure setting: {name}"))),
        }
    }
    let executable_body = body
        .iter()
        .filter(|i| !i.header.trim_start().starts_with("set "))
        .cloned()
        .collect();
    Ok(PreparedProcedure {
        inputs,
        layout,
        source_helpers: helpers,
        argument_sources,
        executable_body,
    })
}
#[cfg(test)]
#[path = "procedure_abi_tests.rs"]
mod tests;
