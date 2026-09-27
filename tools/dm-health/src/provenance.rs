//! Groups type diagnostics by the declaration that first lost type information.
//! A finding is linked only when its diagnostic identifies an unambiguous symbol.
use crate::typing::TypeCoverage;
use crate::Finding;
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};

#[derive(Debug, Serialize)]
pub struct RootCauseReport {
    pub traced: usize,
    pub untraced: usize,
    pub untraced_by_rule: BTreeMap<String, usize>,
    pub groups: Vec<RootCause>,
    pub expression_causes: Vec<CauseBucket>,
    pub unresolved_expressions: usize,
    pub expression_roots: Vec<ExpressionRoot>,
    pub rooted_expressions: usize,
    pub fallback_expressions: usize,
}

#[derive(Debug, Serialize)]
pub struct ExpressionRoot {
    pub category: String,
    pub symbol: String,
    pub path: String,
    pub line: usize,
    pub count: usize,
    pub source_linked: bool,
}

#[derive(Debug, Serialize)]
pub struct CauseBucket {
    pub cause: String,
    pub count: usize,
    pub upstream: String,
}

fn upstream(cause: &str) -> &'static str {
    match cause {
        "Local or parameter type" | "Field type" | "Member field" => "Storage declaration",
        "Direct call return" | "Member return" => "Procedure return",
        "Receiver type" | "Wrapped value" | "Dereference result" => "Dependent expression",
        "Collection value"
        | "Collection contents"
        | "Empty collection literal"
        | "Collection constructor contents" => "Collection element",
        "Dynamic call target" | "Dynamic arguments" => "Dynamic dispatch",
        "Unresolved name" => "Name resolution",
        _ => "Operator or expression",
    }
}

#[derive(Debug, Serialize)]
pub struct RootCause {
    pub category: String,
    pub symbol: String,
    pub path: String,
    pub line: usize,
    pub message: String,
    pub dependent_findings: usize,
    pub dependent_rules: Vec<(String, usize)>,
    pub examples: Vec<SourceLocation>,
}

#[derive(Debug, Serialize)]
pub struct SourceLocation {
    pub path: String,
    pub line: usize,
    pub rule: String,
}

fn declaration(f: &Finding) -> Option<(&'static str, String)> {
    match f.rule {
        "unknown-field-type" => Some(("Field", f.message.split_whitespace().next()?.to_owned())),
        "unknown-return-type" => Some((
            "Procedure return",
            f.message.split_whitespace().next()?.to_owned(),
        )),
        "unknown-parameter-type" | "unverified-inferred-parameter" => {
            let (proc, tail) = f.message.split_once(": ")?;
            Some((
                "Parameter",
                format!("{proc}:{}", tail.split_whitespace().next()?),
            ))
        }
        "unknown-local-type" => {
            let symbol = f.message.split_whitespace().next()?;
            Some(("Local", symbol.to_owned()))
        }
        _ => None,
    }
}

fn referenced_symbol(f: &Finding) -> Option<String> {
    match f.rule {
        "unknown-type-flow" => {
            let prefix = f.message.split(':').next()?.trim();
            for marker in [
                "initializer ",
                "override ",
                "assignment to ",
                "field ",
                "argument ",
                "local ",
            ] {
                if let Some(symbol) = prefix.strip_prefix(marker) {
                    return Some(symbol.to_owned());
                }
            }
            None
        }
        "unknown-field-write" | "field-type-conflict" => {
            f.message.split_whitespace().next().map(str::to_owned)
        }
        _ => None,
    }
}

pub fn categorize(findings: &[Finding]) -> RootCauseReport {
    categorize_with_coverage(findings, &TypeCoverage::default())
}

pub fn categorize_with_coverage(findings: &[Finding], coverage: &TypeCoverage) -> RootCauseReport {
    let mut groups = Vec::<RootCause>::new();
    let mut by_symbol = HashMap::<String, usize>::new();
    let mut by_path_local = HashMap::<(String, String), usize>::new();
    for finding in findings {
        let Some((category, symbol)) = declaration(finding) else {
            continue;
        };
        let index = groups.len();
        // Duplicate declarations across DM proc versions are ambiguous; retain the
        // first root but do not attach dependent findings to either version.
        by_symbol
            .entry(symbol.clone())
            .and_modify(|slot| *slot = usize::MAX)
            .or_insert(index);
        if matches!(category, "Local" | "Parameter") {
            let name = symbol
                .rsplit_once(':')
                .map_or(symbol.as_str(), |(_, name)| name);
            by_path_local
                .entry((finding.path.clone(), name.into()))
                .and_modify(|slot| *slot = usize::MAX)
                .or_insert(index);
        }
        groups.push(RootCause {
            category: category.into(),
            symbol,
            path: finding.path.clone(),
            line: finding.line,
            message: finding.message.clone(),
            dependent_findings: 0,
            dependent_rules: Vec::new(),
            examples: Vec::new(),
        });
    }
    let mut traced = 0;
    let mut untraced = 0;
    let mut untraced_by_rule = BTreeMap::new();
    for finding in findings {
        if !finding.rule.starts_with("unknown-") && !finding.rule.starts_with("unresolved-") {
            continue;
        }
        if declaration(finding).is_some() {
            continue;
        }
        let index = referenced_symbol(finding).and_then(|symbol| {
            if let Some(index) = by_path_local.get(&(finding.path.clone(), symbol.clone())) {
                return Some(*index);
            }
            let mut candidate = symbol;
            loop {
                if let Some(index) = by_symbol.get(&candidate) {
                    return Some(*index);
                }
                let (owner, field) = candidate.rsplit_once('.')?;
                let (parent, _) = owner.rsplit_once('/')?;
                if parent.is_empty() {
                    return None;
                }
                candidate = format!("{parent}.{field}");
            }
        });
        if let Some(index) = index.filter(|index| *index != usize::MAX) {
            let group = &mut groups[index];
            group.dependent_findings += 1;
            if let Some((_, count)) = group
                .dependent_rules
                .iter_mut()
                .find(|(rule, _)| rule == finding.rule)
            {
                *count += 1;
            } else {
                group.dependent_rules.push((finding.rule.into(), 1));
            }
            if group.examples.len() < 5 {
                group.examples.push(SourceLocation {
                    path: finding.path.clone(),
                    line: finding.line,
                    rule: finding.rule.into(),
                });
            }
            traced += 1;
        } else {
            untraced += 1;
            *untraced_by_rule.entry(finding.rule.into()).or_default() += 1;
        }
    }
    groups.sort_by(|a, b| {
        b.dependent_findings
            .cmp(&a.dependent_findings)
            .then_with(|| a.path.cmp(&b.path))
            .then_with(|| a.line.cmp(&b.line))
    });
    let mut expression_causes: Vec<_> = coverage
        .unresolved_causes
        .iter()
        .map(|(cause, count)| CauseBucket {
            cause: cause.clone(),
            count: *count,
            upstream: upstream(cause).into(),
        })
        .collect();
    expression_causes.sort_by(|a, b| b.count.cmp(&a.count).then_with(|| a.cause.cmp(&b.cause)));
    let mut expression_roots: Vec<_> = coverage
        .unresolved_roots
        .values()
        .map(|root| ExpressionRoot {
            category: root.category.clone(),
            symbol: root.symbol.clone(),
            path: root.path.clone(),
            line: root.line,
            count: root.count,
            source_linked: !root.path.is_empty()
                && root.line > 0
                && matches!(
                    root.category.as_str(),
                    "Parameter"
                        | "Local"
                        | "Field"
                        | "Procedure return"
                        | "Unknown side effect"
                        | "Unverified value write"
                        | "Local flow value"
                ),
        })
        .collect();
    expression_roots.sort_by(|a, b| {
        b.count
            .cmp(&a.count)
            .then_with(|| a.path.cmp(&b.path))
            .then_with(|| a.line.cmp(&b.line))
    });
    let rooted_expressions = expression_roots
        .iter()
        .filter(|root| root.source_linked)
        .map(|root| root.count)
        .sum();
    let fallback_expressions = expression_roots
        .iter()
        .filter(|root| !root.source_linked)
        .map(|root| root.count)
        .sum();
    RootCauseReport {
        traced,
        untraced,
        untraced_by_rule,
        groups,
        expression_causes,
        unresolved_expressions: coverage.unresolved_expressions,
        expression_roots,
        rooted_expressions,
        fallback_expressions,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn finding(rule: &'static str, line: usize, message: &str) -> Finding {
        Finding {
            rule,
            path: "code/example.dm".into(),
            line,
            severity: "error",
            message: message.into(),
        }
    }
    #[test]
    fn links_exact_field_and_leaves_ambiguous_flow_untraced() {
        let report = categorize(&[
            finding(
                "unknown-field-type",
                2,
                "/datum/example.value has no proven precise single type",
            ),
            finding(
                "unknown-type-flow",
                4,
                "initializer /datum/example.value: cannot prove num fits unknown",
            ),
            finding(
                "unknown-type-flow",
                6,
                "override /datum/example/child.value: cannot prove num fits unknown",
            ),
            finding(
                "unknown-type-flow",
                5,
                "return: cannot prove num fits unknown",
            ),
        ]);
        assert_eq!(report.traced, 2);
        assert_eq!(report.untraced, 1);
        assert_eq!(report.groups[0].dependent_findings, 2);
        assert_eq!(report.groups[0].examples[0].line, 4);
    }
    #[test]
    fn links_unique_local_and_parameter_in_same_file() {
        let report = categorize(&[
            finding(
                "unknown-local-type",
                2,
                "sample has no proven precise single storage type",
            ),
            finding(
                "unknown-parameter-type",
                3,
                "/datum/test/run: amount needs a type contract",
            ),
            finding(
                "unknown-type-flow",
                6,
                "argument sample: cannot prove unknown fits num",
            ),
            finding(
                "unknown-type-flow",
                7,
                "argument amount: cannot prove unknown fits num",
            ),
        ]);
        assert_eq!(report.traced, 2);
        assert_eq!(report.untraced, 0);
    }
    #[test]
    fn repeated_local_name_is_ambiguous() {
        let report = categorize(&[
            finding(
                "unknown-local-type",
                2,
                "sample has no proven precise single storage type",
            ),
            finding(
                "unknown-local-type",
                20,
                "sample has no proven precise single storage type",
            ),
            finding(
                "unknown-type-flow",
                25,
                "argument sample: cannot prove unknown fits num",
            ),
        ]);
        assert_eq!(report.traced, 0);
        assert_eq!(report.untraced, 1);
    }
    #[test]
    fn separates_declaration_roots_from_expression_fallbacks() {
        let mut coverage = TypeCoverage {
            unresolved_expressions: 3,
            ..TypeCoverage::default()
        };
        coverage
            .unresolved_causes
            .insert("Local or parameter type".into(), 2);
        coverage
            .unresolved_causes
            .insert("Operator or unsupported expression".into(), 1);
        coverage.unresolved_roots.insert(
            "local".into(),
            crate::typing::UnknownRootCount {
                category: "Local".into(),
                symbol: "value".into(),
                path: "code/example.dm".into(),
                line: 2,
                count: 2,
            },
        );
        coverage.unresolved_roots.insert(
            "fallback".into(),
            crate::typing::UnknownRootCount {
                category: "Operator or unsupported expression".into(),
                symbol: "DMASTMystery".into(),
                path: "code/example.dm".into(),
                line: 8,
                count: 1,
            },
        );
        let report = categorize_with_coverage(&[], &coverage);
        assert_eq!(report.rooted_expressions, 2);
        assert_eq!(report.fallback_expressions, 1);
        assert_eq!(report.expression_causes.len(), 2);
        assert!(report.expression_roots[0].source_linked);
        assert!(!report.expression_roots[1].source_linked);
    }
}
