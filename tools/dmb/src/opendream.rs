//! The JSON program emitted by OpenDream's DMCompiler.
//!
//! Field names and optionality follow the compiler's `DMCompiler/Json` types.
//! OpenDream omits default-valued fields while serializing; collections therefore
//! default to empty and scalar settings default to zero or false.

use serde::Deserialize;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::io::Read;
use std::path::Path;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamProgram {
    pub metadata: OpenDreamMetadata,
    pub strings: Vec<String>,
    #[serde(default)]
    pub resources: Vec<String>,
    /// Alternate source spellings for resolved resources, mapped to the
    /// canonical OpenDream resource path.
    #[serde(default)]
    pub resource_aliases: HashMap<String, String>,
    /// Physical Resource path -> ordered decoded source spellings for RSC names.
    #[serde(default)]
    pub resource_archive_names: HashMap<String, Vec<String>>,
    /// Native source-phase order of authored resource archive names. Presence,
    /// including an empty list, distinguishes the annotated compiler export.
    #[serde(default)]
    pub native_resource_archive_order: Option<Vec<String>>,
    #[serde(default)]
    pub global_procs: Vec<usize>,
    pub globals: Option<OpenDreamGlobals>,
    pub global_init_proc: Option<OpenDreamProc>,
    #[serde(default)]
    pub maps: Vec<OpenDreamMap>,
    pub interface: Option<String>,
    /// Authored DMS includes in native preload order, resolved Resource paths.
    #[serde(default)]
    pub native_client_script_files: Vec<String>,
    /// Last authored text world hub-password assignment; null overrides do not reset it.
    pub native_hub_password: Option<String>,
    /// Authored declaration or resolved reference to an intrinsic graphics field.
    #[serde(default)]
    pub native_graphics_access: bool,
    #[serde(default)]
    pub native_cpu_access: bool,
    #[serde(default)]
    pub native_client_settings: HashMap<String, f32>,
    pub types: Vec<OpenDreamType>,
    pub procs: Vec<OpenDreamProc>,
    #[serde(default)]
    pub optional_errors: HashMap<String, Value>,
}

impl OpenDreamProgram {
    pub fn type_inherits_path(&self, mut id: usize, path: &str) -> bool {
        for _ in 0..=self.types.len() {
            let Some(typ) = self.types.get(id) else {
                return false;
            };
            if typ.path == path {
                return true;
            }
            let Some(parent) = typ.parent else {
                return false;
            };
            id = parent;
        }
        false
    }

    /// Native value category follows actual parent_type ancestry, not the
    /// spelling of the declared path. Builtin roots retain their intrinsic kind.
    pub fn native_type_tag(&self, mut id: usize) -> Option<u8> {
        for _ in 0..=self.types.len() {
            let typ = self.types.get(id)?;
            let tag = match typ.path.as_str() {
                "/mob" => Some(8),
                "/obj" | "/atom/movable" => Some(9),
                "/atom" | "/turf" => Some(10),
                "/area" => Some(11),
                "/datum" | "/" => Some(32),
                "/savefile" => Some(36),
                "/file" => Some(39),
                "/list" => Some(40),
                "/client" => Some(59),
                "/image" | "/mutable_appearance" => Some(63),
                "/alist" | "/callee" | "/vector" => Some(89),
                _ => None,
            };
            if tag.is_some() {
                return tag;
            }
            let Some(parent) = typ.parent else {
                return Some(32);
            };
            id = parent;
        }
        None // Malformed cyclic parent chain.
    }

    pub fn from_reader<R: Read>(reader: R) -> Result<Self, serde_json::Error> {
        serde_json::from_reader(reader)
    }

    pub fn from_slice(bytes: &[u8]) -> Result<Self, serde_json::Error> {
        serde_json::from_slice(bytes)
    }

    pub fn from_path(path: impl AsRef<Path>) -> Result<Self, OpenDreamLoadError> {
        let file = std::fs::File::open(path)?;
        Ok(Self::from_reader(std::io::BufReader::new(file))?)
    }
}

#[derive(Debug)]
pub enum OpenDreamLoadError {
    Io(std::io::Error),
    Json(serde_json::Error),
}

impl std::fmt::Display for OpenDreamLoadError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => error.fmt(formatter),
            Self::Json(error) => error.fmt(formatter),
        }
    }
}

impl std::error::Error for OpenDreamLoadError {}

impl From<std::io::Error> for OpenDreamLoadError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}

impl From<serde_json::Error> for OpenDreamLoadError {
    fn from(error: serde_json::Error) -> Self {
        Self::Json(error)
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamMetadata {
    pub version: String,
    /// Native DEBUG mode keeps each initializer expression token distinct.
    /// This is independent of whether translated bytecode includes line markers.
    #[serde(default)]
    pub native_initializer_interning_mode: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamGlobals {
    #[serde(default)]
    pub native_initializer_identity_version: u32,
    #[serde(default)]
    pub native_initializer_identities: HashMap<usize, Value>,
    #[serde(default)]
    pub native_unidentified_initializer_ids: HashSet<usize>,
    /// Source constant global declarations, including proc-local readonly bindings.
    #[serde(default)]
    pub const_global_ids: HashSet<usize>,
    /// Global bindings which reuse a class constant declaration record.
    #[serde(default)]
    pub const_field_global_ids: HashSet<usize>,
    #[serde(default)]
    pub global_count: usize,
    pub names: Vec<String>,
    pub globals: HashMap<usize, Value>,
    #[serde(default)]
    pub dynamic_initializer_global_ids: HashSet<usize>,
    #[serde(default)]
    pub temporary_global_ids: HashSet<usize>,
    /// Original source declaration constants, keyed by global ID to preserve duplicate names.
    #[serde(default)]
    pub declaration_values: HashMap<usize, Value>,
    #[serde(default)]
    pub compile_time_const_declarations: Vec<OpenDreamCompileTimeConstDeclaration>,
    #[serde(default)]
    pub initializer_value_kinds: HashMap<usize, String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamCompileTimeConstDeclaration {
    #[serde(default)]
    pub proc_id: usize,
    pub name: String,
    #[serde(default)]
    pub value: Value,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamType {
    #[serde(default)]
    pub native_initializer_identity_version: u32,
    #[serde(default)]
    pub native_initializer_declaration_identities: HashMap<String, Value>,
    #[serde(default)]
    pub native_initializer_identities: HashMap<String, Value>,
    /// Ordered identity keys parallel to dynamic_initializer_assignments.
    /// Reopened same-field assignments have independently observable tokens.
    #[serde(default)]
    pub native_initializer_assignment_identities: Vec<Option<Value>>,
    #[serde(default)]
    pub native_unidentified_initializer_fields: HashSet<String>,
    pub path: String,
    /// Order in which this type declared variables before JSON dictionary
    /// serialization; DreamMaker uses this order for variable IDs.
    #[serde(default)]
    pub variable_declaration_order: Vec<String>,
    #[serde(default)]
    pub variable_override_order: Vec<String>,
    /// Original declared value before later same-type overrides replace it.
    #[serde(default)]
    pub variable_declaration_values: HashMap<String, Value>,
    /// Source-provenance for `/type{field = value}` constants in declarations.
    #[serde(default)]
    pub modified_type_declaration_values: HashMap<String, OpenDreamModifiedTypeValue>,
    /// Final source-provenance for modified type constants in class overrides.
    #[serde(default)]
    pub modified_type_override_values: HashMap<String, OpenDreamModifiedTypeValue>,
    /// Names of authored variable overrides, including values equal to the
    /// compiler's built-in defaults. Stock OpenDream JSON omits this metadata.
    #[serde(default)]
    pub explicit_type_fields: HashSet<String>,
    #[serde(default)]
    pub native_client_settings: HashMap<String, Value>,
    /// Authored instance fields whose final initializer constructs a list or
    /// object at runtime and needs Dream Maker's dynamic marker value.
    #[serde(default)]
    pub dynamic_initializer_fields: HashSet<String>,
    /// Declared runtime list/object values retained in Dream Maker's variable table.
    #[serde(default)]
    pub dynamic_declaration_fields: HashSet<String>,
    /// Authored runtime list/object initializer assignments in compiler order.
    #[serde(default)]
    pub dynamic_initializer_assignments: Vec<String>,
    /// Diagnostic expression names from the patched OpenDream exporter.
    #[serde(default)]
    pub initializer_value_kinds: HashMap<String, String>,
    /// Constant values for authored assignments that OpenDream still puts in
    /// an initializer proc because an inherited assignment was dynamic.
    #[serde(default)]
    pub constant_initializer_fields: HashMap<String, Value>,
    #[serde(default)]
    pub constant_initializer_assignments: Vec<String>,
    #[serde(default)]
    pub initializer_assignment_count: usize,
    /// An authored empty bracket declaration (`var/list/items[]`) can cause
    /// DreamMaker to retain an empty class initializer procedure.
    #[serde(default)]
    pub implicit_empty_init_proc: bool,
    /// Optional compatible compiler annotation preserving explicit `/world`
    /// assignments even when their values equal OpenDream defaults.
    #[serde(default)]
    pub explicit_world_fields: HashSet<String>,
    pub parent: Option<usize>,
    pub init_proc: Option<usize>,
    #[serde(default)]
    pub procs: Vec<Vec<usize>>,
    #[serde(default)]
    pub verbs: HashSet<String>,
    #[serde(default)]
    pub variables: HashMap<String, Value>,
    #[serde(default)]
    pub global_variables: HashMap<String, usize>,
    #[serde(default)]
    pub const_variables: HashSet<String>,
    #[serde(default)]
    pub tmp_variables: HashSet<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamModifiedTypeValue {
    pub type_path: String,
    #[serde(default)]
    pub overrides: HashMap<String, Value>,
    #[serde(default)]
    pub override_order: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamProc {
    #[serde(default)]
    pub owning_type_id: usize,
    pub name: String,
    #[serde(default)]
    pub attributes: u32,
    #[serde(default)]
    pub max_variable_id: usize,
    #[serde(default)]
    pub max_stack_size: usize,
    #[serde(default)]
    pub arguments: Vec<OpenDreamArgument>,
    #[serde(default)]
    pub locals: Vec<OpenDreamLocal>,
    /// Add-event ordinals from `Locals` in source lexical order. Const Add
    /// events are omitted because Dream Maker does not place them in proc.locals.
    #[serde(default)]
    pub lexical_local_add_indices: Vec<usize>,
    #[serde(default)]
    pub source_info: Vec<OpenDreamSourceInfo>,
    /// Optimized byte offsets of locate() with an implicit world container.
    #[serde(default)]
    pub implicit_locate_offsets: Vec<usize>,
    /// Optimized byte offsets of authored null literals using the native Null reader.
    #[serde(default)]
    pub native_null_offsets: Vec<usize>,
    /// Optimized reference loads requiring native Initial(Local/Arg) descriptors.
    #[serde(default)]
    pub native_initial_reference_offsets: Vec<usize>,
    /// Optimized reference loads requiring native IsSaved(Local/Arg/constant Global) descriptors.
    #[serde(default)]
    pub native_is_saved_reference_offsets: Vec<usize>,
    /// Optimized byte offsets of authored del(src), which native terminates with End.
    #[serde(default)]
    pub native_delete_src_offsets: Vec<u32>,
    /// Optimized AssignNoPush offsets clearing a mutable authored del() lvalue.
    #[serde(default)]
    pub native_delete_clear_offsets: Vec<u32>,
    /// Optimized Assign offsets originating from statement store plus read fusion.
    #[serde(default)]
    pub native_store_reload_offsets: Vec<u32>,
    /// Optimized authored continue/break Jump offsets inside a protected try body.
    #[serde(default)]
    pub native_try_continue_offsets: Vec<u32>,
    #[serde(default)]
    pub native_try_break_offsets: Vec<u32>,
    #[serde(default)]
    pub native_try_goto_offsets: Vec<u32>,
    /// Optimized offsets of all authored goto branches, including forward gotos.
    #[serde(default)]
    pub native_goto_offsets: Vec<u32>,
    /// Present for new exporter output, including empty arrays; absent is legacy.
    #[serde(default)]
    pub native_continue_offsets: Option<Vec<u32>>,
    /// Optimized conditional branches belonging to dynamic authored do/while tails.
    #[serde(default)]
    pub native_do_while_condition_offsets: Vec<usize>,
    /// C# `byte[]` is serialized as a base64 JSON string, not an integer array.
    #[serde(default, deserialize_with = "base64_bytecode")]
    pub bytecode: Option<Vec<u8>>,
    #[serde(default)]
    pub is_verb: bool,
    pub verb_src: Option<i32>,
    pub verb_range: Option<i32>,
    pub verb_name: Option<String>,
    pub verb_category: Option<String>,
    pub verb_desc: Option<String>,
    #[serde(default)]
    pub invisibility: i8,
    /// Optional OpenDream extension distinguishing `set invisibility = 0`
    /// from a proc with no invisibility setting.
    #[serde(default)]
    pub explicit_invisibility: bool,
    /// Authored `set` attributes, including explicit false/empty values that
    /// would otherwise be indistinguishable from an inherited default.
    #[serde(default)]
    pub explicit_verb_fields: HashSet<String>,
    /// Authored boolean values for `set` flags. Inherited OpenDream Attributes
    /// can retain a parent bit after an explicit reset, so the set alone is insufficient.
    #[serde(default)]
    pub explicit_verb_field_values: HashMap<String, bool>,
    #[serde(default)]
    pub explicit_verb_text_values: HashMap<String, Option<String>>,
    pub explicit_verb_source: Option<i32>,
    pub explicit_verb_range: Option<i32>,
    pub explicit_verb_source_was_in: Option<bool>,
    /// A nested block `set background` hoisted by Dream Maker into proc flags.
    #[serde(default)]
    pub nested_background: bool,
}

fn base64_bytecode<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<Vec<u8>>, D::Error> {
    let encoded = Option::<String>::deserialize(deserializer)?;
    encoded
        .map(|s| decode_base64(&s).map_err(serde::de::Error::custom))
        .transpose()
}

fn decode_base64(encoded: &str) -> Result<Vec<u8>, &'static str> {
    fn digit(byte: u8) -> Option<u8> {
        match byte {
            b'A'..=b'Z' => Some(byte - b'A'),
            b'a'..=b'z' => Some(byte - b'a' + 26),
            b'0'..=b'9' => Some(byte - b'0' + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    }

    if !encoded.len().is_multiple_of(4) {
        return Err("base64 bytecode length is not divisible by four");
    }
    let mut output = Vec::with_capacity(encoded.len() / 4 * 3);
    for (index, quad) in encoded.as_bytes().chunks_exact(4).enumerate() {
        let final_quad = index == encoded.len() / 4 - 1;
        let a = digit(quad[0]).ok_or("invalid base64 bytecode character")?;
        let b = digit(quad[1]).ok_or("invalid base64 bytecode character")?;
        let c = if quad[2] == b'=' {
            if !final_quad || quad[3] != b'=' || b & 0x0f != 0 {
                return Err("invalid base64 bytecode padding");
            }
            None
        } else {
            Some(digit(quad[2]).ok_or("invalid base64 bytecode character")?)
        };
        let d = if quad[3] == b'=' {
            if !final_quad || c.is_some_and(|c| c & 0x03 != 0) {
                return Err("invalid base64 bytecode padding");
            }
            None
        } else {
            Some(digit(quad[3]).ok_or("invalid base64 bytecode character")?)
        };
        if c.is_none() && d.is_some() {
            return Err("invalid base64 bytecode padding");
        }
        output.push((a << 2) | (b >> 4));
        if let Some(c) = c {
            output.push((b << 4) | (c >> 2));
            if let Some(d) = d {
                output.push((c << 6) | d);
            }
        }
    }
    Ok(output)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamArgument {
    pub name: String,
    /// Compiler-generated proc evaluating `arg in expression` at call time.
    #[serde(default)]
    pub possible_values_proc: Option<usize>,
    #[serde(default)]
    pub r#type: u32,
    /// Optional compiler extension preserving a typed parameter path when
    /// OpenDream's coarse `Type` flags cannot represent it.
    #[serde(default)]
    pub type_path: Option<String>,
    /// Exact source argument declaration path. `TypePath` collapses
    /// `list/turf/x` to `/list`, losing the native element type flags.
    #[serde(default)]
    pub declared_path: Option<String>,
    /// A leading-absolute path in a parameter list declares a type in
    /// DreamMaker rather than a formal argument.
    #[serde(default)]
    pub native_omit: bool,
    /// Explicit null parameter default; DreamMaker can add a nullable
    /// argument type flag even when the authored `as` mask omits null.
    #[serde(default)]
    pub default_is_null: bool,
    /// Authored default expression, independently of its value.
    #[serde(default)]
    pub has_default: bool,
    /// Optional compatible JSON extension. OpenDream currently serializes
    /// explicit `as anything` and an untyped argument with the same Type=0.
    #[serde(default)]
    pub explicit_anything: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamLocal {
    #[serde(default)]
    pub offset: usize,
    pub remove: Option<usize>,
    pub add: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamSourceInfo {
    #[serde(default)]
    pub offset: usize,
    pub file: Option<usize>,
    #[serde(default)]
    pub line: usize,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamMap {
    #[serde(default)]
    pub max_x: i32,
    #[serde(default)]
    pub max_y: i32,
    #[serde(default)]
    pub max_z: i32,
    #[serde(default)]
    pub cell_definitions: HashMap<String, OpenDreamCell>,
    #[serde(default)]
    pub blocks: Vec<OpenDreamMapBlock>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamCell {
    pub name: String,
    pub turf: Option<OpenDreamMapObject>,
    pub area: Option<OpenDreamMapObject>,
    #[serde(default)]
    pub objects: Vec<OpenDreamMapObject>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamMapObject {
    #[serde(rename = "Type")]
    pub type_id: usize,
    #[serde(default)]
    pub var_overrides: HashMap<String, Value>,
    /// Source order of DMM override assignments, including repeated keys.
    #[serde(default)]
    pub override_order: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct OpenDreamMapBlock {
    pub x: i32,
    pub y: i32,
    pub z: i32,
    pub width: i32,
    pub height: i32,
    pub cells: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delete_provenance_is_optional_and_uses_valid_unsigned_offsets() {
        let plain: OpenDreamProc = serde_json::from_str(r#"{"Name":"plain"}"#).unwrap();
        assert!(plain.native_delete_src_offsets.is_empty());
        assert!(plain.native_delete_clear_offsets.is_empty());
        let marked: OpenDreamProc = serde_json::from_str(
            r#"{"Name":"marked","Bytecode":"BiCF","NativeDeleteSrcOffsets":[1],"NativeDeleteClearOffsets":[2]}"#,
        ).unwrap();
        assert_eq!(marked.native_delete_src_offsets, [1]);
        assert_eq!(marked.native_delete_clear_offsets, [2]);
        assert_eq!(
            marked.bytecode.as_ref().unwrap()[marked.native_delete_src_offsets[0] as usize],
            0x20
        );
        assert_eq!(
            marked.bytecode.as_ref().unwrap()[marked.native_delete_clear_offsets[0] as usize],
            0x85
        );
        for invalid in ["-1", "1.5", "4294967296"] {
            for field in ["NativeDeleteSrcOffsets", "NativeDeleteClearOffsets"] {
                let json = format!(r#"{{"Name":"invalid","{field}":[{invalid}]}}"#);
                assert!(serde_json::from_str::<OpenDreamProc>(&json).is_err());
            }
        }
    }

    #[test]
    fn parses_compiler_defaults_and_base64_bytecode() {
        let json = br#"{
          "Metadata":{"Version":"opcode-hash"},"Strings":["x"],
          "Types":[{"Path":"/"},{"Path":"/obj","Parent":0,"Variables":{"icon":{"type":0,"resourcePath":"x.dmi"}}}],
          "Procs":[{"Name":"f","SourceInfo":[],"Bytecode":"AAECA/8="}],
          "OptionalErrors":{}
        }"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        assert_eq!(
            program.procs[0].bytecode.as_deref(),
            Some(&[0, 1, 2, 3, 255][..])
        );
        assert_eq!(program.procs[0].attributes, 0);
        assert_eq!(program.types[1].parent, Some(0));
        assert_eq!(program.types[1].variables["icon"]["resourcePath"], "x.dmi");
    }

    #[test]
    fn parses_maps_and_global_values() {
        let json = br#"{
          "Metadata":{"Version":"x"},"Strings":[],
          "Globals":{"GlobalCount":1,"Names":["g"],"Globals":{"0":{"type":1,"value":2}}},
          "Maps":[{"MaxX":1,"MaxY":1,"MaxZ":1,"CellDefinitions":{"a":{"Name":"a","Turf":{"Type":2,"VarOverrides":{"dir":4,"name":"x"},"OverrideOrder":["name","dir"]},"Objects":[]}},"Blocks":[{"X":1,"Y":1,"Z":1,"Width":1,"Height":1,"Cells":["a"]}]}],
          "Types":[],"Procs":[],"OptionalErrors":{}
        }"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        assert_eq!(program.globals.as_ref().unwrap().globals[&0]["value"], 2);
        assert_eq!(
            program.maps[0].cell_definitions["a"]
                .turf
                .as_ref()
                .unwrap()
                .override_order,
            ["name", "dir"]
        );
        assert_eq!(
            program.maps[0].cell_definitions["a"]
                .turf
                .as_ref()
                .unwrap()
                .type_id,
            2
        );
    }

    #[test]
    fn rejects_bad_base64_bytecode() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Types":[],"Procs":[{"Name":"f","SourceInfo":[],"Bytecode":"AA=Z"}],"OptionalErrors":{}}"#;
        assert!(OpenDreamProgram::from_slice(json).is_err());
    }

    #[test]
    fn optional_explicit_anything_argument_annotation_is_backward_compatible() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Types":[],"Procs":[{"Name":"f","Arguments":[{"Name":"plain"},{"Name":"any","ExplicitAnything":true},{"Name":"union","Type":1,"ExplicitAnything":true}]}]}"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        assert!(!program.procs[0].arguments[0].explicit_anything);
        assert!(program.procs[0].arguments[1].explicit_anything);
        assert_eq!(program.procs[0].arguments[2].r#type, 1);
        assert!(program.procs[0].arguments[2].explicit_anything);
    }

    #[test]
    fn optional_explicit_invisibility_preserves_zero_setting() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Types":[],"Procs":[{"Name":"default"},{"Name":"zero","ExplicitInvisibility":true},{"Name":"high","Invisibility":7,"ExplicitInvisibility":true}]}"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        assert!(!program.procs[0].explicit_invisibility);
        assert_eq!(program.procs[1].invisibility, 0);
        assert!(program.procs[1].explicit_invisibility);
        assert_eq!(program.procs[2].invisibility, 7);
    }

    #[test]
    fn explicit_verb_fields_preserve_false_overrides() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Types":[],"Procs":[{"Name":"parent","Attributes":8,"ExplicitVerbFields":["hidden","category"],"ExplicitVerbFieldValues":{"hidden":true},"ExplicitVerbTextValues":{"category":"Parent"}},{"Name":"child","Attributes":2},{"Name":"clear","Attributes":2,"ExplicitVerbFields":["hidden","src"],"ExplicitVerbFieldValues":{"hidden":false,"waitfor":true},"ExplicitVerbTextValues":{"category":null},"ExplicitVerbSource":1,"ExplicitVerbRange":1,"ExplicitVerbSourceWasIn":false,"NestedBackground":true}]}"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        assert!(program.procs[0].explicit_verb_fields.contains("hidden"));
        assert!(program.procs[1].explicit_verb_fields.is_empty());
        assert!(program.procs[2].explicit_verb_fields.contains("hidden"));
        assert_eq!(
            program.procs[0].explicit_verb_field_values.get("hidden"),
            Some(&true)
        );
        assert!(program.procs[1].explicit_verb_field_values.is_empty());
        assert_eq!(
            program.procs[2].explicit_verb_field_values.get("hidden"),
            Some(&false)
        );
        assert_eq!(
            program.procs[2].explicit_verb_field_values.get("waitfor"),
            Some(&true)
        );
        assert_eq!(
            program.procs[0].explicit_verb_text_values.get("category"),
            Some(&Some("Parent".to_string()))
        );
        assert_eq!(
            program.procs[2].explicit_verb_text_values.get("category"),
            Some(&None)
        );
        assert_eq!(program.procs[2].explicit_verb_source, Some(1));
        assert_eq!(program.procs[2].explicit_verb_range, Some(1));
        assert_eq!(program.procs[2].explicit_verb_source_was_in, Some(false));
        assert!(program.procs[2].nested_background);
    }

    #[test]
    fn lexical_local_add_indices_preserve_shadowed_names() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Types":[],"Procs":[{"Name":"f","Locals":[{"Add":"item"},{"Remove":1},{"Add":"item"}],"LexicalLocalAddIndices":[1,0]}]}"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        assert_eq!(program.procs[0].lexical_local_add_indices, [1, 0]);
        assert_eq!(program.procs[0].locals.len(), 3);
    }

    #[test]
    fn declared_argument_path_preserves_list_element_and_absolute_type() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Types":[],"Procs":[{"Name":"f","Arguments":[{"Name":"to_add","TypePath":"/list","DeclaredPath":"list/turf/to_add"},{"Name":"A","TypePath":"/datum/disease/advance","DeclaredPath":"/datum/disease/advance/A","NativeOmit":true}]}]}"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        let args = &program.procs[0].arguments;
        assert_eq!(args[0].declared_path.as_deref(), Some("list/turf/to_add"));
        assert!(!args[0].native_omit);
        assert_eq!(
            args[1].declared_path.as_deref(),
            Some("/datum/disease/advance/A")
        );
        assert!(args[1].native_omit);
    }

    #[test]
    fn argument_default_provenance_is_optional() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Types":[],"Procs":[{"Name":"f","Arguments":[{"Name":"plain"},{"Name":"zero","HasDefault":true},{"Name":"nil","HasDefault":true,"DefaultIsNull":true}]}]}"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        let args = &program.procs[0].arguments;
        assert!(!args[0].has_default);
        assert!(args[1].has_default);
        assert!(!args[1].default_is_null);
        assert!(args[2].has_default && args[2].default_is_null);
    }

    #[test]
    fn optional_explicit_type_fields_preserve_default_equal_override() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Types":[{"Path":"/area","Variables":{"luminosity":1},"ExplicitTypeFields":["luminosity"],"VariableDeclarationOrder":["luminosity"]},{"Path":"/area/plain","Parent":0,"Variables":{"luminosity":1}}],"Procs":[]}"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        assert!(program.types[0].explicit_type_fields.contains("luminosity"));
        assert_eq!(program.types[0].variable_declaration_order, ["luminosity"]);
        assert!(program.types[1].explicit_type_fields.is_empty());
    }

    #[test]
    fn modified_type_and_original_declaration_values_parse() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Types":[{"Path":"/datum/holder","Variables":{"uniform":{"type":1,"value":1},"state":"new"},"VariableDeclarationValues":{"state":"old","empty":null},"ModifiedTypeOverrideValues":{"uniform":{"TypePath":"/obj/uniform","Overrides":{"amount":20,"items":{"type":3,"values":[1,2]}},"OverrideOrder":["amount","items"]}}},{"Path":"/obj/uniform"}],"Procs":[]}"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        let holder = &program.types[0];
        assert_eq!(holder.variable_declaration_values["state"], "old");
        assert!(holder.variable_declaration_values["empty"].is_null());
        let modified = &holder.modified_type_override_values["uniform"];
        assert_eq!(modified.type_path, "/obj/uniform");
        assert_eq!(modified.override_order, ["amount", "items"]);
        assert_eq!(modified.overrides["amount"], 20);
    }

    #[test]
    fn optional_global_markers_and_argument_sources_parse() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Resources":["Asset.txt"],"ResourceAliases":{"asset.txt":"Asset.txt"},"Globals":{"GlobalCount":2,"Names":["items","image"],"Globals":{},"DynamicInitializerGlobalIds":[0],"TemporaryGlobalIds":[1],"ConstGlobalIds":[1],"ConstFieldGlobalIds":[1],"DeclarationValues":{"0":0,"1":"\u00a0"},"CompileTimeConstDeclarations":[{"Name":"GUID_VARIANT","Value":"d"},{"ProcId":1,"Name":"LIMIT","Value":0}],"InitializerValueKinds":{"0":"List","1":"ProcCall"}},"Types":[{"Path":"/obj","ConstantInitializerFields":{"name":"child"},"ConstantInitializerAssignments":["name"],"InitializerAssignmentCount":1}],"Procs":[{"Name":"choose","Arguments":[{"Name":"choice","PossibleValuesProc":1}]},{"Name":"<init>"}]}"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        let globals = program.globals.unwrap();
        assert!(globals.dynamic_initializer_global_ids.contains(&0));
        assert!(!globals.dynamic_initializer_global_ids.contains(&1));
        assert!(globals.temporary_global_ids.contains(&1));
        assert!(globals.const_global_ids.contains(&1));
        assert!(globals.const_field_global_ids.contains(&1));
        assert_eq!(globals.declaration_values[&0], 0);
        assert_eq!(globals.declaration_values[&1], " ");
        assert_eq!(globals.compile_time_const_declarations[0].proc_id, 0);
        assert_eq!(
            globals.compile_time_const_declarations[0].name,
            "GUID_VARIANT"
        );
        assert_eq!(globals.compile_time_const_declarations[0].value, "d");
        assert_eq!(globals.compile_time_const_declarations[1].proc_id, 1);
        assert_eq!(globals.initializer_value_kinds[&1], "ProcCall");
        assert_eq!(program.procs[0].arguments[0].possible_values_proc, Some(1));
        assert_eq!(program.resource_aliases["asset.txt"], "Asset.txt");
        assert_eq!(
            program.types[0].constant_initializer_fields["name"],
            "child"
        );
        assert_eq!(program.types[0].initializer_assignment_count, 1);
        assert_eq!(program.types[0].constant_initializer_assignments, ["name"]);
    }

    #[test]
    fn optional_dynamic_initializer_fields_are_backward_compatible() {
        let json = br#"{"Metadata":{"Version":"x"},"Strings":[],"Types":[{"Path":"/obj","DynamicInitializerFields":["contents"],"DynamicDeclarationFields":["contents"],"DynamicInitializerAssignments":["contents","contents"],"InitializerValueKinds":{"contents":"List","name":"String"}},{"Path":"/obj/plain"}],"Procs":[]}"#;
        let program = OpenDreamProgram::from_slice(json).unwrap();
        assert!(program.types[0]
            .dynamic_initializer_fields
            .contains("contents"));
        assert!(program.types[0]
            .dynamic_declaration_fields
            .contains("contents"));
        assert_eq!(program.types[0].initializer_value_kinds["name"], "String");
        assert_eq!(program.types[0].dynamic_initializer_assignments.len(), 2);
        assert!(program.types[1].dynamic_initializer_fields.is_empty());
    }

    #[test]
    fn patched_dynamic_initializer_fixture_preserves_declaration_and_override_order() {
        let program = OpenDreamProgram::from_slice(include_bytes!(
            "../fixtures/translation/dynamic_initializer_fields.json"
        ))
        .unwrap();
        let datum = program
            .types
            .iter()
            .find(|ty| ty.path == "/datum/dynamic_initializer_probe")
            .unwrap();
        assert_eq!(datum.dynamic_declaration_fields.len(), 1);
        assert!(datum.dynamic_declaration_fields.contains("items"));
        assert_eq!(
            datum.dynamic_initializer_assignments,
            ["items", "items", "created"]
        );
        assert!(!datum.dynamic_initializer_fields.contains("cleared"));
        let particles = program
            .types
            .iter()
            .find(|ty| ty.path == "/particles/dynamic_initializer_probe")
            .unwrap();
        assert_eq!(particles.dynamic_initializer_assignments, ["drift"]);
        assert_eq!(particles.initializer_value_kinds["drift"], "ProcCall");
    }

    #[test]
    fn parses_real_compiler_output_when_available() {
        let Ok(path) = std::env::var("OPENDREAM_SMOKE_JSON") else {
            return;
        };
        let program = OpenDreamProgram::from_path(path).unwrap();
        assert!(program.types.iter().any(|ty| ty.path == "/world"));
        assert!(program.procs.iter().any(|proc_| !proc_
            .bytecode
            .as_deref()
            .unwrap_or_default()
            .is_empty()));
    }
}
