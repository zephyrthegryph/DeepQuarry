//! Collect explicit DM health annotations from source comments.
use regex::Regex;
use std::sync::LazyLock;

static INVALID_FIELD: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(?:/[\w/]+/)?var/(?:[A-Za-z_]\w*/)*[A-Za-z_]\w*\b").expect("static regex")
});
static INVALID_PROC: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(?:/[\w/]+/)?(?:proc/|verb/)?[A-Za-z_]\w*\s*\(").expect("static regex")
});
static INVALID_GLOBAL: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^GLOBAL_(?:VAR|LIST|ALIST|DATUM)(?:_[A-Z_]+)?\(").expect("static regex")
});
static ABSOLUTE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(/[\w/]+)/(?:var/(?:[A-Za-z_]\w*/)*|proc/|verb/)([A-Za-z_]\w*)\b")
        .expect("static regex")
});
static ABSOLUTE_PROC: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(/[\w/]+?)/(?:proc/|verb/)?([A-Za-z_]\w*)\s*\(").expect("static regex")
});
static ROOT_PROC: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^/(?:proc|verb)/([A-Za-z_]\w*)\s*\(").expect("static regex"));
static TY: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^(/[\w/]+)\s*$").expect("static regex"));
static RELATIVE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^\s+(?:var/(?:[A-Za-z_]\w*/)*|proc/|verb/)([A-Za-z_]\w*)\b").expect("static regex")
});
static RELATIVE_PROC: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s+([A-Za-z_]\w*)\s*\(").expect("static regex"));
static RELATIVE_DECL_PROC: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s+(?:proc/|verb/)([A-Za-z_]\w*)\s*\(").expect("static regex"));
static GLOBAL_MACRO: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^\s*GLOBAL_(?:VAR|LIST|ALIST|DATUM)(?:_(?:INIT|EMPTY|CONST|TYPED|INIT_TYPED|EMPTY_TYPED))?\(\s*([A-Za-z_]\w*)").expect("static regex")
});

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Visibility {
    Public,
    Private,
    Protected,
    NonNull,
    Nullable,
    ReadOnly,
    ParentFirst,
    ParentAlways,
    NoSleep,
    ParentRequiredByOverrides,
    ParentExemptOverride,
    TypeHint,
    TypeAlias,
    ParamType,
    LocalType,
    ReturnType,
    InitializedBy,
    Tracked,
}

#[derive(Clone, Debug)]
pub struct Contract {
    pub owner: String,
    pub member: String,
    pub visibility: Visibility,
    pub parameter: Option<String>,
    pub value: Option<String>,
}

fn annotation(line: &str) -> Option<(Visibility, Option<String>, Option<String>)> {
    let text = line.trim().strip_prefix("//")?.trim();
    let text = text.strip_prefix("dm-health: ").unwrap_or(text);
    if let Some(rest) = text.strip_prefix("alias ") {
        let (name, ty) = rest.split_once('=')?;
        let name = name.trim();
        let ty = ty.trim();
        if !name.is_empty()
            && name
                .chars()
                .next()
                .is_some_and(|ch| ch.is_ascii_alphabetic() || ch == '_')
            && name
                .chars()
                .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
            && !ty.is_empty()
        {
            return Some((Visibility::TypeAlias, Some(name.into()), Some(ty.into())));
        }
    }
    if let Some(ty) = text.strip_prefix("type ") {
        return Some((Visibility::TypeHint, None, Some(ty.trim().into())));
    }
    if let Some(ty) = text.strip_prefix("returns ") {
        return Some((Visibility::ReturnType, None, Some(ty.trim().into())));
    }
    if let Some(rest) = text.strip_prefix("param ") {
        let (name, ty) = rest.trim().split_once(char::is_whitespace)?;
        if !name.is_empty() && !ty.trim().is_empty() {
            return Some((
                Visibility::ParamType,
                Some(name.into()),
                Some(ty.trim().into()),
            ));
        }
    }
    if let Some(rest) = text.strip_prefix("local ") {
        let (name, ty) = rest.trim().split_once(char::is_whitespace)?;
        if !name.is_empty() && !ty.trim().is_empty() {
            return Some((
                Visibility::LocalType,
                Some(name.into()),
                Some(ty.trim().into()),
            ));
        }
    }
    if let Some(phase) = text.strip_prefix("initialized-by ") {
        return Some((Visibility::InitializedBy, None, Some(phase.trim().into())));
    }
    if let Some(setter) = text
        .strip_prefix("tracked(setter=")
        .and_then(|rest| rest.strip_suffix(')'))
    {
        if !setter.is_empty()
            && setter
                .chars()
                .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
            && !setter.chars().next().unwrap().is_ascii_digit()
        {
            return Some((Visibility::Tracked, None, Some(setter.into())));
        }
    }
    for (name, visibility) in [
        ("public", Visibility::Public),
        ("private", Visibility::Private),
        ("protected", Visibility::Protected),
        ("nonnull", Visibility::NonNull),
        ("nullable", Visibility::Nullable),
        ("readonly", Visibility::ReadOnly),
        ("parent-first", Visibility::ParentFirst),
        ("parent-always", Visibility::ParentAlways),
        ("no-sleep", Visibility::NoSleep),
    ] {
        if text == name {
            return Some((visibility, None, None));
        }
        if let Some(parameter) = text
            .strip_prefix(name)
            .and_then(|rest| rest.strip_prefix('('))
            .and_then(|rest| rest.strip_suffix(')'))
        {
            if !parameter.is_empty()
                && parameter
                    .chars()
                    .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
            {
                return Some((visibility, Some(parameter.into()), None));
            }
        }
    }
    None
}

pub fn invalid_annotations(source: &str) -> Vec<(usize, String)> {
    let field = &*INVALID_FIELD;
    let proc = &*INVALID_PROC;
    let global = &*INVALID_GLOBAL;
    let mut invalid = Vec::new();
    let mut pending = Vec::new();
    for (index, line) in source.lines().enumerate() {
        let trimmed = line.trim();
        if let Some(comment) = trimmed.strip_prefix("//").map(str::trim) {
            if comment.starts_with("dm-health:") {
                if let Some((visibility, parameter, _)) = annotation(line) {
                    if visibility != Visibility::TypeAlias {
                        pending.push((index + 1, visibility, parameter));
                    }
                } else {
                    invalid.push((index + 1, comment.into()));
                }
            } else if !pending.is_empty() {
                for (line, _, _) in pending.drain(..) {
                    invalid.push((
                        line,
                        "dm-health contract has no adjacent declaration".into(),
                    ));
                }
            }
            continue;
        }
        if pending.is_empty() {
            continue;
        }
        if trimmed.is_empty() {
            for (line, _, _) in pending.drain(..) {
                invalid.push((
                    line,
                    "dm-health contract has no adjacent declaration".into(),
                ));
            }
            continue;
        }
        let is_field = field.is_match(trimmed);
        let is_proc = proc.is_match(trimmed);
        let is_global = global.is_match(trimmed);
        for (line, visibility, parameter) in pending.drain(..) {
            let valid = if is_field {
                parameter.is_none()
                    && matches!(
                        visibility,
                        Visibility::Public
                            | Visibility::Private
                            | Visibility::Protected
                            | Visibility::NonNull
                            | Visibility::Nullable
                            | Visibility::ReadOnly
                            | Visibility::TypeHint
                            | Visibility::InitializedBy
                            | Visibility::Tracked
                    )
            } else if is_global {
                parameter.is_none()
                    && matches!(
                        visibility,
                        Visibility::ReadOnly
                            | Visibility::NonNull
                            | Visibility::Nullable
                            | Visibility::TypeHint
                    )
            } else if is_proc {
                matches!(
                    visibility,
                    Visibility::Public
                        | Visibility::Private
                        | Visibility::Protected
                        | Visibility::NonNull
                        | Visibility::Nullable
                        | Visibility::ParentFirst
                        | Visibility::ParentAlways
                        | Visibility::NoSleep
                        | Visibility::ParamType
                        | Visibility::LocalType
                        | Visibility::ReturnType
                )
            } else {
                false
            };
            if !valid {
                invalid.push((
                    line,
                    "dm-health contract does not apply to the next declaration".into(),
                ));
            }
        }
    }
    for (line, _, _) in pending {
        invalid.push((
            line,
            "dm-health contract has no adjacent declaration".into(),
        ));
    }
    invalid
}

pub fn collect(source: &str) -> Vec<Contract> {
    if !source.contains("dm-health:")
        && !source.contains("// public")
        && !source.contains("// private")
        && !source.contains("// protected")
        && !source.contains("// nonnull")
        && !source.contains("// nullable")
        && !source.contains("// readonly")
        && !source.contains("// parent-first")
        && !source.contains("// parent-always")
        && !source.contains("// no-sleep")
        && !source.contains("tracked(setter=")
        && !source.contains("SHOULD_CALL_PARENT(")
        && !source.contains("SHOULD_NOT_SLEEP(")
        && !source.contains("RETURN_TYPE(")
    {
        return Vec::new();
    }
    let absolute = &*ABSOLUTE;
    let absolute_proc = &*ABSOLUTE_PROC;
    let root_proc = &*ROOT_PROC;
    let ty = &*TY;
    let relative = &*RELATIVE;
    let relative_proc = &*RELATIVE_PROC;
    let relative_decl_proc = &*RELATIVE_DECL_PROC;
    let global_macro = &*GLOBAL_MACRO;
    let mut result = Vec::new();
    let mut owner: Option<String> = None;
    let mut current_proc: Option<(String, String, usize)> = None;
    let mut pending = Vec::new();
    for line in source.lines() {
        if let Some(contract) = annotation(line) {
            if contract.0 == Visibility::TypeAlias {
                result.push(Contract {
                    owner: "$typealias".into(),
                    member: contract.1.unwrap_or_default(),
                    visibility: Visibility::TypeAlias,
                    parameter: None,
                    value: contract.2,
                });
            } else {
                pending.push(contract);
            }
            continue;
        }
        if line.trim().is_empty() {
            pending.clear();
            continue;
        }
        if line.trim_start().starts_with("//") {
            pending.clear();
            continue;
        }
        let indent = line.chars().take_while(|ch| ch.is_whitespace()).count();
        if current_proc
            .as_ref()
            .is_some_and(|(_, _, start)| indent <= *start)
        {
            current_proc = None;
        }
        if let Some((proc_owner, proc_name, _)) = &current_proc {
            // SpacemanDMM's existing return pragma is erased by OpenDream's
            // normal preprocessing, so collect its literal type from source.
            if let Some(value) = line
                .trim()
                .strip_prefix("RETURN_TYPE(")
                .and_then(|value| value.strip_suffix(')'))
                .map(str::trim)
                .filter(|value| {
                    *value == "num"
                        || *value == "text"
                        || *value == "null"
                        || value.starts_with('/')
                            && !value.starts_with("/list/")
                            && value[1..]
                                .chars()
                                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '/')
                })
            {
                result.push(Contract {
                    owner: proc_owner.clone(),
                    member: proc_name.clone(),
                    visibility: Visibility::ReturnType,
                    parameter: None,
                    value: Some(value.into()),
                });
            }
            let visibility = match line.trim() {
                "SHOULD_CALL_PARENT(TRUE)" => Some(Visibility::ParentRequiredByOverrides),
                "SHOULD_CALL_PARENT(FALSE)" => Some(Visibility::ParentExemptOverride),
                "SHOULD_NOT_SLEEP(TRUE)" => Some(Visibility::NoSleep),
                _ => None,
            };
            if let Some(visibility) = visibility {
                result.push(Contract {
                    owner: proc_owner.clone(),
                    member: proc_name.clone(),
                    visibility,
                    parameter: None,
                    value: None,
                });
            }
        }
        if let Some(capture) = ty.captures(line) {
            owner = Some(capture[1].into());
        }
        for (visibility, parameter, value) in pending.drain(..) {
            if let Some(capture) = root_proc.captures(line) {
                result.push(Contract {
                    owner: "/".into(),
                    member: capture[1].into(),
                    visibility,
                    parameter,
                    value: value.clone(),
                });
            } else if let Some(capture) = absolute
                .captures(line)
                .or_else(|| absolute_proc.captures(line))
            {
                result.push(Contract {
                    owner: capture[1].into(),
                    member: capture[2].into(),
                    visibility,
                    parameter,
                    value: value.clone(),
                });
            } else if let Some(capture) = global_macro.captures(line) {
                if matches!(
                    visibility,
                    Visibility::ReadOnly
                        | Visibility::Nullable
                        | Visibility::NonNull
                        | Visibility::TypeHint
                ) {
                    result.push(Contract {
                        owner: "GLOB".into(),
                        member: capture[1].into(),
                        visibility,
                        parameter: None,
                        value: value.clone(),
                    });
                }
            } else if let (Some(current), Some(capture)) = (
                &owner,
                relative
                    .captures(line)
                    .or_else(|| relative_proc.captures(line)),
            ) {
                result.push(Contract {
                    owner: current.clone(),
                    member: capture[1].into(),
                    visibility,
                    parameter,
                    value: value.clone(),
                });
            }
        }
        if let Some(capture) = root_proc.captures(line) {
            current_proc = Some(("/".into(), capture[1].into(), indent));
        } else if let Some(capture) = absolute_proc.captures(line) {
            current_proc = Some((capture[1].into(), capture[2].into(), indent));
        } else if global_macro.is_match(line) {
            current_proc = None;
        } else if let Some(capture) = relative_proc
            .captures(line)
            .or_else(|| relative_decl_proc.captures(line))
        {
            if let Some(current) = &owner {
                current_proc = Some((current.clone(), capture[1].into(), indent));
            }
        }
        if !line.starts_with(char::is_whitespace) && !line.trim_start().starts_with("//") {
            owner = ty.captures(line).map(|capture| capture[1].into());
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn existing_return_type_pragma_attaches_to_proc() {
        let contracts = collect(
            "/atom/proc/init_forensic_data()\n\tRETURN_TYPE(/datum/forensics_crime)\n\treturn forensic_data\n",
        );
        assert_eq!(contracts.len(), 1);
        assert_eq!(contracts[0].owner, "/atom");
        assert_eq!(contracts[0].member, "init_forensic_data");
        assert_eq!(contracts[0].visibility, Visibility::ReturnType);
        assert_eq!(
            contracts[0].value.as_deref(),
            Some("/datum/forensics_crime")
        );
    }

    #[test]
    fn readonly_global_macro_contract() {
        let contracts = collect("// dm-health: readonly\nGLOBAL_LIST_EMPTY(important_items)\n");
        assert_eq!(contracts.len(), 1);
        assert_eq!(contracts[0].owner, "GLOB");
        assert_eq!(contracts[0].member, "important_items");
        assert_eq!(contracts[0].visibility, Visibility::ReadOnly);
    }

    #[test]
    fn global_macro_preserves_explicit_type_contract() {
        let contracts =
            collect("/datum/test\n// dm-health: type list<num>?\nGLOBAL_LIST_EMPTY(numbers)\n");
        assert_eq!(contracts.len(), 1);
        assert_eq!(contracts[0].owner, "GLOB");
        assert_eq!(contracts[0].member, "numbers");
        assert_eq!(contracts[0].value.as_deref(), Some("list<num>?"));
    }
    #[test]
    fn misplaced_and_dangling_contracts_are_invalid() {
        let source = "// dm-health: initialized-by New\n/datum/test/proc/Run()\n\
// dm-health: returns num\n/datum/test/var/count\n\
// dm-health: type num\n\n/datum/test/var/later\n\
// dm-health: type list<num>?\nGLOBAL_LIST_EMPTY(numbers)\n";
        let invalid = invalid_annotations(source);
        assert_eq!(invalid.len(), 3);
        assert_eq!(invalid[0].0, 1);
        assert_eq!(invalid[1].0, 3);
        assert_eq!(invalid[2].0, 5);
    }
    #[test]
    fn tracked_annotation_requires_valid_setter_name() {
        let contracts =
            collect("// dm-health: tracked(setter=set_charge)\n/datum/cell/var/charge\n");
        assert_eq!(contracts.len(), 1);
        assert_eq!(contracts[0].visibility, Visibility::Tracked);
        assert_eq!(contracts[0].value.as_deref(), Some("set_charge"));
        assert_eq!(
            invalid_annotations("// dm-health: tracked(setter=1bad)").len(),
            1
        );
    }
    #[test]
    fn exact_annotations_attach_to_next_member() {
        let contracts = collect("// dm-health: private\n/datum/vault/var/key\n// dm-health: protected\n/datum/vault/proc/Reset()\n");
        assert_eq!(contracts.len(), 2);
        assert_eq!(contracts[0].owner, "/datum/vault");
        assert_eq!(contracts[0].visibility, Visibility::Private);
        assert_eq!(contracts[1].member, "Reset");
        assert_eq!(
            collect("// dm-health: nullable\n/datum/vault/var/key\n")[0].visibility,
            Visibility::Nullable
        );
        assert_eq!(
            collect("// private\n/datum/vault/var/key\n")[0].visibility,
            Visibility::Private
        );
    }
    #[test]
    fn typed_relative_field_contract_targets_the_field() {
        let contracts = collect(
            "/datum/health_init\n    // dm-health: initialized-by New\n    var/num/number\n",
        );
        assert_eq!(contracts.len(), 1);
        assert_eq!(contracts[0].owner, "/datum/health_init");
        assert_eq!(contracts[0].member, "number");
        let absolute = collect("// dm-health: nullable\n/datum/health_init/var/list/items\n");
        assert_eq!(absolute.len(), 1);
        assert_eq!(absolute[0].owner, "/datum/health_init");
        assert_eq!(absolute[0].member, "items");
    }
    #[test]
    fn stacked_annotations_and_explicit_public() {
        let contracts =
            collect("// dm-health: public\n// dm-health: nonnull\n/datum/vault/var/key\n");
        assert_eq!(contracts.len(), 2);
        assert_eq!(contracts[0].visibility, Visibility::Public);
        assert_eq!(contracts[1].visibility, Visibility::NonNull);
    }
    #[test]
    fn parent_first_attaches_to_bare_override() {
        let contracts =
            collect("/datum/example\n    // dm-health: parent-first\n    Initialize()\n");
        assert_eq!(contracts.len(), 1);
        assert_eq!(contracts[0].owner, "/datum/example");
        assert_eq!(contracts[0].member, "Initialize");
        assert_eq!(contracts[0].visibility, Visibility::ParentFirst);
    }
    #[test]
    fn existing_parent_pragma_attaches_to_declaring_proc() {
        let contracts = collect("/datum/base/proc/Run()\n\tSHOULD_CALL_PARENT(TRUE)\n\treturn 1\n");
        assert!(contracts.iter().any(|c| c.owner == "/datum/base"
            && c.member == "Run"
            && c.visibility == Visibility::ParentRequiredByOverrides));
        let relative = collect("/datum/base\n\tproc/Run()\n\t\tSHOULD_CALL_PARENT(TRUE)\n");
        assert!(relative.iter().any(|c| c.owner == "/datum/base"
            && c.member == "Run"
            && c.visibility == Visibility::ParentRequiredByOverrides));
    }
    #[test]
    fn no_sleep_comment_and_existing_pragma_attach_to_procs() {
        for source in [
            "// dm-health: no-sleep\n/datum/test/proc/Run()\n",
            "/datum/test/proc/Run()\n\tSHOULD_NOT_SLEEP(TRUE)\n",
        ] {
            let contracts = collect(source);
            assert!(contracts
                .iter()
                .any(|contract| contract.owner == "/datum/test"
                    && contract.member == "Run"
                    && contract.visibility == Visibility::NoSleep));
        }
        assert_eq!(
            invalid_annotations("// dm-health: no-sleep\n/datum/test/var/value\n").len(),
            1
        );
    }
    #[test]
    fn local_type_contract_attaches_to_proc() {
        let source = "// dm-health: local cache list<text>\n/datum/test/proc/Read()\n";
        let contracts = collect(source);
        assert_eq!(contracts.len(), 1);
        assert_eq!(contracts[0].visibility, Visibility::LocalType);
        assert_eq!(contracts[0].owner, "/datum/test");
        assert_eq!(contracts[0].member, "Read");
        assert_eq!(contracts[0].parameter.as_deref(), Some("cache"));
        assert_eq!(contracts[0].value.as_deref(), Some("list<text>"));
        assert!(invalid_annotations(source).is_empty());
    }
    #[test]
    fn medical_collection_contracts_attach_to_their_real_fields() {
        let body = collect(include_str!("../../../code/modules/body/affliction.dm"));
        let causes = collect(include_str!(
            "../../../code/modules/medical/causes/_cause.dm"
        ));
        for (contracts, owner, member, ty) in [
            (&body, "/datum/affliction", "treated_by", "assoc<text,num>?"),
            (
                &body,
                "/datum/affliction",
                "organ_damage_targets",
                "list<text>?",
            ),
            (
                &body,
                "/datum/affliction",
                "symptom_pool",
                "assoc<typepath</datum/affliction_symptom>,num>?",
            ),
            (
                &causes,
                "/datum/affliction_trigger/injury",
                "body_regions",
                "list<text>?",
            ),
        ] {
            assert!(
                contracts.iter().any(|contract| contract.owner == owner
                    && contract.member == member
                    && contract.visibility == Visibility::TypeHint
                    && contract.value.as_deref() == Some(ty)),
                "missing contract for {owner}.{member}"
            );
        }
    }
    #[test]
    fn global_proc_annotation_uses_root_owner() {
        let contracts = collect(
            "// dm-health: param symptoms assoc<text,num>\n/proc/chem_stage(list/symptoms)\n",
        );
        assert_eq!(contracts.len(), 1);
        assert_eq!(contracts[0].owner, "/");
        assert_eq!(contracts[0].member, "chem_stage");
        assert_eq!(contracts[0].parameter.as_deref(), Some("symptoms"));
        let real = collect(include_str!(
            "../../../code/modules/medical/conditions/pharmacology/_pharmacology.dm"
        ));
        assert!(real.iter().any(|contract| contract.owner == "/"
            && contract.member == "chem_stage"
            && contract.parameter.as_deref() == Some("symptom_pool")
            && contract.value.as_deref()
                == Some("assoc<typepath</datum/affliction_symptom>,num>")));
        for parameter in ["min_symptoms", "max_symptoms"] {
            assert!(real.iter().any(|contract| contract.owner == "/"
                && contract.member == "chem_stage"
                && contract.parameter.as_deref() == Some(parameter)
                && contract.value.as_deref() == Some("num")));
        }
        assert!(real.iter().any(|contract| contract.owner == "/"
            && contract.member == "chem_stage"
            && contract.parameter.as_deref() == Some("extra")
            && contract.value.as_deref() == Some("@ChemStageExtra?")));
        for parameter in ["mild", "severe", "critical"] {
            assert!(real.iter().any(|contract| contract.owner == "/"
                && contract.member == "overdose_stages"
                && contract.parameter.as_deref() == Some(parameter)
                && contract.value.as_deref() == Some("@ChemStage")));
        }
    }
}
