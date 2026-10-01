//! Builtin calls whose native BYOND 516.1687 lowering is a sequence of
//! argument pushes, optional constant defaults, and one opcode.
//!
//! `fixtures/native_compiler/builtin_catalog.dm` is the source probe; its
//! `.native.bin` companion is the output of DreamMaker 516.1687. Calls with
//! arity-dependent opcodes or special references stay in dedicated lowering.

use crate::ValueWord;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OpcodeCountPolicy {
    None,
    /// Append the number of arguments passed by the caller as a word operand.
    EmittedArgs,
    /// Fixed native operand, independent of supplied argument count.
    Fixed(u32),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BuiltinSpec {
    pub opcode: u32,
    pub min_args: usize,
    pub max_args: usize,
    /// Defaults are pushed in order after supplied arguments. This slice has
    /// one entry per argument omitted from a call at `min_args` arity.
    pub trailing_defaults: &'static [ValueWord],
    pub count_operand: OpcodeCountPolicy,
    /// Optional opcode emitted after the builtin produces its value.
    pub post_opcode: Option<u32>,
}

fn fixed(opcode: u32, args: usize) -> BuiltinSpec {
    BuiltinSpec {
        opcode,
        min_args: args,
        max_args: args,
        trailing_defaults: &[],
        count_operand: OpcodeCountPolicy::None,
        post_opcode: None,
    }
}

pub fn is_void(name: &str) -> bool {
    matches!(
        name,
        "rand_seed"
            | "shutdown"
            | "flick"
            | "winset"
            | "winshow"
            | "winclone"
            | "walk"
            | "walk_to"
            | "walk_away"
            | "walk_towards"
            | "walk_rand"
    )
}

fn optional(opcode: u32, min: usize, defaults: &'static [ValueWord], flag: bool) -> BuiltinSpec {
    BuiltinSpec {
        opcode,
        min_args: min,
        max_args: min + defaults.len(),
        trailing_defaults: defaults,
        count_operand: OpcodeCountPolicy::None,
        post_opcode: flag.then_some(0x36),
    }
}

/// Some native builtins select a different instruction when optional arguments are supplied.
pub fn lookup_with_arity(name: &str, arity: usize) -> Option<BuiltinSpec> {
    if matches!(name, "bounds" | "obounds") && arity <= 5 {
        let mut spec = fixed(if name == "bounds" { 0x11b } else { 0x11c }, arity);
        spec.count_operand = OpcodeCountPolicy::EmittedArgs;
        return Some(spec);
    }
    if name == "pixloc" && (1..=3).contains(&arity) {
        let mut spec = fixed(0x17f, arity);
        spec.count_operand = OpcodeCountPolicy::EmittedArgs;
        return Some(spec);
    }
    if name == "block" && (3..=6).contains(&arity) {
        return Some(optional(
            0x170,
            3,
            &[ValueWord::Null, ValueWord::Null, ValueWord::Null],
            false,
        ));
    }
    let alternate = match (name, arity) {
        ("icon_states", 2) => Some((0x114, 2, false)),
        ("roll", 2) => Some((0x57, 2, false)),
        ("step", 3) => Some((0x11e, 3, true)),
        ("step_towards", 3) => Some((0x121, 3, true)),
        ("step_rand", 2) => Some((0x122, 2, true)),
        ("step_to", 4) => Some((0x11f, 4, true)),
        ("step_away", 4) => Some((0x120, 4, true)),
        ("walk", 4) => Some((0x123, 4, false)),
        ("walk_to", 5) => Some((0x124, 5, false)),
        ("walk_towards", 4) => Some((0x126, 4, false)),
        ("walk_away", 5) => Some((0x125, 5, false)),
        ("walk_rand", 3) => Some((0x127, 3, false)),
        _ => None,
    };
    if let Some((opcode, args, flag)) = alternate {
        let mut spec = fixed(opcode, args);
        spec.post_opcode = flag.then_some(0x36);
        Some(spec)
    } else {
        lookup(name)
    }
}

/// Returns only calls whose stack shape was checked against the native
/// compiler. In particular, `round`, `arctan`, `log`, `num2text`, and
/// `text2num` have other arities with different opcodes; their extra forms
/// must be handled by specialized lowering.
pub fn lookup(name: &str) -> Option<BuiltinSpec> {
    let added = match name {
        "addtext" => Some(BuiltinSpec {
            opcode: 0x6c,
            min_args: 2,
            max_args: usize::MAX,
            trailing_defaults: &[],
            count_operand: OpcodeCountPolicy::EmittedArgs,
            post_opcode: None,
        }),
        "bounds_dist" => Some(fixed(0x11d, 2)),
        "eval" => Some(fixed(0x103, 1)),
        "ispointer" => Some(fixed(0x166, 1)),
        "lentext" => Some(fixed(0x6d, 1)),
        "shutdown" => Some(fixed(0x5d, 0)),
        "findtextEx_char" => Some(optional(
            0x150,
            2,
            &[ValueWord::Number(0x3f800000), ValueWord::Null],
            false,
        )),
        "findlasttext_char" | "findlasttextEx_char" => Some(optional(
            if name == "findlasttext_char" {
                0x153
            } else {
                0x154
            },
            2,
            &[ValueWord::Number(0), ValueWord::Number(0x3f800000)],
            false,
        )),
        "replacetext_char" | "replacetextEx_char" => Some(optional(
            if name == "replacetext_char" {
                0x151
            } else {
                0x152
            },
            3,
            &[ValueWord::Number(0x3f800000), ValueWord::Null],
            false,
        )),
        "ftime" => Some(optional(0x16f, 1, &[ValueWord::Null], false)),
        "get_steps_to" => Some(optional(0x175, 2, &[ValueWord::Null], false)),
        "noise_hash" => Some(BuiltinSpec {
            opcode: 0x172,
            min_args: 1,
            max_args: usize::MAX,
            trailing_defaults: &[],
            count_operand: OpcodeCountPolicy::EmittedArgs,
            post_opcode: None,
        }),
        "bounds" | "obounds" => {
            let mut spec = fixed(if name == "bounds" { 0x11b } else { 0x11c }, 0);
            spec.count_operand = OpcodeCountPolicy::EmittedArgs;
            Some(spec)
        }

        "lerp" => Some(fixed(0x187, 3)),
        "values_sum" => Some(fixed(0x188, 1)),
        "values_product" => Some(fixed(0x189, 1)),
        "values_dot" => Some(fixed(0x18a, 2)),
        "values_cut_under" => Some(optional(0x18b, 2, &[ValueWord::Null], false)),
        "values_cut_over" => Some(optional(0x18c, 2, &[ValueWord::Null], false)),
        "bound_pixloc" => Some(fixed(0x181, 2)),
        "pixloc" => Some(BuiltinSpec {
            opcode: 0x17f,
            min_args: 1,
            max_args: 1,
            trailing_defaults: &[],
            count_operand: OpcodeCountPolicy::EmittedArgs,
            post_opcode: None,
        }),
        "ref" => Some(fixed(0x148, 1)),
        "refcount" => Some(fixed(0x178, 1)),
        "trunc" => Some(fixed(0x16a, 1)),
        "fract" => Some(fixed(0x16b, 1)),
        "sign" => Some(fixed(0x186, 1)),
        "shell" => Some(fixed(0x98, 1)),
        "rand_seed" => Some(fixed(0xda, 1)),
        "flick" => Some(fixed(0x5c, 2)),
        "winset" => Some(fixed(0x10c, 3)),
        "winget" => Some(fixed(0x10d, 3)),
        "winexists" => Some(fixed(0x118, 2)),
        "winclone" => Some(fixed(0x10e, 3)),
        "winshow" => Some(optional(0x10f, 2, &[ValueWord::Number(0x3f800000)], false)),
        "findtext_char" => Some(optional(
            0x14f,
            2,
            &[ValueWord::Number(0x3f800000), ValueWord::Null],
            false,
        )),
        "splicetext" | "splicetext_char" => Some(optional(
            if name == "splicetext" { 0x15f } else { 0x160 },
            3,
            &[ValueWord::Null],
            false,
        )),
        "spantext_char" | "nonspantext_char" => Some(optional(
            if name == "spantext_char" {
                0x155
            } else {
                0x156
            },
            2,
            &[ValueWord::Number(0x3f800000)],
            false,
        )),
        "text2ascii_char" => Some(optional(0x14c, 1, &[ValueWord::Null], false)),
        "splittext_char" => Some(optional(
            0x157,
            2,
            &[
                ValueWord::Number(0x3f800000),
                ValueWord::Null,
                ValueWord::Null,
            ],
            false,
        )),
        "icon_states" => Some(fixed(0xdd, 1)),
        "roll" => Some(fixed(0x5f, 1)),
        "step" => Some(optional(0x86, 2, &[], true)),
        "step_towards" => Some(optional(0x89, 2, &[], true)),
        "step_rand" => Some(optional(0x8a, 1, &[], true)),
        "step_to" | "step_away" => Some(optional(
            if name == "step_to" { 0x87 } else { 0x88 },
            2,
            &[ValueWord::Null],
            true,
        )),
        "get_step_to" => Some(optional(0x91, 2, &[ValueWord::Null], false)),
        "walk" => Some(optional(0x8b, 2, &[ValueWord::Null], false)),
        "walk_to" | "walk_away" => Some(optional(
            if name == "walk_to" { 0x8c } else { 0x8d },
            2,
            &[ValueWord::Null, ValueWord::Null],
            false,
        )),
        "walk_towards" => Some(optional(0x8e, 2, &[ValueWord::Null], false)),
        "walk_rand" => Some(optional(0x8f, 1, &[ValueWord::Null], false)),
        "viewers" | "oview" | "oviewers" | "range" | "hearers" | "ohearers" => {
            let opcode = match name {
                "viewers" => 0xe5,
                "oview" => 0x1c,
                "oviewers" => 0xe6,
                "range" => 0x59,
                "hearers" => 0xe7,
                _ => 0xe8,
            };
            let mut spec = optional(opcode, 0, &[ValueWord::Null, ValueWord::Null], false);
            if name == "range" {
                spec.count_operand = OpcodeCountPolicy::Fixed(0xae);
            }
            Some(spec)
        }
        "block" => Some(fixed(0x1f, 2)),
        "trimtext" => Some(fixed(0x16e, 1)),
        _ => None,
    };
    if added.is_some() {
        return added;
    }
    if let Some(opcode) = match name {
        "ismovable" => Some(0x149),
        "isnan" => Some(0x16c),
        "isinf" => Some(0x16d),
        "isloc" => Some(0x13),
        "ismob" => Some(0x14),
        "isobj" => Some(0x15),
        "isarea" => Some(0x16),
        "isturf" => Some(0x17),
        _ => None,
    } {
        let mut spec = fixed(opcode, 1);
        spec.post_opcode = Some(0x36);
        return Some(spec);
    }
    let (opcode, args) = match name {
        "abs" => (0x68, 1),
        "sin" => (0x182, 1),
        "cos" => (0x183, 1),
        "tan" => (0x184, 1),
        "arcsin" => (0xc4, 1),
        "arccos" => (0xc5, 1),
        "arctan" => (0x145, 1),
        "sqrt" => (0x69, 1),
        "log" => (0x31, 1),
        "round" | "floor" => (0x43, 1),
        "ceil" => (0x169, 1),
        "length" => (0x6d, 1),
        "length_char" => (0x14d, 1),
        "lowertext" => (0x75, 1),
        "uppertext" => (0x74, 1),
        "num2text" => (0x77, 1),
        "text2num" => (0x76, 1),
        "isnull" => (0x9e, 1),
        "isnum" => (0x9f, 1),
        "istext" => (0xa0, 1),
        "islist" => (0x147, 1),
        "ispath" => (0xf5, 1),
        "isfile" => (0xe4, 1),
        "isicon" => (0x28, 1),
        "get_dir" => (0x96, 2),
        "get_dist" => (0x95, 2),
        "get_step" => (0x90, 2),
        "get_step_towards" => (0x93, 2),
        "get_step_rand" => (0x94, 1),
        "turn" => (0x6b, 2),
        "locate" => (0x5b, 1),
        "hascall" => (0xbc, 2),
        "load_ext" => (0x179, 2),
        "fcopy" => (0x9b, 2),
        "fdel" => (0xb4, 1),
        "fexists" => (0xf7, 1),
        "file2text" => (0x9a, 1),
        "text2file" => (0x99, 2),
        "flist" => (0xac, 1),
        "fcopy_rsc" => (0xd7, 1),
        "text2path" => (0x10a, 1),
        "params2list" => (0xb8, 1),
        "list2params" => (0xb7, 1),
        "prob" => (0x21, 1),
        "md5" => (0x109, 1),
        "sha1" => (0x14b, 1),
        "json_encode" => (0x138, 1),
        "json_decode" => (0x139, 1),
        "html_encode" => (0xbe, 1),
        "html_decode" => (0xbf, 1),
        "url_decode" => (0x108, 1),
        "ckey" => (0xa8, 1),
        "ckeyEx" => (0xb9, 1),
        "ascii2text" => (0xdc, 1),
        "rgb" => (0xbb, 3),
        "matrix" => {
            return Some(BuiltinSpec {
                opcode: 0x12a,
                min_args: 0,
                max_args: usize::MAX,
                trailing_defaults: &[],
                count_operand: OpcodeCountPolicy::EmittedArgs,
                post_opcode: None,
            });
        }
        "view" => {
            return Some(BuiltinSpec {
                opcode: 0x1b,
                min_args: 0,
                max_args: 2,
                trailing_defaults: &[ValueWord::Null, ValueWord::Null],
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "time2text" => {
            return Some(BuiltinSpec {
                opcode: 0xc0,
                min_args: 0,
                max_args: 2,
                trailing_defaults: &[ValueWord::Null, ValueWord::Null],
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "get_step_away" => {
            return Some(BuiltinSpec {
                opcode: 0x92,
                min_args: 2,
                max_args: 3,
                trailing_defaults: &[ValueWord::Null],
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "typesof" | "sorttextEx" => {
            return Some(BuiltinSpec {
                opcode: if name == "typesof" { 0xa7 } else { 0x73 },
                min_args: if name == "typesof" { 1 } else { 2 },
                max_args: usize::MAX,
                trailing_defaults: &[],
                count_operand: OpcodeCountPolicy::EmittedArgs,
                post_opcode: None,
            });
        }
        "findlasttext" | "findlasttextEx" => {
            return Some(BuiltinSpec {
                opcode: if name == "findlasttext" { 0x132 } else { 0x133 },
                min_args: 2,
                max_args: 4,
                trailing_defaults: &[ValueWord::Number(0), ValueWord::Number(0x3f80_0000)],
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "spantext" | "nonspantext" => {
            return Some(BuiltinSpec {
                opcode: if name == "spantext" { 0x134 } else { 0x135 },
                min_args: 2,
                max_args: 3,
                trailing_defaults: &[ValueWord::Number(0x3f80_0000)],
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "jointext" | "splittext" => {
            return Some(BuiltinSpec {
                opcode: if name == "jointext" { 0x137 } else { 0x136 },
                min_args: 2,
                max_args: if name == "jointext" { 4 } else { 5 },
                trailing_defaults: if name == "jointext" {
                    &[ValueWord::Number(0x3f80_0000), ValueWord::Null]
                } else {
                    &[
                        ValueWord::Number(0x3f80_0000),
                        ValueWord::Null,
                        ValueWord::Null,
                    ]
                },
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "url_encode" => {
            return Some(BuiltinSpec {
                opcode: 0x107,
                min_args: 1,
                max_args: 2,
                trailing_defaults: &[ValueWord::Null],
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "text2ascii" | "copytext_char" => {
            return Some(BuiltinSpec {
                opcode: if name == "text2ascii" { 0xdb } else { 0x14e },
                min_args: if name == "text2ascii" { 1 } else { 2 },
                max_args: if name == "text2ascii" { 2 } else { 3 },
                trailing_defaults: &[ValueWord::Null],
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "rgb2num" => {
            return Some(BuiltinSpec {
                opcode: 0x162,
                min_args: 1,
                max_args: 2,
                trailing_defaults: &[ValueWord::Number(0)],
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "findtextEx" => {
            return Some(BuiltinSpec {
                opcode: 0x70,
                min_args: 2,
                max_args: 4,
                trailing_defaults: &[ValueWord::Number(0x3f80_0000), ValueWord::Null],
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "replacetext" | "replacetextEx" => {
            return Some(BuiltinSpec {
                opcode: if name == "replacetext" { 0x130 } else { 0x131 },
                min_args: 3,
                max_args: 5,
                trailing_defaults: &[ValueWord::Number(0x3f80_0000), ValueWord::Null],
                count_operand: OpcodeCountPolicy::None,
                post_opcode: None,
            });
        }
        "sorttext" => {
            return Some(BuiltinSpec {
                opcode: 0x72,
                min_args: 2,
                max_args: usize::MAX,
                trailing_defaults: &[],
                count_operand: OpcodeCountPolicy::EmittedArgs,
                post_opcode: None,
            });
        }
        _ => return None,
    };
    Some(fixed(opcode, args))
}

#[cfg(test)]
mod tests {
    use super::*;
    use byond_dmb::{bytecode, dmb::Dmb};

    const NATIVE: &[u8] =
        include_bytes!("../../../fixtures/native_compiler/builtin_catalog.native.bin");

    #[test]
    fn missing_builtin_signatures_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/builtin_missing.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/builtin_missing.dm"
        ));
        assert!(ast.diagnostics.is_empty());
        let parameters = ["A", "B", "C", "D", "E", "F"].map(String::from).to_vec();
        for item in &ast.items {
            let path = item.header.split('(').next().unwrap();
            let tail = path.strip_prefix("/proc/probe_").unwrap();
            let (name, arity) = tail.rsplit_once('_').unwrap();
            let spec = lookup_with_arity(name, arity.parse().unwrap()).unwrap();
            let compiled =
                crate::compile_simple_proc_with_params(&item.children, &parameters).unwrap();
            let linked = crate::link_proc(&compiled.code, &crate::Ledger::default()).unwrap();
            let actual = bytecode::decode(&linked.words).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let expected = bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
            let prefix = |code: Vec<byond_dmb::bytecode::Instruction>| {
                let at = code
                    .iter()
                    .position(|instruction| instruction.opcode == spec.opcode)
                    .unwrap();
                let end = at + 1 + usize::from(spec.post_opcode.is_some());
                code[..end]
                    .iter()
                    .map(|instruction| (instruction.opcode, instruction.operands.clone()))
                    .collect::<Vec<_>>()
            };
            assert_eq!(prefix(actual), prefix(expected), "{path}");
        }
    }

    #[test]
    fn additional_builtin_signatures_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/builtin_additional.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/builtin_additional.dm"
        ));
        assert!(ast.diagnostics.is_empty());
        let parameters = ["A", "B", "C", "D", "E", "F"].map(String::from).to_vec();
        for item in &ast.items {
            let path = item.header.split('(').next().unwrap();
            let tail = path.strip_prefix("/proc/probe_").unwrap();
            let (name, arity) = tail.rsplit_once('_').unwrap();
            if name == "gradient" {
                continue;
            }
            let spec = lookup_with_arity(name, arity.parse().unwrap()).unwrap();
            let compiled =
                crate::compile_simple_proc_with_params(&item.children, &parameters).unwrap();
            let linked = crate::link_proc(&compiled.code, &crate::Ledger::default()).unwrap();
            let actual = bytecode::decode(&linked.words).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let expected = bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
            let prefix = |code: Vec<byond_dmb::bytecode::Instruction>| {
                let at = code
                    .iter()
                    .position(|instruction| instruction.opcode == spec.opcode)
                    .unwrap();
                let end = at + 1 + usize::from(spec.post_opcode.is_some());
                code[..end]
                    .iter()
                    .map(|instruction| (instruction.opcode, instruction.operands.clone()))
                    .collect::<Vec<_>>()
            };
            assert_eq!(prefix(actual), prefix(expected), "{path}");
        }
    }

    #[test]
    fn catalog_matches_native_dreammaker_procs() {
        let dmb = Dmb::from_bytes(NATIVE).unwrap();
        let names = [
            "abs",
            "sin",
            "cos",
            "tan",
            "arcsin",
            "arccos",
            "arctan",
            "sqrt",
            "log",
            "round",
            "floor",
            "ceil",
            "length",
            "length_char",
            "lowertext",
            "uppertext",
            "num2text",
            "text2num",
            "isnull",
            "isnum",
            "istext",
            "islist",
            "ispath",
            "isfile",
            "isicon",
            "isloc",
            "ismob",
            "isobj",
            "isarea",
            "isturf",
            "get_dir",
            "get_dist",
            "get_step",
            "get_step_towards",
            "get_step_rand",
            "get_step_away",
            "turn",
            "locate",
            "hascall",
            "fcopy",
            "fdel",
            "fexists",
            "file2text",
            "text2file",
            "flist",
            "fcopy_rsc",
            "text2path",
            "params2list",
            "list2params",
            "typesof",
            "sorttextEx",
            "findlasttext",
            "findlasttextEx",
            "spantext",
            "nonspantext",
            "jointext",
            "splittext",
            "prob",
            "md5",
            "sha1",
            "json_encode",
            "json_decode",
            "html_encode",
            "html_decode",
            "url_encode",
            "url_decode",
            "ckey",
            "ckeyEx",
            "sorttext",
            "ascii2text",
            "text2ascii",
            "copytext_char",
            "findtextEx",
            "rgb",
            "matrix",
            "time2text",
            "rgb2num",
            "replacetext",
            "replacetextEx",
        ];
        for name in names {
            let spec = lookup(name).unwrap();
            let path = format!("/proc/catalog_{name}");
            let (index, _) = dmb
                .procs
                .iter()
                .enumerate()
                .find(|(_, proc)| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap_or_else(|| panic!("missing native fixture for {name}"));
            let code = bytecode::decode(dmb.proc_code_words(index).unwrap()).unwrap();
            let instruction = code
                .iter()
                .find(|instruction| instruction.opcode == spec.opcode)
                .unwrap_or_else(|| panic!("wrong opcode for {name}: {code:?}"));
            let expected_operands = match spec.count_operand {
                OpcodeCountPolicy::None => vec![],
                OpcodeCountPolicy::EmittedArgs => vec![spec.min_args as u32],
                OpcodeCountPolicy::Fixed(value) => vec![value],
            };
            assert_eq!(instruction.operands, expected_operands, "{name}");
            if let Some(post) = spec.post_opcode {
                let position = code
                    .iter()
                    .position(|instruction| instruction.opcode == spec.opcode)
                    .unwrap();
                assert_eq!(
                    code.get(position + 1).map(|instruction| instruction.opcode),
                    Some(post),
                    "{name}"
                );
            }
        }
    }

    #[test]
    fn optional_null_and_count_operand_match_native_stack() {
        let dmb = Dmb::from_bytes(NATIVE).unwrap();
        let proc_code = |name: &str| {
            let path = format!("/proc/catalog_{name}");
            let (index, _) = dmb
                .procs
                .iter()
                .enumerate()
                .find(|(_, proc)| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            bytecode::decode(dmb.proc_code_words(index).unwrap()).unwrap()
        };
        let one = proc_code("url_encode");
        let two = proc_code("url_encode2");
        assert!(one
            .iter()
            .any(|instruction| { instruction.opcode == 0x60 && instruction.operands == [0, 0] }));
        assert!(!two.iter().any(|instruction| instruction.opcode == 0x60));
        let three = proc_code("sorttext3");
        assert!(three
            .iter()
            .any(|instruction| { instruction.opcode == 0x72 && instruction.operands == [3] }));
        let opcodes = |name| {
            proc_code(name)
                .iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>()
        };
        assert_eq!(&opcodes("text2ascii")[..3], &[0x33, 0x60, 0xdb]);
        assert_eq!(&opcodes("copytext_char")[..4], &[0x33, 0x33, 0x60, 0x14e]);
        assert_eq!(&opcodes("findtextEx")[..5], &[0x33, 0x33, 0x50, 0x60, 0x70]);
        assert_eq!(&opcodes("rgb2num")[..3], &[0x33, 0x50, 0x162]);
        assert_eq!(
            &opcodes("replacetext")[..6],
            &[0x33, 0x33, 0x33, 0x50, 0x60, 0x130]
        );
        assert_eq!(
            &opcodes("replacetext4")[..6],
            &[0x33, 0x33, 0x33, 0x33, 0x60, 0x130]
        );
        assert_eq!(
            &opcodes("replacetext5")[..6],
            &[0x33, 0x33, 0x33, 0x33, 0x33, 0x130]
        );
        assert_eq!(
            lookup("url_encode").unwrap().trailing_defaults,
            &[ValueWord::Null]
        );
        assert!(opcodes("locate1").contains(&0x5b));
        assert!(opcodes("locate2").contains(&0x97));
        assert_eq!(&opcodes("get_step_away")[..4], &[0x33, 0x33, 0x60, 0x92]);
        assert_eq!(&opcodes("get_step_away3")[..4], &[0x33, 0x33, 0x33, 0x92]);
        assert!(lookup("exp").is_none());
    }

    #[test]
    fn named_image_and_animate_use_associative_argument_lists() {
        let native = Dmb::from_bytes(NATIVE).unwrap();
        for (name, count, call_opcode) in [
            ("image_named", 3, 0xd3),
            ("image_mixed", 2, 0xd3),
            ("animate_named", 3, 0x128),
        ] {
            let path = format!("/proc/catalog_{name}");
            let index = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let code = bytecode::decode(native.proc_code_words(index).unwrap()).unwrap();
            let assoc = code
                .iter()
                .position(|instruction| instruction.opcode == 0xc8)
                .unwrap();
            assert_eq!(code[assoc].operands, [count], "{name}");
            assert_eq!(code[assoc + 1].opcode, call_opcode, "{name}");
        }
        for (name, opcode, operands) in [
            ("image_one", 0xd4, vec![1]),
            ("animate_one", 0x129, vec![]),
            ("animate_two", 0x129, vec![]),
        ] {
            let path = format!("/proc/catalog_{name}");
            let index = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let code = bytecode::decode(native.proc_code_words(index).unwrap()).unwrap();
            let call = code
                .iter()
                .find(|instruction| instruction.opcode == opcode)
                .unwrap();
            assert_eq!(call.operands, operands, "{name}");
            if name == "animate_two" {
                assert_eq!(code[0].opcode, 0x33);
                assert_eq!(code[1].opcode, 0x129);
            }
        }
    }

    #[test]
    fn matrix_and_time2text_optional_forms_match_native_bodies() {
        let native = Dmb::from_bytes(NATIVE).unwrap();
        for (name, expression, parameters) in [
            (
                "matrix6",
                "matrix(a,b,c,d,e,f)",
                vec!["a", "b", "c", "d", "e", "f"],
            ),
            ("time2text1", "time2text(a)", vec!["a"]),
            ("time2text2", "time2text(a,b)", vec!["a", "b"]),
        ] {
            let path = format!("/proc/catalog_{name}");
            let source = format!(
                "{path}({})\n    return {expression}\n",
                parameters.join(",")
            );
            let ast = dm_syntax::parse(&source);
            assert!(ast.diagnostics.is_empty());
            let parameters = parameters.into_iter().map(String::from).collect::<Vec<_>>();
            let compiled =
                crate::compile_simple_proc_with_params(&ast.items[0].children, &parameters)
                    .unwrap();
            let linked = crate::link_proc(&compiled.code, &crate::Ledger::default()).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn generator_and_alist_native_special_forms() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/generator_alist.native.bin"
        ))
        .unwrap();
        let code = |name: &str| {
            let path = format!("/proc/probe_{name}");
            let index = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            bytecode::decode(native.proc_code_words(index).unwrap()).unwrap()
        };
        for (name, arity) in [
            ("generator_num", 3),
            ("generator_four", 4),
            ("generator_vector", 3),
        ] {
            let instructions = code(name);
            assert_eq!(instructions[0].opcode, 0x60);
            assert_eq!(instructions[0].operands[0], 6);
            assert_eq!(
                native.string(instructions[0].operands[1]),
                Some(b"/generator".as_slice())
            );
            assert!(instructions
                .iter()
                .any(|instruction| instruction.opcode == 1 && instruction.operands == [arity]));
        }
        let named = code("generator_named");
        let assoc = named
            .iter()
            .position(|instruction| instruction.opcode == 0xc8)
            .unwrap();
        assert_eq!(named[assoc].operands, [3]);
        assert_eq!(named[assoc + 1].opcode, 0xcf);
        assert!(code("alist_pairs")
            .iter()
            .any(|instruction| instruction.opcode == 0x17c && instruction.operands == [2]));
        assert!(code("alist_empty")
            .iter()
            .any(|instruction| instruction.opcode == 0x17c && instruction.operands == [0]));
    }

    #[test]
    fn view_catalog_forms_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/view_orange.native.bin"
        ))
        .unwrap();
        let spec = lookup("view").unwrap();
        assert_eq!((spec.opcode, spec.min_args, spec.max_args), (0x1b, 0, 2));
        assert_eq!(spec.trailing_defaults, &[ValueWord::Null, ValueWord::Null]);
        for (name, expression, parameters) in [
            ("zero", "view()", vec![]),
            ("one", "view(6)", vec![]),
            ("two", "view(6, A)", vec!["A"]),
        ] {
            let path = format!("/proc/probe_view_{name}");
            let source = format!(
                "{path}({})\n    return {expression}\n",
                parameters.join(",")
            );
            let ast = dm_syntax::parse(&source);
            assert!(ast.diagnostics.is_empty());
            let parameters = parameters.into_iter().map(String::from).collect::<Vec<_>>();
            let compiled =
                crate::compile_simple_proc_with_params(&ast.items[0].children, &parameters)
                    .unwrap();
            let linked = crate::link_proc(&compiled.code, &crate::Ledger::default()).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn orange_special_operand_and_turf_membership_match_native() {
        let native = Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/view_orange.native.bin"
        ))
        .unwrap();
        for name in ["zero", "one", "two"] {
            let path = format!("/proc/probe_orange_{name}");
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let code = bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
            let orange = code
                .iter()
                .find(|instruction| instruction.name == "ORange")
                .unwrap();
            assert_eq!(orange.operands, [0xae]);
        }
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/probe_turf_in_orange"))
            .unwrap();
        let code = bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        assert_eq!(
            code.iter()
                .map(|instruction| instruction.name)
                .collect::<Vec<_>>(),
            ["PushInt", "PushVal", "ORange", "PushVal", "IsIn", "GetFlag", "Pick", "Ret", "End"]
        );
        assert_eq!(code[4].operands, [5]);
    }
}
