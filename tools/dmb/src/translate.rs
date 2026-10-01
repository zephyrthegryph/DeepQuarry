//! End-to-end OpenDream JSON to BYOND v516 DMB/RSC translation.
//!
//! The lowering is intentionally strict: a procedure that uses an unsupported
//! OpenDream operation fails with its name and byte offset. A syntactically
//! valid DMB with guessed bytecode would be harder to diagnose at runtime.

use crate::dmb::Dmb;
use crate::od_emit::{self, Emission};
use crate::od_lower::{self, SymbolResolver};
use crate::opendream::OpenDreamProgram;
use std::fmt;
use std::path::Path;

#[derive(Debug)]
pub enum TranslateError {
    Emit(od_emit::EmitError),
    Proc {
        name: String,
        offset: usize,
        reason: String,
    },
    Invalid(String),
    Io(std::io::Error),
}

impl fmt::Display for TranslateError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Emit(error) => error.fmt(f),
            Self::Proc {
                name,
                offset,
                reason,
            } => {
                write!(
                    f,
                    "cannot lower {name} at OpenDream byte {offset}: {reason}"
                )
            }
            Self::Invalid(reason) => reason.fmt(f),
            Self::Io(error) => error.fmt(f),
        }
    }
}

impl std::error::Error for TranslateError {}

impl From<od_emit::EmitError> for TranslateError {
    fn from(value: od_emit::EmitError) -> Self {
        Self::Emit(value)
    }
}

impl From<std::io::Error> for TranslateError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

struct Resolver<'a> {
    program: &'a OpenDreamProgram,
    ids: &'a od_emit::EmissionIds,
    mob_ids_by_class: std::collections::HashMap<u32, u32>,
    native_sound_string: Option<u32>,
    native_icon_string: Option<u32>,
    native_generator_string: Option<u32>,
    current_owner: std::cell::Cell<usize>,
    current_proc: std::cell::Cell<usize>,
}

impl Resolver<'_> {
    fn verb_in_owner(&self, mut owner: usize, name: &str) -> bool {
        let mut seen = std::collections::HashSet::new();
        while seen.insert(owner) {
            let Some(typ) = self.program.types.get(owner) else {
                return false;
            };
            if typ.procs.iter().flatten().any(|&id| {
                self.program
                    .procs
                    .get(id)
                    .is_some_and(|proc_| proc_.name == name && proc_.is_verb)
            }) {
                return true;
            }
            let Some(parent) = typ.parent else {
                return false;
            };
            owner = parent;
        }
        false
    }
}

impl SymbolResolver for Resolver<'_> {
    fn method_call_is_verb(&self, old_proc: u32) -> bool {
        self.program
            .procs
            .get(old_proc as usize)
            .is_some_and(|proc_| {
                proc_.is_verb || self.verb_in_owner(proc_.owning_type_id, &proc_.name)
            })
    }
    fn self_call_is_verb(&self, old_field: u32) -> bool {
        self.program
            .strings
            .get(old_field as usize)
            .is_some_and(|name| self.verb_in_owner(self.current_owner.get(), name))
    }
    fn native_constant_global(&self, old: u32) -> bool {
        self.program
            .globals
            .as_ref()
            .is_some_and(|globals| globals.const_global_ids.contains(&(old as usize)))
    }
    fn native_initial_reference_offsets(&self) -> &[usize] {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        proc_.map_or(&[], |proc_| {
            proc_.native_initial_reference_offsets.as_slice()
        })
    }
    fn native_do_while_condition(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        proc_.is_some_and(|proc_| proc_.native_do_while_condition_offsets.contains(&offset))
    }
    fn native_is_saved_reference_offsets(&self) -> &[usize] {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        proc_.map_or(&[], |proc_| {
            proc_.native_is_saved_reference_offsets.as_slice()
        })
    }
    fn native_is_saved_reference(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        proc_.is_some_and(|proc_| proc_.native_is_saved_reference_offsets.contains(&offset))
    }
    fn native_initial_reference(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        proc_.is_some_and(|proc_| proc_.native_initial_reference_offsets.contains(&offset))
    }
    fn native_delete_clear(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        u32::try_from(offset).ok().is_some_and(|offset| {
            proc_.is_some_and(|proc_| proc_.native_delete_clear_offsets.contains(&offset))
        })
    }
    fn native_store_reload_offsets(&self) -> &[u32] {
        if self.current_proc.get() == usize::MAX {
            self.program
                .global_init_proc
                .as_ref()
                .map_or(&[], |proc_| proc_.native_store_reload_offsets.as_slice())
        } else {
            self.program
                .procs
                .get(self.current_proc.get())
                .map_or(&[], |proc_| proc_.native_store_reload_offsets.as_slice())
        }
    }
    fn native_store_reload(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        u32::try_from(offset).ok().is_some_and(|offset| {
            proc_.is_some_and(|proc_| proc_.native_store_reload_offsets.contains(&offset))
        })
    }
    fn native_try_continue(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        u32::try_from(offset).ok().is_some_and(|offset| {
            proc_.is_some_and(|proc_| proc_.native_try_continue_offsets.contains(&offset))
        })
    }
    fn native_try_goto(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        u32::try_from(offset).ok().is_some_and(|offset| {
            proc_.is_some_and(|proc_| proc_.native_try_goto_offsets.contains(&offset))
        })
    }
    fn native_goto(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        u32::try_from(offset).ok().is_some_and(|offset| {
            proc_.is_some_and(|proc_| proc_.native_goto_offsets.contains(&offset))
        })
    }
    fn native_continue(&self, offset: usize) -> Option<bool> {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        let offsets = proc_?.native_continue_offsets.as_ref()?;
        Some(
            u32::try_from(offset)
                .ok()
                .is_some_and(|offset| offsets.contains(&offset)),
        )
    }
    fn native_try_break(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        u32::try_from(offset).ok().is_some_and(|offset| {
            proc_.is_some_and(|proc_| proc_.native_try_break_offsets.contains(&offset))
        })
    }
    fn native_delete_src(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        u32::try_from(offset).ok().is_some_and(|offset| {
            proc_.is_some_and(|proc_| proc_.native_delete_src_offsets.contains(&offset))
        })
    }
    fn native_null(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        proc_.is_some_and(|proc_| proc_.native_null_offsets.contains(&offset))
    }
    fn implicit_locate(&self, offset: usize) -> bool {
        let proc_ = if self.current_proc.get() == usize::MAX {
            self.program.global_init_proc.as_ref()
        } else {
            self.program.procs.get(self.current_proc.get())
        };
        proc_.is_some_and(|proc_| proc_.implicit_locate_offsets.contains(&offset))
    }
    fn string(&self, old: u32) -> Option<u32> {
        self.ids.strings.get(old as usize).copied()
    }
    fn method_call_name(&self, old_proc: u32, old_field: u32) -> Option<u32> {
        if old_proc == u32::MAX {
            self.string(old_field)
        } else {
            self.ids.method_call_names.get(old_proc as usize).copied()
        }
    }
    fn self_call_name(&self, old_field: u32) -> Option<u32> {
        let name = self.program.strings.get(old_field as usize)?;
        let mut owner = Some(self.current_owner.get());
        let mut seen = std::collections::HashSet::new();
        while let Some(id) = owner {
            if !seen.insert(id) {
                return None;
            }
            let typ = self.program.types.get(id)?;
            if let Some(proc_id) = typ
                .procs
                .iter()
                .rev()
                .flat_map(|chain| chain.iter().rev())
                .find(|&&proc_id| {
                    self.program
                        .procs
                        .get(proc_id)
                        .is_some_and(|proc| proc.name == *name)
                })
            {
                return self.ids.method_call_names.get(*proc_id).copied();
            }
            owner = typ.parent;
        }
        self.string(old_field)
    }
    fn type_id(&self, old: u32) -> Option<u32> {
        let tag = self.program.native_type_tag(old as usize)?;
        if matches!(tag, 36 | 39 | 40 | 59) {
            return Some(0);
        }
        let class_id = self
            .ids
            .classes
            .get(old as usize)
            .copied()
            .filter(|id| *id != 0xffff)?;
        if tag == 8 {
            self.mob_ids_by_class.get(&class_id).copied()
        } else {
            Some(class_id)
        }
    }
    fn world_iterator_mask(&self, tag: u8, native_id: u32) -> Option<(u32, bool)> {
        let old = self.program.types.iter().enumerate().find_map(|(old, _)| {
            let old = u32::try_from(old).ok()?;
            (self.type_tag(old) == Some(tag) && self.type_id(old) == Some(native_id)).then_some(old)
        })?;
        let mask = self.iterator_type_mask(old)?;
        Some((mask, self.iterator_root_mask(old) == Some(mask)))
    }
    fn iterator_type_mask(&self, old: u32) -> Option<u32> {
        let id = old as usize;
        self.program.types.get(id)?;
        for (path, mask) in [
            ("/mob", 1),
            ("/obj", 2),
            ("/atom/movable", 3),
            ("/turf", 32),
            ("/area", 256),
            ("/atom", 291),
        ] {
            if self.program.type_inherits_path(id, path) {
                return Some(mask);
            }
        }
        Some(0)
    }
    fn iterator_root_mask(&self, old: u32) -> Option<u32> {
        match self.program.types.get(old as usize)?.path.as_str() {
            "/mob" => Some(1),
            "/turf" => Some(32),
            "/area" => Some(256),
            _ => None,
        }
    }
    fn proc_id(&self, old: u32) -> Option<u32> {
        self.ids
            .procs
            .get(old as usize)
            .copied()
            .filter(|id| *id != 0xffff)
    }
    fn modified_instance(&self, old_type: u32, old_string: u32) -> Option<u32> {
        let overrides = self.program.strings.get(old_string as usize)?;
        self.ids
            .modified_instances
            .get(&(old_type as usize, overrides.clone()))
            .copied()
    }
    fn builtin_proc(&self, old: u32) -> Option<u32> {
        match self.program.procs.get(old as usize)?.name.as_str() {
            "_dm_db_new_con" => Some(0xe9),
            "_dm_db_new_query" => Some(0xea),
            "isfile" => Some(0xe4),
            "isnum" => Some(0x9f),
            "round" => Some(0x43),
            "floor" => Some(0x43),
            "ceil" => Some(0x169),
            "rand" => Some(0x22),
            "clamp" => Some(0x14a),
            "min" => Some(0xa5),
            "max" => Some(0xa6),
            "fexists" => Some(0xf7),
            "istext" => Some(0xa0),
            "islist" => Some(0x147),
            "hascall" => Some(0xbc),
            "jointext" => Some(0x137),
            "isicon" => Some(0x28),
            "isloc" => Some(0x13),
            "shell" => Some(0x98),
            "ref" => Some(0x148),
            "run" => Some(0x09),
            "load_ext" => Some(0x179),
            "walk_away" => Some(0x125),
            "ismob" => Some(0x14),
            "isobj" => Some(0x15),
            "isturf" => Some(0x17),
            "copytext" => Some(0x6e),
            "copytext_char" => Some(0x14e),
            "time2text" => Some(0xc0),
            "num2text" => Some(0x159),
            "winset" => Some(0x10c),
            "winshow" => Some(0x10f),
            "winexists" => Some(0x118),
            "winclone" => Some(0x10e),
            "sha1" => Some(0x14b),
            "splicetext_char" => Some(0x160),
            "url_decode" => Some(0x108),
            "walk_rand" => Some(0x127),
            "roll" => Some(0x57),
            "ckeyEx" => Some(0xb9),
            "get_step_rand" => Some(0x94),
            "rand_seed" => Some(0xda),
            "winget" => Some(0x10d),
            "ispath" => Some(0xf5),
            "typesof" => Some(0xa7),
            "sorttext" => Some(0x72),
            "sorttextEx" => Some(0x73),
            "isnan" => Some(0x16c),
            "isinf" => Some(0x16d),
            "html_encode" => Some(0xbe),
            "sound" => Some(0x170),
            "matrix" => Some(0x12a),
            "icon" => Some(0x171),
            "image" => Some(0x173),
            "icon_states" => Some(0x114),
            "rgb2num" => Some(0x162),
            "splittext" => Some(0x136),
            "replacetext" => Some(0x130),
            "replacetextEx" => Some(0x131),
            "get_dist" => Some(0x95),
            "flist" => Some(0xac),
            "findtext" => Some(0x6f),
            "findtextEx" => Some(0x70),
            "findtext_char" => Some(0x14f),
            "trimtext" => Some(0x16e),
            "splittext_char" => Some(0x157),
            "refcount" => Some(0x178),
            "file" => Some(0x172),
            "file2text" => Some(0x9a),
            "text2file" => Some(0x99),
            "flick" => Some(0x5c),
            "turn" => Some(0x6b),
            "step" => Some(0x86),
            "step_towards" => Some(0x89),
            "step_away" => Some(0x88),
            "step_to" => Some(0x87),
            "get_step_away" => Some(0x92),
            "get_step_towards" => Some(0x93),
            "get_step_to" => Some(0x91),
            "step_rand" => Some(0x8a),
            "walk" => Some(0x8b),
            "walk_to" => Some(0x8c),
            "walk_towards" => Some(0x8e),
            "hearers" => Some(0xe7),
            "ohearers" => Some(0xe8),
            "ismovable" => Some(0x149),
            "text2path" => Some(0x10a),
            "html_decode" => Some(0xbf),
            "ckey" => Some(0xa8),
            "cmptext" => Some(0x71),
            "cmptextEx" => Some(0x37),
            "spantext" => Some(0x134),
            "nonspantext" => Some(0x135),
            "spantext_char" => Some(0x155),
            "nonspantext_char" => Some(0x156),
            "splicetext" => Some(0x15f),
            "trunc" => Some(0x16a),
            "fract" => Some(0x16b),
            "text2ascii_char" => Some(0x14c),
            "length_char" => Some(0x14d),
            "findlasttext" => Some(0x132),
            "list2params" => Some(0xb7),
            "url_encode" => Some(0x107),
            "md5" => Some(0x109),
            "fcopy" => Some(0x9b),
            "fcopy_rsc" => Some(0xd7),
            "fdel" => Some(0xb4),
            "filter" => Some(0x13b),
            "regex" => Some(0x13a),
            "params2list" => Some(0xb8),
            "isarea" => Some(0x16),
            "lowertext" => Some(0x75),
            "uppertext" => Some(0x74),
            "view" => Some(0x1b),
            "viewers" => Some(0xe5),
            "oview" => Some(0x1c),
            "orange" => Some(0x1000e), // native iterator mode 14
            "oviewers" => Some(0xe6),
            "range" => Some(0x59),
            "block" => Some(0x1f),
            "text2num" => Some(0x76),
            "text2ascii" => Some(0xdb),
            "ascii2text" => Some(0xdc),
            "json_decode" => Some(0x139),
            "json_encode" => Some(0x138),
            "CRASH" => Some(0xc7),
            "sleep" => Some(0x24),
            "alert" => Some(0x18),
            "generator" => Some(0x10001),
            "sign" => Some(0x186),
            "lerp" => Some(0x187),
            "values_sum" => Some(0x188),
            "values_product" => Some(0x189),
            "values_dot" => Some(0x18a),
            "values_cut_under" => Some(0x18b),
            "values_cut_over" => Some(0x18c),
            "vector" => Some(0x180),
            "pixloc" => Some(0x17f),
            "bound_pixloc" => Some(0x181),
            _ => None,
        }
    }
    fn sound_type_string(&self) -> Option<u32> {
        self.native_sound_string
    }
    fn icon_type_string(&self) -> Option<u32> {
        self.native_icon_string
    }
    fn generator_type_string(&self) -> Option<u32> {
        self.native_generator_string
    }
    fn resource(&self, old: u32) -> Option<u32> {
        let path = self.program.strings.get(old as usize)?;
        let index = self
            .program
            .resources
            .iter()
            .position(|resource| resource == path)?;
        self.ids.resources.get(index).copied()
    }
    fn global_vars_variable(&self) -> Option<u32> {
        self.ids.global_vars
    }
    fn global(&self, old: u32) -> Option<u32> {
        self.ids.globals.get(old as usize).copied()
    }
    fn type_tag(&self, old: u32) -> Option<u8> {
        self.program.native_type_tag(old as usize)
    }
}

/// One independently audited procedure that cannot yet be lowered.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LowerAuditIssue {
    pub od_proc_id: usize,
    pub name: String,
    pub offset: usize,
    pub reason: String,
}

/// Attempt every OpenDream procedure independently against an already emitted
/// symbol table. This does not mutate the emission, so one unsupported proc
/// does not hide the rest of the bytecode backlog.
pub fn audit_lowering(input: &OpenDreamProgram, emission: &Emission) -> Vec<LowerAuditIssue> {
    audit_lowering_with_debug(input, emission, false)
}

/// Audit the same source-marker mode that will be used when writing output.
pub fn audit_lowering_with_debug(
    input: &OpenDreamProgram,
    emission: &Emission,
    debug_lines: bool,
) -> Vec<LowerAuditIssue> {
    let resolver = Resolver {
        current_owner: std::cell::Cell::new(0),
        current_proc: std::cell::Cell::new(usize::MAX),
        program: input,
        ids: &emission.ids,
        mob_ids_by_class: emission
            .dmb
            .mobs
            .iter()
            .enumerate()
            .map(|(id, mob)| (mob.class, id as u32))
            .collect(),
        native_sound_string: emission
            .dmb
            .strings
            .iter()
            .position(|value| value.data == b"/sound")
            .map(|index| index as u32),
        native_icon_string: emission
            .dmb
            .strings
            .iter()
            .position(|value| value.data == b"/icon")
            .map(|index| index as u32),
        native_generator_string: emission
            .dmb
            .strings
            .iter()
            .position(|value| value.data == b"/generator")
            .map(|index| index as u32),
    };
    let mut issues = Vec::new();
    for (od_proc_id, proc) in input.procs.iter().enumerate() {
        resolver.current_proc.set(od_proc_id);
        resolver.current_owner.set(proc.owning_type_id);
        if emission.ids.procs.get(od_proc_id) == Some(&0xffff) {
            continue;
        }
        let Some(code) = proc.bytecode.as_deref() else {
            continue;
        };
        let lowered = if proc.name == "<init>"
            && !emission.ids.argument_source_procs.contains(&od_proc_id)
        {
            od_lower::lower_init_bytecode(code, &resolver)
        } else {
            let native_omit: Vec<_> = proc.arguments.iter().map(|arg| arg.native_omit).collect();
            od_lower::lower_proc_bytecode_with_native_layout(
                code,
                &resolver,
                proc.max_variable_id,
                &proc.locals,
                &proc.lexical_local_add_indices,
                &native_omit,
                debug_lines.then_some(proc.source_info.as_slice()),
            )
        };
        let result = lowered.and_then(|words| {
            crate::bytecode::decode(&words)
                .map(|_| ())
                .map_err(|error| od_lower::LowerError {
                    offset: error.offset,
                    kind: od_lower::LowerErrorKind::MalformedControlFlow,
                    reason: error.reason,
                })
        });
        if let Err(error) = result {
            let reason = error
                .reason
                .strip_prefix("unresolved OpenDream proc ID ")
                .and_then(|id| id.parse::<usize>().ok())
                .and_then(|id| input.procs.get(id).map(|proc| proc.name.as_str()))
                .map(|name| format!("unresolved OpenDream proc `{name}`"))
                .unwrap_or(error.reason);
            issues.push(LowerAuditIssue {
                od_proc_id,
                name: proc.name.clone(),
                offset: error.offset,
                reason,
            });
        }
    }
    resolver.current_owner.set(0);
    resolver.current_proc.set(usize::MAX);
    if let Some(source) = input
        .global_init_proc
        .as_ref()
        .and_then(|proc| proc.bytecode.as_deref())
    {
        if let Err(error) = od_lower::lower_init_bytecode(source, &resolver) {
            issues.push(LowerAuditIssue {
                od_proc_id: usize::MAX,
                name: "<global_init>".into(),
                offset: error.offset,
                reason: error.reason,
            });
        }
    }
    issues
}

/// Translate a compiled OpenDream program using a same-version native BYOND
/// scaffold and OpenDream baseline. The scaffold is supplied explicitly so
/// the caller controls its provenance and BYOND version.
pub fn translate(
    input: &OpenDreamProgram,
    od_baseline: &OpenDreamProgram,
    native_template: &Dmb,
    resource_root: &Path,
) -> Result<Emission, TranslateError> {
    translate_named(input, od_baseline, native_template, resource_root, None)
}

/// Translate with the project name Dream Maker would use as the default world name.
pub fn translate_named(
    input: &OpenDreamProgram,
    od_baseline: &OpenDreamProgram,
    native_template: &Dmb,
    resource_root: &Path,
    project_name: Option<&str>,
) -> Result<Emission, TranslateError> {
    translate_named_debug(
        input,
        od_baseline,
        native_template,
        resource_root,
        project_name,
        false,
    )
}

/// Translate with optional Dream Maker source file/line bytecode markers.
pub fn translate_named_debug(
    input: &OpenDreamProgram,
    od_baseline: &OpenDreamProgram,
    native_template: &Dmb,
    resource_root: &Path,
    project_name: Option<&str>,
    debug_lines: bool,
) -> Result<Emission, TranslateError> {
    translate_named_mode(
        input,
        od_baseline,
        native_template,
        resource_root,
        project_name,
        debug_lines,
        false,
    )
}

/// Validate full translation without reading or packaging resource payloads.
/// The returned emission contains placeholder resource IDs and must never be
/// written as a runnable DMB/RSC pair.
pub fn translate_diagnostic(
    input: &OpenDreamProgram,
    od_baseline: &OpenDreamProgram,
    native_template: &Dmb,
    resource_root: &Path,
    project_name: Option<&str>,
) -> Result<Emission, TranslateError> {
    translate_named_mode(
        input,
        od_baseline,
        native_template,
        resource_root,
        project_name,
        false,
        true,
    )
}

fn translate_named_mode(
    input: &OpenDreamProgram,
    od_baseline: &OpenDreamProgram,
    native_template: &Dmb,
    resource_root: &Path,
    project_name: Option<&str>,
    debug_lines: bool,
    diagnostic: bool,
) -> Result<Emission, TranslateError> {
    let mut output = if diagnostic {
        od_emit::emit_diagnostic_with_baseline_named(
            input,
            Some(od_baseline),
            native_template,
            resource_root,
            project_name,
        )?
    } else {
        od_emit::emit_with_baseline_named(
            input,
            Some(od_baseline),
            native_template,
            resource_root,
            project_name,
        )?
    };
    if debug_lines {
        output.dmb.header.flags |= 0x0002_0000;
    }
    let resolver = Resolver {
        current_owner: std::cell::Cell::new(0),
        current_proc: std::cell::Cell::new(usize::MAX),
        program: input,
        ids: &output.ids,
        mob_ids_by_class: output
            .dmb
            .mobs
            .iter()
            .enumerate()
            .map(|(id, mob)| (mob.class, id as u32))
            .collect(),
        native_sound_string: output
            .dmb
            .strings
            .iter()
            .position(|value| value.data == b"/sound")
            .map(|index| index as u32),
        native_icon_string: output
            .dmb
            .strings
            .iter()
            .position(|value| value.data == b"/icon")
            .map(|index| index as u32),
        native_generator_string: output
            .dmb
            .strings
            .iter()
            .position(|value| value.data == b"/generator")
            .map(|index| index as u32),
    };
    for (od_id, proc) in input.procs.iter().enumerate() {
        resolver.current_proc.set(od_id);
        resolver.current_owner.set(proc.owning_type_id);
        let dmb_id = *output.ids.procs.get(od_id).ok_or_else(|| {
            TranslateError::Invalid(format!("missing mapping for OpenDream proc {od_id}"))
        })?;
        if dmb_id == 0xffff {
            continue;
        }
        let Some(code) = proc.bytecode.as_deref() else {
            continue;
        };
        let is_class_init =
            proc.name == "<init>" && !output.ids.argument_source_procs.contains(&od_id);
        let native_omit: Vec<_> = proc.arguments.iter().map(|arg| arg.native_omit).collect();
        let words = if is_class_init && debug_lines {
            od_lower::lower_class_init_bytecode_with_debug_info(code, &resolver, &proc.source_info)
        } else if is_class_init {
            od_lower::lower_init_bytecode(code, &resolver)
        } else {
            od_lower::lower_proc_bytecode_with_native_layout(
                code,
                &resolver,
                proc.max_variable_id,
                &proc.locals,
                &proc.lexical_local_add_indices,
                &native_omit,
                debug_lines.then_some(proc.source_info.as_slice()),
            )
        }
        .map_err(|error| TranslateError::Proc {
            name: proc.name.clone(),
            offset: error.offset,
            reason: error.reason,
        })?;
        crate::bytecode::decode(&words).map_err(|error| TranslateError::Proc {
            name: proc.name.clone(),
            offset: error.offset,
            reason: error.reason,
        })?;
        let list_id = append_code_list(&mut output.dmb, words);
        output.dmb.procs[dmb_id as usize].code_locals_args[0] = list_id;
    }
    if let (Some(source), Some(dmb_id)) = (&input.global_init_proc, output.ids.global_init_proc) {
        resolver.current_proc.set(usize::MAX);
        resolver.current_owner.set(source.owning_type_id);
        if let Some(code) = source.bytecode.as_deref() {
            let lowered = if debug_lines {
                od_lower::lower_global_init_bytecode_with_debug_info(
                    code,
                    &resolver,
                    &source.source_info,
                )
            } else {
                od_lower::lower_init_bytecode(code, &resolver)
            };
            let words = lowered.map_err(|error| TranslateError::Proc {
                name: "<global_init>".into(),
                offset: error.offset,
                reason: error.reason,
            })?;
            crate::bytecode::decode(&words).map_err(|error| TranslateError::Proc {
                name: "<global_init>".into(),
                offset: error.offset,
                reason: error.reason,
            })?;
            let list_id = append_code_list(&mut output.dmb, words);
            output.dmb.procs[dmb_id as usize].code_locals_args[0] = list_id;
        }
    }
    refresh_native_feature_flags(
        &mut output.dmb,
        input.native_graphics_access,
        input.native_cpu_access,
    )?;
    prune_unused_global_vars_proxy(&mut output)?;
    output.dmb.compact_lists()?;
    output.dmb.validate_references()?;
    Ok(output)
}

/// Compiler feature flags are derived from decoded native instructions, never
/// operand words which happen to equal an opcode.
fn refresh_native_feature_flags(
    dmb: &mut Dmb,
    native_graphics_access: bool,
    native_cpu_access: bool,
) -> Result<(), TranslateError> {
    let mut external_library = false;
    let mut filter = native_graphics_access;
    for index in 0..dmb.procs.len() {
        let Some(words) = dmb.proc_code_words(index) else {
            continue;
        };
        for instruction in crate::bytecode::decode(words).map_err(|error| {
            TranslateError::Invalid(format!(
                "native feature instruction {}: {}",
                error.offset, error.reason
            ))
        })? {
            external_library |= matches!(instruction.opcode, 0x116 | 0x117 | 0x179 | 0x17a | 0x17b);
            filter |= instruction.opcode == 0x13b;
        }
    }
    dmb.header.flags = (dmb.header.flags & !0x2000_0041)
        | if external_library { 0x2000_0000 } else { 0 }
        | if filter { 0 } else { 0x40 }
        | u32::from(native_cpu_access);
    Ok(())
}

fn prune_unused_global_vars_proxy(output: &mut od_emit::Emission) -> Result<(), TranslateError> {
    fn references(variable: &crate::operands::Variable, id: u32) -> bool {
        use crate::operands::Variable;
        match variable {
            Variable::Global(value) => *value == id,
            Variable::SetCache(lhs, rhs) => references(lhs, id) || references(rhs, id),
            Variable::Initial(value) | Variable::IsSaved(value) => references(value, id),
            _ => false,
        }
    }
    let Some(id) = output.ids.global_vars else {
        return Ok(());
    };
    for index in 0..output.dmb.procs.len() {
        let Some(words) = output.dmb.proc_code_words(index) else {
            continue;
        };
        for instruction in crate::bytecode::decode(words).map_err(|error| {
            TranslateError::Invalid(format!(
                "native instruction {}: {}",
                error.offset, error.reason
            ))
        })? {
            for operand in instruction.typed_operands().map_err(|error| {
                TranslateError::Invalid(format!(
                    "native instruction {}: {}",
                    error.offset, error.reason
                ))
            })? {
                if let crate::bytecode::Operand::Variable(value) = operand {
                    if references(&value, id) {
                        return Ok(());
                    }
                }
            }
        }
    }
    // Only the specifically allocated trailing record is eligible for pruning.
    if id as usize + 1 == output.dmb.variables.len()
        && output.dmb.variables[id as usize].kind == 82
        && output.dmb.variables[id as usize].value == 0
    {
        output.dmb.variables.pop();
        output.ids.global_vars = None;
    }
    Ok(())
}

fn append_code_list(dmb: &mut Dmb, words: Vec<u32>) -> u32 {
    if dmb.lists.len() == 0xffff {
        dmb.lists.push(Vec::new());
    }
    let id = dmb.lists.len() as u32;
    dmb.lists.push(words);
    if dmb.lists.len() > u16::MAX as usize {
        dmb.header.flags |= 0x4000_0000;
    }
    id
}

#[cfg(test)]
#[path = "translate_tests.rs"]
mod code_list_tests;
