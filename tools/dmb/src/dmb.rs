//! BYOND 516 compiled-world container reader and writer.
//!
//! Table boundaries and field widths are validated on DeepQuarry's v516 DMB.
//! Unknown fields retain their exact numeric values. Procedure bytecode is
//! stored as list words; semantic opcode decoding is a separate layer.
use crate::hash::nqcrc;
use serde::{Deserialize, Serialize};
use crate::ids::{ResourceId, NONE};
use std::collections::{HashMap, HashSet};
use std::io::{self, ErrorKind};

fn invalid(message: &'static str) -> io::Error {
    io::Error::new(ErrorKind::InvalidData, message)
}

struct Reader<'a> {
    data: &'a [u8],
    at: usize,
    object_size: usize,
    compatibility_version: u16,
}

impl<'a> Reader<'a> {
    fn take(&mut self, len: usize) -> io::Result<&'a [u8]> {
        let end = self
            .at
            .checked_add(len)
            .ok_or_else(|| invalid("offset overflow"))?;
        let bytes = self.data.get(self.at..end).ok_or_else(|| {
            io::Error::new(
                ErrorKind::InvalidData,
                format!("truncated DMB at byte {} reading {len} bytes", self.at),
            )
        })?;
        self.at = end;
        Ok(bytes)
    }
    fn u8(&mut self) -> io::Result<u8> {
        Ok(self.take(1)?[0])
    }
    fn u16(&mut self) -> io::Result<u16> {
        Ok(u16::from_le_bytes(self.take(2)?.try_into().unwrap()))
    }
    fn u32(&mut self) -> io::Result<u32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    fn object(&mut self) -> io::Result<u32> {
        if self.object_size == 2 {
            Ok(u32::from(self.u16()?))
        } else {
            self.u32()
        }
    }
    fn f32_bits(&mut self) -> io::Result<u32> {
        self.u32()
    }
    fn line(&mut self) -> io::Result<Vec<u8>> {
        let rest = &self.data[self.at..];
        let len = rest
            .iter()
            .position(|&x| x == b'\n')
            .ok_or_else(|| invalid("missing DMB header newline"))?
            + 1;
        Ok(self.take(len)?.to_vec())
    }
    fn table<T>(&mut self, mut read: impl FnMut(&mut Self) -> io::Result<T>) -> io::Result<Vec<T>> {
        let count = self.object()? as usize;
        let mut entries = Vec::new();
        for _ in 0..count {
            entries.push(read(self)?);
        }
        Ok(entries)
    }
}

struct Writer {
    bytes: Vec<u8>,
    object_size: usize,
    object_overflow: bool,
    compatibility_version: u16,
}
impl Writer {
    fn new(object_size: usize, compatibility_version: u16) -> Self {
        Self {
            bytes: Vec::new(),
            object_size,
            object_overflow: false,
            compatibility_version,
        }
    }
    fn at(&self) -> usize {
        self.bytes.len()
    }
    fn raw(&mut self, bytes: &[u8]) {
        self.bytes.extend_from_slice(bytes);
    }
    fn u8(&mut self, value: u8) {
        self.bytes.push(value);
    }
    fn u16(&mut self, value: u16) {
        self.raw(&value.to_le_bytes());
    }
    fn u32(&mut self, value: u32) {
        self.raw(&value.to_le_bytes());
    }
    fn object(&mut self, value: u32) {
        if self.object_size == 2 {
            if value > u16::MAX as u32 {
                self.object_overflow = true;
            }
            self.u16(value as u16);
        } else {
            self.u32(value);
        }
    }
    fn table<T>(&mut self, items: &[T], mut write: impl FnMut(&mut Self, &T)) -> io::Result<()> {
        let count = u32::try_from(items.len()).map_err(|_| invalid("table exceeds u32 count"))?;
        self.object(count);
        for item in items {
            write(self, item);
        }
        Ok(())
    }
}

fn compatibility_version(line: &[u8]) -> io::Result<u16> {
    let text = std::str::from_utf8(line).map_err(|_| invalid("non-ASCII compatibility line"))?;
    let number = text
        .strip_prefix("min compatibility v")
        .and_then(|tail| tail.split_ascii_whitespace().next())
        .ok_or_else(|| invalid("unsupported compatibility header"))?;
    number
        .parse::<u16>()
        .map_err(|_| invalid("invalid compatibility version"))
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Header {
    /// Optional native CGI executor prefix, including all its authored lines.
    pub executor_line: Option<Vec<u8>>,
    pub version_line: Vec<u8>,
    pub compatibility_line: Vec<u8>,
    pub flags: u32,
    /// Present when bit 31 of `flags` is set. Its bit meanings need probes.
    pub extended_flags: Option<u32>,
}
impl Header {
    /// Dream Maker emits DbgFile/DbgLine instructions when this bit is set.
    pub fn debug_symbols(&self) -> bool {
        self.flags & 0x0002_0000 != 0
    }
    pub fn uses_large_object_ids(&self) -> bool {
        self.flags & 0x4000_0000 != 0
    }
    pub fn loop_checks_disabled(&self) -> bool {
        self.flags & 0x2 != 0
    }
    pub fn sleeps_offline(&self) -> bool {
        self.flags & 0x20 != 0
    }
    pub fn hidden_from_hub(&self) -> bool {
        self.flags & 0x2000 != 0
    }
    pub fn verb_panel_disabled(&self) -> bool {
        self.flags & 0x400 != 0
    }
    pub fn hub_authentication_disabled(&self) -> bool {
        self.flags & 0x8000 != 0
    }
    pub fn client_map_disabled(&self) -> bool {
        self.flags & 0x10_0000 != 0
    }
    pub fn popup_menus_disabled(&self) -> bool {
        self.flags & 0x1000_0000 != 0
    }
    pub fn uses_dynamic_calls(&self) -> bool {
        self.flags & 0x2000_0000 != 0
    }
    pub fn resource_preload_mode(&self) -> Option<u8> {
        match self.flags & 0x1800 {
            0 => Some(1),
            0x800 => Some(0),
            0x1000 => Some(2),
            _ => None,
        }
    }
    pub fn movement_mode_setting(&self) -> Option<u8> {
        match self.extended_flags.unwrap_or(0) & 0xc {
            0 => Some(0),
            4 => Some(1),
            8 => Some(2),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct GridRun {
    pub turf: u32,
    pub area: u32,
    pub contents: u32,
    pub copies: u8,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Class {
    pub initial_ids: [u32; 6],
    pub direction: u8,
    pub interface: u8,
    pub extended_interface: Option<u32>,
    pub text: u32,
    pub maptext: u32,
    pub maptext_geometry: [u16; 4],
    pub suffix: u32,
    pub flags: u64,
    pub lists_and_procs: [u32; 6],
    pub layer_bits: u32,
    pub transform_flag: u8,
    pub transform: Option<[u32; 6]>,
    pub color_matrix_flag: u8,
    pub color_matrix: Option<[u32; 20]>,
    pub overrides: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ClassInterface {
    Regular,
    Image,
    Sound,
    Icon,
    Matrix,
    Regex,
    MutableAppearance,
    Generator,
    DatabaseQuery,
    Other {
        discriminator: u8,
        extension: Option<u32>,
    },
}

impl Class {
    pub fn native_interface(&self) -> ClassInterface {
        match (self.interface, self.extended_interface) {
            (1, None) => ClassInterface::Regular,
            (15, Some(65)) => ClassInterface::Image,
            (15, Some(545)) => ClassInterface::Sound,
            (15, Some(769)) => ClassInterface::Icon,
            (15, Some(1025)) => ClassInterface::Matrix,
            (15, Some(8193)) => ClassInterface::Regex,
            (15, Some(16449)) => ClassInterface::MutableAppearance,
            (15, Some(32769)) => ClassInterface::Generator,
            (15, Some(36865)) => ClassInterface::DatabaseQuery,
            (discriminator, extension) => ClassInterface::Other {
                discriminator,
                extension,
            },
        }
    }
    /// Initial invisibility is zero when this flag is set.
    pub fn is_normally_visible(&self) -> bool {
        self.flags & 0x4 != 0
    }

    /// The three low luminosity bits stored with the initial appearance.
    pub fn luminosity(&self) -> u8 {
        ((self.flags >> 3) & 0x7) as u8
    }

    pub fn set_luminosity(&mut self, value: u8) -> io::Result<()> {
        if value > 7 {
            return Err(invalid("packed luminosity exceeds three bits"));
        }
        self.flags = (self.flags & !(0x7 << 3)) | (u64::from(value) << 3);
        Ok(())
    }

    pub fn has_mouse_event_proc(&self) -> bool {
        self.flags & 0x800 != 0
    }

    pub fn is_mouse_drop_zone(&self) -> bool {
        self.flags & 0x100 != 0
    }

    pub fn set_mouse_drop_zone(&mut self, enabled: bool) {
        self.flags = (self.flags & !0x100) | (u64::from(enabled) << 8);
    }

    pub fn has_mouse_move_proc(&self) -> bool {
        self.flags & 0x80000 != 0
    }

    pub fn has_mouse_wheel_proc(&self) -> bool {
        self.flags & 0x100000 != 0
    }

    /// Initial animate_movement (0 through 3). Zero additionally sets bit 10.
    pub fn animate_movement(&self) -> u8 {
        if self.flags & 0x400 != 0 {
            0
        } else {
            ((((self.flags >> 14) & 0x3) as u8) + 1) & 0x3
        }
    }

    pub fn set_animate_movement(&mut self, value: u8) -> io::Result<()> {
        if value > 3 {
            return Err(invalid("animate_movement exceeds two bits"));
        }
        self.flags &= !(0xc000 | 0x400);
        self.flags |= u64::from(value.wrapping_sub(1) & 0x3) << 14;
        if value == 0 {
            self.flags |= 0x400;
        }
        Ok(())
    }

    pub fn is_opaque(&self) -> bool {
        self.flags & 0x1 != 0
    }

    pub fn set_opaque(&mut self, opaque: bool) {
        self.flags = (self.flags & !0x1) | u64::from(opaque);
    }

    /// Initial density bit in the class flag word.
    pub fn is_dense(&self) -> bool {
        self.flags & 0x2 != 0
    }

    pub fn set_dense(&mut self, dense: bool) {
        self.flags = (self.flags & !0x2) | (u64::from(dense) << 1);
    }

    /// Enum encoding: 0 neuter, 1 male, 2 female, 3 plural.
    pub fn gender_code(&self) -> u8 {
        ((self.flags >> 6) & 0x3) as u8
    }

    pub fn set_gender_code(&mut self, code: u8) -> io::Result<()> {
        if code > 3 {
            return Err(invalid("gender code exceeds two bits"));
        }
        self.flags = (self.flags & !(0x3 << 6)) | (u64::from(code) << 6);
        Ok(())
    }

    /// Initial mouse_opacity (0 through 3), packed as value minus one.
    pub fn mouse_opacity(&self) -> u8 {
        (((self.flags >> 12) as u8 & 0x3) + 1) & 0x3
    }

    pub fn set_mouse_opacity(&mut self, value: u8) -> io::Result<()> {
        if value > 3 {
            return Err(invalid("mouse_opacity exceeds two bits"));
        }
        let encoded = (value.wrapping_sub(1) & 0x3) as u64;
        self.flags = (self.flags & !(0x3 << 12)) | (encoded << 12);
        Ok(())
    }

    /// Initial atom appearance_flags, packed above the 21 low class flag bits.
    pub fn appearance_flags(&self) -> u32 {
        (self.flags >> 21) as u32
    }

    pub fn set_appearance_flags(&mut self, value: u32) {
        self.flags = (self.flags & ((1u64 << 21) - 1)) | (u64::from(value) << 21);
    }

    pub fn path_string_id(&self) -> u32 {
        self.initial_ids[0]
    }
    pub fn parent_class_id(&self) -> u32 {
        self.initial_ids[1]
    }
    pub fn name_string_id(&self) -> u32 {
        self.initial_ids[2]
    }
    pub fn description_string_id(&self) -> u32 {
        self.initial_ids[3]
    }
    pub fn icon_resource_id(&self) -> u32 {
        self.initial_ids[4]
    }
    pub fn icon_state_string_id(&self) -> u32 {
        self.initial_ids[5]
    }
    pub fn verb_list_id(&self) -> u32 {
        self.lists_and_procs[0]
    }
    pub fn proc_list_id(&self) -> u32 {
        self.lists_and_procs[1]
    }
    pub fn initializer_proc_id(&self) -> u32 {
        self.lists_and_procs[2]
    }
    pub fn initialized_variable_list_id(&self) -> u32 {
        self.lists_and_procs[3]
    }
    pub fn defining_variable_list_id(&self) -> u32 {
        self.lists_and_procs[4]
    }
    pub fn overriding_variable_list_id(&self) -> u32 {
        self.overrides
    }

    fn read(r: &mut Reader<'_>) -> io::Result<Self> {
        let mut initial_ids = [0; 6];
        for id in &mut initial_ids {
            *id = r.object()?;
        }
        let direction = r.u8()?;
        let interface = r.u8()?;
        let extended_interface = if interface == 15 {
            Some(r.u32()?)
        } else {
            None
        };
        let text = r.object()?;
        let maptext = r.object()?;
        let mut maptext_geometry = [0; 4];
        for value in &mut maptext_geometry {
            *value = r.u16()?;
        }
        let suffix = r.object()?;
        let flags = u64::from(r.u32()?) | (u64::from(r.u32()?) << 32);
        let mut lists_and_procs = [0; 6];
        for id in &mut lists_and_procs {
            *id = r.object()?;
        }
        let layer_bits = r.f32_bits()?;
        let transform_flag = r.u8()?;
        let transform = if transform_flag != 0 {
            let mut values = [0; 6];
            for value in &mut values {
                *value = r.f32_bits()?;
            }
            Some(values)
        } else {
            None
        };
        let color_matrix_flag = r.u8()?;
        let color_matrix = if color_matrix_flag != 0 {
            let mut values = [0; 20];
            for value in &mut values {
                *value = r.f32_bits()?;
            }
            Some(values)
        } else {
            None
        };
        let overrides = r.object()?;
        Ok(Self {
            initial_ids,
            direction,
            interface,
            extended_interface,
            text,
            maptext,
            maptext_geometry,
            suffix,
            flags,
            lists_and_procs,
            layer_bits,
            transform_flag,
            transform,
            color_matrix_flag,
            color_matrix,
            overrides,
        })
    }
    fn write(&self, w: &mut Writer) {
        for id in self.initial_ids {
            w.object(id);
        }
        w.u8(self.direction);
        w.u8(self.interface);
        if let Some(value) = self.extended_interface {
            w.u32(value);
        }
        w.object(self.text);
        w.object(self.maptext);
        for value in self.maptext_geometry {
            w.u16(value);
        }
        w.object(self.suffix);
        w.u32(self.flags as u32);
        w.u32((self.flags >> 32) as u32);
        for id in self.lists_and_procs {
            w.object(id);
        }
        w.u32(self.layer_bits);
        w.u8(self.transform_flag);
        if let Some(values) = self.transform {
            for value in values {
                w.u32(value);
            }
        }
        w.u8(self.color_matrix_flag);
        if let Some(values) = self.color_matrix {
            for value in values {
                w.u32(value);
            }
        }
        w.object(self.overrides);
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct MobType {
    pub class: u32,
    pub key: u32,
    pub sight: u8,
    pub extended_sight: Option<(u32, u8, u8)>,
}
pub mod mob_sight {
    pub const BLIND: u32 = 1;
    pub const SEE_MOBS: u32 = 4;
    pub const SEE_OBJS: u32 = 8;
    pub const SEE_TURFS: u32 = 16;
    pub const SEE_SELF: u32 = 32;
    pub const SEE_INFRA: u32 = 64;
    pub const SEE_PIXELS: u32 = 256;
    pub const SEE_THRU: u32 = 512;
    pub const SEE_BLACKNESS: u32 = 1024;
    pub const SEE_INFRARED: u32 = 65536;
}
impl MobType {
    /// Effective `sight` bit mask; bit 0x80 in the wire record marks the
    /// extended form and is removed from the semantic value.
    pub fn sight_bits(&self) -> u32 {
        self.extended_sight
            .map_or(u32::from(self.sight), |record| record.0)
            & !0x80
    }
    pub fn see_in_dark_setting(&self) -> Option<u8> {
        self.extended_sight.map(|record| record.1)
    }
    pub fn see_invisible_setting(&self) -> Option<u8> {
        self.extended_sight.map(|record| record.2)
    }
    fn read(r: &mut Reader<'_>) -> io::Result<Self> {
        let class = r.object()?;
        let key = r.object()?;
        let sight = r.u8()?;
        let extended_sight = if sight & 0x80 != 0 {
            Some((r.u32()?, r.u8()?, r.u8()?))
        } else {
            None
        };
        Ok(Self {
            class,
            key,
            sight,
            extended_sight,
        })
    }
    fn write(&self, w: &mut Writer) {
        w.object(self.class);
        w.object(self.key);
        w.u8(self.sight);
        if let Some((flags, dark, invisible)) = self.extended_sight {
            w.u32(flags);
            w.u8(dark);
            w.u8(invisible);
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct DmString {
    pub data: Vec<u8>,
    /// Original count of 0xffff length chunks, kept for exact round trips.
    pub long_chunks: u16,
}

fn crypt_string(data: &mut [u8], offset: usize) {
    let mut key = offset as u8;
    for byte in data {
        *byte ^= key;
        key = key.wrapping_add(9);
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Proc {
    pub strings: [u32; 4],
    pub source_parameter: u8,
    pub source_kind: u8,
    pub flags: u8,
    pub extended_flags: Option<(u32, u8)>,
    pub code_locals_args: [u32; 3],
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProcSource {
    Default,
    InView(u8),
    InOView(u8),
    InRange(u8),
    InUsr,
    IsUsr,
    IsUsrLoc,
    Other { kind: u8, parameter: u8 },
}
impl Proc {
    pub fn source_location(&self) -> ProcSource {
        match self.source_kind {
            0 => ProcSource::Default,
            1 => ProcSource::InView(self.source_parameter),
            2 => ProcSource::InOView(self.source_parameter),
            3 => ProcSource::IsUsrLoc,
            5 => ProcSource::InRange(self.source_parameter),
            8 => ProcSource::InUsr,
            32 => ProcSource::IsUsr,
            kind => ProcSource::Other {
                kind,
                parameter: self.source_parameter,
            },
        }
    }
    /// Extended records replace the compact flag bits, retaining the same
    /// low-bit meanings and adding background/instant controls.
    pub fn effective_flags(&self) -> u32 {
        self.extended_flags
            .map_or(u32::from(self.flags), |extra| extra.0)
    }
    pub fn is_hidden(&self) -> bool {
        self.effective_flags() & 1 != 0
    }
    pub fn waits_for_completion(&self) -> bool {
        self.effective_flags() & 4 != 0
    }
    pub fn runs_in_background(&self) -> bool {
        self.effective_flags() & 0x100 != 0
    }
    pub fn is_instant(&self) -> bool {
        self.effective_flags() & 0x200 != 0
    }
    pub fn has_explicit_source(&self) -> bool {
        self.effective_flags() & 0x2 != 0
    }
    pub fn has_no_category(&self) -> bool {
        self.effective_flags() & 0x20 != 0
    }
    pub fn popup_menu_disabled(&self) -> bool {
        self.effective_flags() & 0x40 != 0
    }
    /// Explicit `set invisibility` value. Wire byte 255 encodes level zero;
    /// positive values use the byte directly and are capped at 127.
    pub fn invisibility_setting(&self) -> Option<u8> {
        let (flags, level) = self.extended_flags?;
        if flags & 0x8 == 0 {
            None
        } else if flags & 0x10 == 0 {
            Some(0)
        } else {
            Some(level)
        }
    }
    fn read(r: &mut Reader<'_>) -> io::Result<Self> {
        let mut strings = [0; 4];
        for value in &mut strings {
            *value = r.object()?;
        }
        let source_parameter = r.u8()?;
        let source_kind = r.u8()?;
        let flags = r.u8()?;
        let extended_flags = if flags & 0x80 != 0 {
            Some((r.u32()?, r.u8()?))
        } else {
            None
        };
        let mut code_locals_args = [0; 3];
        for value in &mut code_locals_args {
            *value = r.object()?;
        }
        Ok(Self {
            strings,
            source_parameter,
            source_kind,
            flags,
            extended_flags,
            code_locals_args,
        })
    }
    fn write(&self, w: &mut Writer) {
        for value in self.strings {
            w.object(value);
        }
        w.u8(self.source_parameter);
        w.u8(self.source_kind);
        w.u8(self.flags);
        if let Some((value, byte)) = self.extended_flags {
            w.u32(value);
            w.u8(byte);
        }
        for value in self.code_locals_args {
            w.object(value);
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Variable {
    pub kind: u8,
    pub value: u32,
    pub name: u32,
}
impl Variable {
    pub fn value_kind(&self) -> crate::operands::ValueKind {
        crate::operands::ValueKind::from_tag(self.kind)
    }
    pub fn number(&self) -> Option<f32> {
        (self.kind == 42).then(|| f32::from_bits(self.value))
    }
    /// Compiler-assigned marker for a value constructed by an initializer proc.
    /// The initializer bytecode uses the variable ID, not this marker.
    pub fn hidden_initializer_marker(&self) -> Option<u32> {
        (self.kind == 62).then_some(self.value)
    }
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Instance {
    pub kind: u8,
    pub class: u32,
    pub initializer: u32,
}
impl Instance {
    pub fn value_kind(&self) -> crate::operands::ValueKind {
        crate::operands::ValueKind::from_tag(self.kind)
    }
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct MapObject {
    pub offset: u16,
    pub instance: u32,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ResourceRef {
    pub id: u32,
    pub kind: u8,
}

/// Native loader interpretation of the serialized world.view word.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WorldViewEncoding {
    Radius(i16),
    Dimensions { width: u8, height: u8 },
}
impl WorldViewEncoding {
    /// Dimensions of the native loader's signed 16-bit axis fields.
    pub fn dimensions(self) -> (i16, i16) {
        match self {
            Self::Radius(radius) => {
                let side = radius.wrapping_mul(2).wrapping_add(1);
                (side, side)
            }
            Self::Dimensions { width, height } => (i16::from(width), i16::from(height)),
        }
    }
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct World {
    pub ids: [u32; 7],
    /// `world.tick_lag` expressed in integer milliseconds by Dream Maker.
    pub tick_lag: u32,
    pub client: u32,
    pub image: u32,
    /// Initial /savefile/byond_version value.
    pub savefile_byond_version: u32,
    pub eye: u8,
    pub direction: u8,
    pub control: u16,
    /// Authored client Import-handler presence. Kept under its original public
    /// field name for compatibility; use the semantic accessors below.
    pub unknown_byte: u8,
    pub client_script: u32,
    pub client_script_files: Vec<u32>,
    /// Serialized world.view word; use view_encoding() for the native radius/axis interpretation.
    pub view_dimensions: u16,
    pub hub_password: u32,
    pub server_name: u32,
    pub hub_number: u32,
    pub version: u32,
    pub cache_lifespan: u16,
    pub command_ids: [u32; 2],
    pub hub_channel_skin: [u32; 3],
    pub icon_dimensions_format: [u16; 3],
}
impl World {
    pub fn has_client_import_handler(&self) -> bool {
        self.unknown_byte != 0
    }
    pub fn set_client_import_handler(&mut self, present: bool) {
        self.unknown_byte = u8::from(present);
    }
    pub fn mob_type_id(&self) -> u32 {
        self.ids[0]
    }
    pub fn turf_class_id(&self) -> u32 {
        self.ids[1]
    }
    pub fn area_class_id(&self) -> u32 {
        self.ids[2]
    }
    pub fn proc_list_id(&self) -> u32 {
        self.ids[3]
    }
    pub fn global_initializer_proc_id(&self) -> u32 {
        self.ids[4]
    }
    pub fn domain_string_id(&self) -> u32 {
        self.ids[5]
    }
    pub fn name_string_id(&self) -> u32 {
        self.ids[6]
    }
    pub fn client_command_text_id(&self) -> u32 {
        self.command_ids[0]
    }
    pub fn client_command_prompt_id(&self) -> u32 {
        self.command_ids[1]
    }
    pub fn hub_string_id(&self) -> u32 {
        self.hub_channel_skin[0]
    }
    pub fn channel_string_id(&self) -> u32 {
        self.hub_channel_skin[1]
    }
    pub fn skin_resource_id(&self) -> u32 {
        self.hub_channel_skin[2]
    }
    pub fn icon_size(&self) -> (u16, u16) {
        (
            self.icon_dimensions_format[0],
            self.icon_dimensions_format[1],
        )
    }
    pub fn map_format(&self) -> u16 {
        self.icon_dimensions_format[2]
    }
    pub fn view_encoding(&self) -> WorldViewEncoding {
        let signed = self.view_dimensions as i16;
        if signed <= 255 {
            WorldViewEncoding::Radius(signed)
        } else {
            WorldViewEncoding::Dimensions {
                width: (self.view_dimensions >> 8) as u8,
                height: self.view_dimensions as u8,
            }
        }
    }
    pub fn native_view_size(&self) -> (i16, i16) {
        self.view_encoding().dimensions()
    }
    /// Raw high/low bytes, retained for compatibility. These are not always axes.
    pub fn view_size(&self) -> (u8, u8) {
        (
            (self.view_dimensions >> 8) as u8,
            self.view_dimensions as u8,
        )
    }

    pub fn set_view_size(&mut self, width: u8, height: u8) {
        self.view_dimensions = (u16::from(width) << 8) | u16::from(height);
    }

    fn read(r: &mut Reader<'_>) -> io::Result<Self> {
        let mut ids = [0; 7];
        for value in &mut ids {
            *value = r.object()?;
        }
        let tick_lag = r.u32()?;
        let client = r.object()?;
        let image = r.object()?;
        let savefile_byond_version = if r.compatibility_version <= 514 {
            0
        } else {
            r.u32()?
        };
        let eye = r.u8()?;
        let direction = r.u8()?;
        let control = r.u16()?;
        let unknown_byte = r.u8()?;
        let client_script = r.object()?;
        let script_file_count = r.u16()? as usize;
        let mut client_script_files = Vec::with_capacity(script_file_count);
        for _ in 0..script_file_count {
            client_script_files.push(r.object()?);
        }
        let view_dimensions = r.u16()?;
        let hub_password = r.object()?;
        let server_name = r.object()?;
        let hub_number = r.u32()?;
        let version = r.u32()?;
        let cache_lifespan = r.u16()?;
        let mut command_ids = [0; 2];
        for value in &mut command_ids {
            *value = r.object()?;
        }
        let mut hub_channel_skin = [0; 3];
        for value in &mut hub_channel_skin {
            *value = r.object()?;
        }
        let mut icon_dimensions_format = [0; 3];
        for value in &mut icon_dimensions_format {
            *value = r.u16()?;
        }
        Ok(Self {
            ids,
            tick_lag,
            client,
            image,
            savefile_byond_version,
            eye,
            direction,
            control,
            unknown_byte,
            client_script,
            client_script_files,
            view_dimensions,
            hub_password,
            server_name,
            hub_number,
            version,
            cache_lifespan,
            command_ids,
            hub_channel_skin,
            icon_dimensions_format,
        })
    }
    fn write(&self, w: &mut Writer) {
        for value in self.ids {
            w.object(value);
        }
        w.u32(self.tick_lag);
        w.object(self.client);
        w.object(self.image);
        if w.compatibility_version > 514 {
            w.u32(self.savefile_byond_version);
        }
        w.u8(self.eye);
        w.u8(self.direction);
        w.u16(self.control);
        w.u8(self.unknown_byte);
        w.object(self.client_script);
        w.u16(self.client_script_files.len() as u16);
        for value in &self.client_script_files {
            w.object(*value);
        }
        w.u16(self.view_dimensions);
        w.object(self.hub_password);
        w.object(self.server_name);
        w.u32(self.hub_number);
        w.u32(self.version);
        w.u16(self.cache_lifespan);
        for value in self.command_ids {
            w.object(value);
        }
        for value in self.hub_channel_skin {
            w.object(value);
        }
        for value in self.icon_dimensions_format {
            w.u16(value);
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Dmb {
    pub header: Header,
    pub dimensions: [u16; 3],
    pub grid: Vec<GridRun>,
    pub classes: Vec<Class>,
    pub mobs: Vec<MobType>,
    pub strings: Vec<DmString>,
    pub lists: Vec<Vec<u32>>,
    pub procs: Vec<Proc>,
    pub variables: Vec<Variable>,
    /// List ID of (variable ID, declaration flags) pairs for globals.
    pub variable_footer: u32,
    pub proc_references: Vec<u32>,
    pub instances: Vec<Instance>,
    pub map_objects: Vec<MapObject>,
    pub world: World,
    pub resources: Vec<ResourceRef>,
}

/// Reusable index for looking up many DMB resource references in one archive.
pub struct ResourceLookup<'a> {
    archive: &'a [crate::rsc::Entry],
    by_key: HashMap<(u32, u8), usize>,
}

impl<'a> ResourceLookup<'a> {
    pub fn new(archive: &'a [crate::rsc::Entry]) -> Self {
        let mut by_key = HashMap::new();
        for (index, entry) in archive.iter().enumerate() {
            if let crate::rsc::Entry::Named(resource) = entry {
                by_key.entry((resource.id, resource.kind)).or_insert(index);
            }
        }
        Self { archive, by_key }
    }

    pub fn get(&self, dmb: &Dmb, index: ResourceId) -> Option<&'a crate::rsc::NamedResource> {
        let reference = dmb.resources.get(index.index())?;
        let entry = self
            .archive
            .get(*self.by_key.get(&(reference.id, reference.kind))?)?;
        match entry {
            crate::rsc::Entry::Named(resource) => Some(resource),
            crate::rsc::Entry::Opaque { .. } => None,
        }
    }
}

/// Attach borrowed assets while retaining only references to archive payloads.
/// Distinct spellings of identical content share a table and archive entry.
pub fn attach_resource_refs<'a>(
    dmb: &mut Dmb,
    resources: impl IntoIterator<Item = &'a crate::rsc::NamedResource>,
) -> io::Result<(Vec<ResourceId>, Vec<&'a crate::rsc::NamedResource>)> {
    let mut references = HashMap::new();
    for (id, resource) in dmb.resources.iter().enumerate() {
        references
            .entry((resource.id, resource.kind))
            .or_insert(id as u32);
    }
    let mut archive: Vec<&crate::rsc::NamedResource> = Vec::new();
    let mut entries: HashMap<(u32, u8), usize> = HashMap::new();
    let mut ids = Vec::new();
    for resource in resources {
        if resource.content_id()? != resource.id {
            return Err(invalid("RSC resource ID does not match asset content"));
        }
        let key = (resource.id, resource.kind);
        if let Some(&entry) = entries.get(&key) {
            if archive[entry].asset_bytes()? != resource.asset_bytes()? {
                return Err(invalid("RSC resource ID collision"));
            }
        } else {
            entries.insert(key, archive.len());
            archive.push(resource);
        }
        let index = if let Some(&index) = references.get(&key) {
            index
        } else {
            let index = u32::try_from(dmb.resources.len())
                .map_err(|_| invalid("resource index exceeds u32"))?;
            ResourceId::from_raw(index).ok_or_else(|| invalid("reserved resource index"))?;
            dmb.resources.push(ResourceRef {
                id: resource.id,
                kind: resource.kind,
            });
            references.insert(key, index);
            index
        };
        ids.push(ResourceId::from_raw(index).ok_or_else(|| invalid("reserved resource index"))?);
    }
    Ok((ids, archive))
}

/// Keeps resource tables indexed while inserting a batch of assets.
pub struct ResourceAttachment<'a> {
    dmb: &'a mut Dmb,
    archive: &'a mut Vec<crate::rsc::Entry>,
    references: HashMap<(u32, u8), u32>,
    archive_entries: HashMap<(u32, u8), usize>,
}

impl<'a> ResourceAttachment<'a> {
    pub fn new(dmb: &'a mut Dmb, archive: &'a mut Vec<crate::rsc::Entry>) -> Self {
        let mut references = HashMap::new();
        for (index, reference) in dmb.resources.iter().enumerate() {
            references
                .entry((reference.id, reference.kind))
                .or_insert(index as u32);
        }
        let mut archive_entries = HashMap::new();
        for (index, entry) in archive.iter().enumerate() {
            if let crate::rsc::Entry::Named(resource) = entry {
                archive_entries
                    .entry((resource.id, resource.kind))
                    .or_insert(index);
            }
        }
        Self {
            dmb,
            archive,
            references,
            archive_entries,
        }
    }

    pub fn attach(&mut self, resource: crate::rsc::NamedResource) -> io::Result<ResourceId> {
        if resource.content_id()? != resource.id {
            return Err(invalid("RSC resource ID does not match asset content"));
        }
        let key = (resource.id, resource.kind);
        if let Some(&index) = self.references.get(&key) {
            let entry = self
                .archive_entries
                .get(&key)
                .and_then(|&position| self.archive.get(position))
                .ok_or_else(|| invalid("DMB resource reference missing from RSC"))?;
            let crate::rsc::Entry::Named(existing) = entry else {
                return Err(invalid("RSC resource index is not named"));
            };
            if existing.asset_bytes()? != resource.asset_bytes()? {
                return Err(invalid("RSC resource ID collision"));
            }
            return ResourceId::from_raw(index).ok_or_else(|| invalid("reserved resource index"));
        }
        let index = u32::try_from(self.dmb.resources.len())
            .map_err(|_| invalid("resource index exceeds u32"))?;
        let typed =
            ResourceId::from_raw(index).ok_or_else(|| invalid("reserved resource index"))?;
        self.dmb.resources.push(ResourceRef {
            id: resource.id,
            kind: resource.kind,
        });
        self.references.insert(key, index);
        self.archive_entries.insert(key, self.archive.len());
        self.archive.push(crate::rsc::Entry::Named(resource));
        Ok(typed)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ProcArgument {
    /// DM `as` type restriction bits.
    pub type_flags: u32,
    /// Low byte identifies a `in` value source; the next byte is its argument.
    pub value_source: u32,
    /// VarID of the declared parameter (whose variable record owns the name).
    pub variable_id: u32,
    /// Zero in all arguments observed in the two DeepQuarry builds.
    pub reserved: u32,
}

pub mod argument_type {
    pub const MOB: u32 = 0x0001;
    pub const OBJ: u32 = 0x0002;
    pub const TEXT: u32 = 0x0004;
    pub const NUM: u32 = 0x0008;
    pub const FILE: u32 = 0x0010;
    pub const TURF: u32 = 0x0020;
    pub const NULL: u32 = 0x0080;
    pub const AREA: u32 = 0x0100;
    pub const ICON: u32 = 0x0200;
    pub const SOUND: u32 = 0x0400;
    pub const MESSAGE: u32 = 0x0800;
    pub const ANYTHING: u32 = 0x1000;
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ClassInitialValue {
    pub variable_id: u32,
    pub value: crate::operands::Value,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ClassBuiltinOverride {
    pub name_string_id: u32,
    pub value: crate::operands::Value,
}

impl ProcArgument {
    pub fn value_source_kind(&self) -> u8 {
        self.value_source as u8
    }
    pub fn value_source_parameter(&self) -> u8 {
        (self.value_source >> 8) as u8
    }
    /// Index into DMB's generated argument-expression procedure table when
    /// the source code's low byte is 0x40 (`arg in expression`).
    pub fn source_expression_index(&self) -> Option<u8> {
        (self.value_source_kind() == 0x40).then(|| self.value_source_parameter())
    }
}

impl Dmb {
    /// Checks the typed cross-table references needed to construct a world.
    /// Generic list contents and bytecode words have context-specific meanings.
    /// Remove unreachable list records and intern identical immutable word arrays.
    /// Call only after all procedure bodies and metadata lists have been finalized.
    /// List words contain values, procedure/variable IDs, or bytecode, never list IDs.
    pub fn compact_lists(&mut self) -> io::Result<usize> {
        self.validate_references()?;
        let old_count = self.lists.len();
        let mut live = vec![false; old_count];
        let mut mark = |id: u32| {
            if id != NONE {
                live[id as usize] = true;
            }
        };
        for class in &self.classes {
            for id in [
                class.verb_list_id(),
                class.proc_list_id(),
                class.initialized_variable_list_id(),
                class.defining_variable_list_id(),
                class.overriding_variable_list_id(),
            ] {
                mark(id);
            }
        }
        for proc in &self.procs {
            for &id in &proc.code_locals_args {
                mark(id);
            }
        }
        for run in &self.grid {
            mark(run.contents);
        }
        mark(self.world.ids[3]);
        mark(self.variable_footer);
        let mut remap = vec![NONE; old_count];
        use std::hash::{Hash, Hasher};
        let mut intern = std::collections::HashMap::<u64, Vec<u32>>::new();
        let mut lists = Vec::new();
        for (old, words) in self.lists.iter().enumerate() {
            if !live[old] {
                continue;
            }
            let mut hasher = std::collections::hash_map::DefaultHasher::new();
            words.hash(&mut hasher);
            let bucket = intern.entry(hasher.finish()).or_default();
            let id = if let Some(&id) = bucket.iter().find(|&&id| lists[id as usize] == *words) {
                id
            } else {
                // 0xffff is NONE even when the table uses 32-bit object IDs.
                if lists.len() == NONE as usize {
                    lists.push(Vec::new());
                }
                let id =
                    u32::try_from(lists.len()).map_err(|_| invalid("list table exceeds u32"))?;
                lists.push(words.clone());
                bucket.push(id);
                id
            };
            remap[old] = id;
        }
        let map = |id: &mut u32| {
            if *id != NONE {
                *id = remap[*id as usize];
            }
        };
        for class in &mut self.classes {
            for index in [0, 1, 3, 4] {
                map(&mut class.lists_and_procs[index]);
            }
            map(&mut class.overrides);
        }
        for proc in &mut self.procs {
            for id in &mut proc.code_locals_args {
                map(id);
            }
        }
        for run in &mut self.grid {
            map(&mut run.contents);
        }
        map(&mut self.world.ids[3]);
        map(&mut self.variable_footer);
        self.lists = lists;
        self.validate_references()?;
        Ok(old_count.saturating_sub(self.lists.len()))
    }

    /// Validate list mutations against an already validated image. The caller
    /// must prove all non-list tables and list count are unchanged. Arbitrary
    /// structural edits require `validate_references` instead.
    pub fn validate_changed_lists(&self, changed: &[u32]) -> io::Result<()> {
        if changed.is_empty() {
            return Ok(());
        }
        let changed: std::collections::HashSet<u32> = changed.iter().copied().collect();
        if changed.iter().any(|&id| id as usize >= self.lists.len()) {
            return Err(invalid("changed list ID out of range"));
        }
        // Class/global payloads have several distinct schemas. These edits are
        // uncommon and keep the complete validator as their correctness gate.
        if changed.contains(&self.variable_footer)
            || changed.contains(&self.world.ids[3])
            || self.classes.iter().any(|class| {
                [
                    class.lists_and_procs[0],
                    class.lists_and_procs[1],
                    class.lists_and_procs[3],
                    class.lists_and_procs[4],
                    class.overrides,
                ]
                .iter()
                .any(|id| changed.contains(id))
            })
        {
            return self.validate_references();
        }
        for (index, proc_) in self.procs.iter().enumerate() {
            if self.is_reserved_proc_slot(index) {
                continue;
            }
            if changed.contains(&proc_.code_locals_args[1]) {
                let locals = self
                    .lists
                    .get(proc_.code_locals_args[1] as usize)
                    .ok_or_else(|| invalid("proc locals list missing"))?;
                if locals
                    .iter()
                    .any(|&id| id != NONE && id as usize >= self.variables.len())
                {
                    return Err(invalid("proc locals list contains invalid VarID"));
                }
            }
            if changed.contains(&proc_.code_locals_args[2]) {
                let arguments = self
                    .proc_arguments(index)
                    .ok_or_else(|| invalid("malformed proc argument list"))?;
                if arguments.iter().any(|arg| {
                    arg.variable_id != NONE && arg.variable_id as usize >= self.variables.len()
                }) {
                    return Err(invalid("proc argument contains invalid VarID"));
                }
                if arguments.iter().any(|arg| {
                    arg.source_expression_index().is_some_and(|reference| {
                        usize::from(reference) >= self.proc_references.len()
                    })
                }) {
                    return Err(invalid("proc argument expression reference out of range"));
                }
            }
        }
        Ok(())
    }

    pub fn validate_references(&self) -> io::Result<()> {
        fn in_table(id: u32, len: usize) -> bool {
            id == NONE || (id as usize) < len
        }
        for (class_index, class) in self.classes.iter().enumerate() {
            if !in_table(class.path_string_id(), self.strings.len())
                || !in_table(class.parent_class_id(), self.classes.len())
                || !in_table(class.name_string_id(), self.strings.len())
                || !in_table(class.description_string_id(), self.strings.len())
                || !in_table(class.icon_resource_id(), self.resources.len())
                || !in_table(class.icon_state_string_id(), self.strings.len())
                || !in_table(class.text, self.strings.len())
                || !in_table(class.maptext, self.strings.len())
                || !in_table(class.suffix, self.strings.len())
                || !in_table(class.lists_and_procs[0], self.lists.len())
                || !in_table(class.lists_and_procs[1], self.lists.len())
                || !in_table(class.lists_and_procs[2], self.procs.len())
                || !in_table(class.lists_and_procs[3], self.lists.len())
                || !in_table(class.lists_and_procs[4], self.lists.len())
                || !in_table(class.overrides, self.lists.len())
            {
                return Err(invalid("class cross-table reference out of range"));
            }
            for list_id in [class.verb_list_id(), class.proc_list_id()] {
                if list_id != NONE
                    && self.lists[list_id as usize]
                        .iter()
                        .any(|&id| !in_table(id, self.procs.len()))
                {
                    return Err(invalid("class procedure list contains invalid ProcID"));
                }
            }
            if class.initialized_variable_list_id() != NONE {
                let values = self
                    .class_initial_values(class_index)
                    .ok_or_else(|| invalid("malformed class initial value list"))?;
                if values
                    .iter()
                    .any(|v| !in_table(v.variable_id, self.variables.len()))
                {
                    return Err(invalid("class initial value has invalid VarID"));
                }
            }
            if class.defining_variable_list_id() != NONE {
                let values = self
                    .class_variable_declarations(class_index)
                    .ok_or_else(|| invalid("malformed class declaration list"))?;
                if values.iter().any(|v| !in_table(v.0, self.variables.len())) {
                    return Err(invalid("class declaration has invalid VarID"));
                }
            }
            if class.overriding_variable_list_id() != NONE {
                let values = self
                    .class_builtin_overrides(class_index)
                    .ok_or_else(|| invalid("malformed class builtin override list"))?;
                if values
                    .iter()
                    .any(|v| !in_table(v.name_string_id, self.strings.len()))
                {
                    return Err(invalid("class builtin override has invalid StringID"));
                }
            }
        }
        for mob in &self.mobs {
            if !in_table(mob.class, self.classes.len()) || !in_table(mob.key, self.strings.len()) {
                return Err(invalid("mob cross-table reference out of range"));
            }
        }
        for (proc_index, proc) in self.procs.iter().enumerate() {
            // Native wide tables reserve the nullable ProcID at FFFF as an
            // empty record. Its list references are absent by construction.
            if self.is_reserved_proc_slot(proc_index) {
                continue;
            }
            if proc_index == NONE as usize
                || (proc.strings == [NONE; 4] && proc.code_locals_args == [NONE; 3])
            {
                return Err(invalid("invalid reserved procedure record"));
            }
            if proc
                .strings
                .iter()
                .any(|&id| !in_table(id, self.strings.len()))
                || proc
                    .code_locals_args
                    .iter()
                    .any(|&id| !in_table(id, self.lists.len()))
            {
                return Err(invalid("proc cross-table reference out of range"));
            }
            let locals = self
                .lists
                .get(proc.code_locals_args[1] as usize)
                .ok_or_else(|| invalid("proc locals list missing"))?;
            if locals.iter().any(|&id| !in_table(id, self.variables.len())) {
                return Err(invalid("proc locals list contains invalid VarID"));
            }
            let arguments = self
                .proc_arguments(proc_index)
                .ok_or_else(|| invalid("malformed proc argument list"))?;
            if arguments
                .iter()
                .any(|arg| !in_table(arg.variable_id, self.variables.len()))
            {
                return Err(invalid("proc argument contains invalid VarID"));
            }
            if arguments.iter().any(|arg| {
                arg.source_expression_index()
                    .is_some_and(|index| usize::from(index) >= self.proc_references.len())
            }) {
                return Err(invalid("proc argument expression reference out of range"));
            }
        }
        for variable in &self.variables {
            if !in_table(variable.name, self.strings.len()) {
                return Err(invalid("variable name out of range"));
            }
        }
        for instance in &self.instances {
            let descriptors = if instance.kind == 8 {
                self.mobs.len()
            } else {
                self.classes.len()
            };
            if !in_table(instance.class, descriptors)
                || !in_table(instance.initializer, self.procs.len())
            {
                return Err(invalid("instance cross-table reference out of range"));
            }
        }
        for run in &self.grid {
            if !in_table(run.turf, self.instances.len())
                || !in_table(run.area, self.instances.len())
                || !in_table(run.contents, self.lists.len())
            {
                return Err(invalid("grid cross-table reference out of range"));
            }
        }
        for object in &self.map_objects {
            if !in_table(object.instance, self.instances.len()) {
                return Err(invalid("map object instance out of range"));
            }
        }
        for &id in &self.proc_references {
            if !in_table(id, self.procs.len()) {
                return Err(invalid("procedure reference out of range"));
            }
        }
        if !in_table(self.variable_footer, self.lists.len()) {
            return Err(invalid("global declaration list out of range"));
        }
        let w = &self.world;
        if !in_table(w.ids[0], self.mobs.len())
            || !in_table(w.ids[1], self.classes.len())
            || !in_table(w.ids[2], self.classes.len())
            || !in_table(w.ids[3], self.lists.len())
            || !in_table(w.ids[4], self.procs.len())
            || !in_table(w.ids[5], self.strings.len())
            || !in_table(w.ids[6], self.strings.len())
            || !in_table(w.client, self.classes.len())
            || !in_table(w.image, self.classes.len())
            || !in_table(w.client_script, self.strings.len())
            || w.client_script_files
                .iter()
                .any(|&id| id as usize >= self.resources.len())
            || !in_table(w.hub_password, self.strings.len())
            || !in_table(w.server_name, self.strings.len())
            || w.command_ids
                .iter()
                .any(|&id| !in_table(id, self.strings.len()))
            || !in_table(w.hub_channel_skin[0], self.strings.len())
            || !in_table(w.hub_channel_skin[1], self.strings.len())
            || !in_table(w.hub_channel_skin[2], self.resources.len())
        {
            return Err(invalid("world cross-table reference out of range"));
        }
        Ok(())
    }
    /// Installs new code for one procedure in a fresh list-table slot.
    /// Existing lists may be shared, so they are never modified in place.
    pub fn replace_proc_code(
        &mut self,
        proc_index: usize,
        instructions: &[crate::bytecode::Instruction],
    ) -> io::Result<()> {
        if proc_index >= self.procs.len() {
            return Err(io::Error::new(
                ErrorKind::InvalidInput,
                "proc index out of range",
            ));
        }
        let words = crate::bytecode::encode(instructions);
        if words.len() > u16::MAX as usize {
            return Err(io::Error::new(
                ErrorKind::InvalidInput,
                "procedure code exceeds list limit",
            ));
        }
        crate::bytecode::decode(&words)
            .map_err(|error| io::Error::new(ErrorKind::InvalidInput, error.reason))?;
        if self.lists.len() == NONE as usize {
            self.lists.push(Vec::new());
        }
        let list_id =
            u32::try_from(self.lists.len()).map_err(|_| invalid("list ID exceeds u32"))?;
        self.lists.push(words);
        self.procs[proc_index].code_locals_args[0] = list_id;
        if self.lists.len() > u16::MAX as usize {
            self.header.flags |= 0x4000_0000;
        }
        Ok(())
    }

    pub fn string(&self, id: u32) -> Option<&[u8]> {
        self.strings
            .get(id as usize)
            .map(|entry| entry.data.as_slice())
    }

    /// Whether this is the exact nullable ProcID record reserved by native wide tables.
    pub fn is_reserved_proc_slot(&self, index: usize) -> bool {
        self.procs.get(index).is_some_and(|proc| {
            index == NONE as usize
                && proc.strings == [NONE; 4]
                && proc.source_parameter == 255
                && proc.source_kind == 0
                && proc.flags == 4
                && proc.extended_flags.is_none()
                && proc.code_locals_args == [NONE; 3]
        })
    }

    pub fn proc_code_words(&self, proc_index: usize) -> Option<&[u32]> {
        if self.is_reserved_proc_slot(proc_index) {
            return None;
        }
        let list_id = self.procs.get(proc_index)?.code_locals_args[0];
        self.lists.get(list_id as usize).map(Vec::as_slice)
    }

    pub fn proc_arguments(&self, proc_index: usize) -> Option<Vec<ProcArgument>> {
        if self.is_reserved_proc_slot(proc_index) {
            return None;
        }
        let list_id = self.procs.get(proc_index)?.code_locals_args[2];
        let words = self.lists.get(list_id as usize)?;
        if words.len() % 4 != 0 {
            return None;
        }
        Some(
            words
                .chunks_exact(4)
                .map(|arg| ProcArgument {
                    type_flags: arg[0],
                    value_source: arg[1],
                    variable_id: arg[2],
                    reserved: arg[3],
                })
                .collect(),
        )
    }

    pub fn argument_source_proc_id(&self, argument: &ProcArgument) -> Option<u32> {
        self.proc_references
            .get(usize::from(argument.source_expression_index()?))
            .copied()
    }

    /// Variable IDs and declaration flags defined on this class itself.
    /// Inherited declarations are stored on parent classes.
    pub fn class_variable_declarations(&self, class_index: usize) -> Option<Vec<(u32, u32)>> {
        let list_id = self.classes.get(class_index)?.defining_variable_list_id();
        if list_id == NONE {
            return None;
        }
        let words = self.lists.get(list_id as usize)?;
        if words.len() % 2 != 0 {
            return None;
        }
        Some(
            words
                .chunks_exact(2)
                .map(|pair| (pair[0], pair[1]))
                .collect(),
        )
    }

    /// Initial variable assignments attached to this class. Each entry is a
    /// variable ID followed by the same tagged value used in bytecode.
    pub fn class_initial_values(&self, class_index: usize) -> Option<Vec<ClassInitialValue>> {
        let list_id = self
            .classes
            .get(class_index)?
            .initialized_variable_list_id();
        if list_id == NONE {
            return None;
        }
        let words = self.lists.get(list_id as usize)?;
        let mut result = Vec::new();
        let mut at = 0usize;
        while at < words.len() {
            let variable_id = *words.get(at)?;
            let (value, len) = crate::operands::Value::decode(&words[at + 1..]).ok()?;
            result.push(ClassInitialValue { variable_id, value });
            at += len + 1;
        }
        Some(result)
    }

    /// Builtin properties without dedicated class fields. The key is a
    /// StringID, followed by the same tagged value representation as above.
    pub fn class_builtin_overrides(&self, class_index: usize) -> Option<Vec<ClassBuiltinOverride>> {
        let list_id = self.classes.get(class_index)?.overriding_variable_list_id();
        if list_id == NONE {
            return None;
        }
        let words = self.lists.get(list_id as usize)?;
        let mut result = Vec::new();
        let mut at = 0usize;
        while at < words.len() {
            let name_string_id = *words.get(at)?;
            let (value, len) = crate::operands::Value::decode(&words[at + 1..]).ok()?;
            result.push(ClassBuiltinOverride {
                name_string_id,
                value,
            });
            at += len + 1;
        }
        Some(result)
    }

    /// Global variable declaration flags: 1 = global, 2 = const.
    pub fn global_variable_flags(&self) -> Option<Vec<(u32, u32)>> {
        let words = self.lists.get(self.variable_footer as usize)?;
        if words.len() % 2 != 0 {
            return None;
        }
        Some(
            words
                .chunks_exact(2)
                .map(|pair| (pair[0], pair[1]))
                .collect(),
        )
    }

    /// Finds DMB cache-file references absent from the parsed RSC archive.
    pub fn missing_resources(&self, archive: &[crate::rsc::Entry]) -> Vec<ResourceRef> {
        let present: HashSet<(u32, u8)> = archive
            .iter()
            .filter_map(|entry| match entry {
                crate::rsc::Entry::Named(resource) => Some((resource.id, resource.kind)),
                crate::rsc::Entry::Opaque { .. } => None,
            })
            .collect();
        self.resources
            .iter()
            .filter(|resource| !present.contains(&(resource.id, resource.kind)))
            .cloned()
            .collect()
    }

    /// Reads a BYOND 516 DMB. Older or newer versions must be implemented
    /// deliberately; their version-gated field layouts differ.
    pub fn from_bytes(data: &[u8]) -> io::Result<Self> {
        Self::from_bytes_with_list_spans(data).map(|(dmb, _)| dmb)
    }

    /// Decode while recording exact serialized list records. List words use
    /// object-width encoding and have no position-dependent cipher or offsets.
    pub fn from_bytes_with_list_spans(
        data: &[u8],
    ) -> io::Result<(Self, Vec<std::ops::Range<usize>>)> {
        let mut r = Reader {
            data,
            at: 0,
            object_size: 4,
            compatibility_version: 516,
        };
        let first_line = r.line()?;
        let (executor_line, version_line) = if first_line.starts_with(b"#!") {
            let mut prefix = first_line;
            loop {
                let line = r.line()?;
                if line == b"world bin v516\n" && r.data[r.at..].starts_with(b"min compatibility v")
                {
                    break (Some(prefix), line);
                }
                prefix.extend_from_slice(&line);
            }
        } else {
            (None, first_line)
        };
        let compatibility_line = r.line()?;
        if version_line != b"world bin v516\n"
            || !compatibility_line.starts_with(b"min compatibility v")
        {
            return Err(invalid("only BYOND v516 is supported"));
        }
        let flags = r.u32()?;
        let extended_flags = (flags & 0x8000_0000 != 0).then(|| r.u32()).transpose()?;
        r.object_size = if flags & 0x4000_0000 != 0 { 4 } else { 2 };
        r.compatibility_version = compatibility_version(&compatibility_line)?;
        let header = Header {
            executor_line,
            version_line,
            compatibility_line,
            flags,
            extended_flags,
        };
        let dimensions = [r.u16()?, r.u16()?, r.u16()?];
        let cell_count = dimensions
            .iter()
            .try_fold(1usize, |a, &b| a.checked_mul(usize::from(b)))
            .ok_or_else(|| invalid("grid dimensions overflow"))?;
        let mut grid = Vec::new();
        let mut covered = 0usize;
        while covered < cell_count {
            let run = GridRun {
                turf: r.object()?,
                area: r.object()?,
                contents: r.object()?,
                copies: r.u8()?,
            };
            if run.copies == 0 {
                return Err(invalid("zero-length grid run"));
            }
            covered += usize::from(run.copies);
            if covered > cell_count {
                return Err(invalid("grid runs exceed map dimensions"));
            }
            grid.push(run);
        }
        let expected_string_bytes = r.u32()? as usize;
        let classes = r.table(Class::read)?;
        let mobs = r.table(MobType::read)?;
        let string_count = r.object()? as usize;
        let mut strings = Vec::new();
        let mut string_bytes = 0usize;
        let mut string_hash = u32::MAX;
        // Executor text is outside the position-based string cipher's origin.
        let string_origin = header.executor_line.as_ref().map_or(0, Vec::len);
        for _ in 0..string_count {
            let mut len = 0usize;
            let mut long_chunks = 0u16;
            loop {
                let offset = r.at - string_origin;
                let chunk = r.u16()? ^ offset as u16;
                len = len
                    .checked_add(usize::from(chunk))
                    .ok_or_else(|| invalid("string length overflow"))?;
                if chunk != u16::MAX {
                    break;
                }
                long_chunks = long_chunks
                    .checked_add(1)
                    .ok_or_else(|| invalid("too many string length chunks"))?;
                if len == expected_string_bytes {
                    break;
                }
            }
            let start = r.at - string_origin;
            let mut data = r.take(len)?.to_vec();
            crypt_string(&mut data, start);
            string_hash = nqcrc(string_hash, &data);
            string_hash = nqcrc(string_hash, &[0]);
            string_bytes = string_bytes
                .checked_add(len + 1)
                .ok_or_else(|| invalid("string byte count overflow"))?;
            strings.push(DmString { data, long_chunks });
        }
        if string_bytes != expected_string_bytes {
            return Err(invalid("string byte count mismatch"));
        }
        if r.u32()? != string_hash {
            return Err(invalid("string table checksum mismatch"));
        }
        let mut list_spans = Vec::new();
        let lists = r.table(|r| {
            let start = r.at;
            let count = r.u16()? as usize;
            let mut list = Vec::with_capacity(count);
            for _ in 0..count {
                list.push(r.object()?);
            }
            list_spans.push(start..r.at);
            Ok(list)
        })?;
        let procs = r.table(Proc::read)?;
        let variables = r.table(|r| {
            Ok(Variable {
                kind: r.u8()?,
                value: r.u32()?,
                name: r.object()?,
            })
        })?;
        let variable_footer = r.u32()?;
        let proc_references = r.table(|r| r.object())?;
        let instances = r.table(|r| {
            Ok(Instance {
                kind: r.u8()?,
                class: r.u32()?,
                initializer: r.object()?,
            })
        })?;
        let map_object_count = r.u32()? as usize;
        let mut map_objects = Vec::with_capacity(map_object_count);
        for _ in 0..map_object_count {
            map_objects.push(MapObject {
                offset: r.u16()?,
                instance: r.object()?,
            });
        }
        let world = World::read(&mut r)?;
        let resources = r.table(|r| {
            Ok(ResourceRef {
                id: r.u32()?,
                kind: r.u8()?,
            })
        })?;
        if r.at != data.len() {
            return Err(invalid("trailing DMB bytes"));
        }
        Ok((
            Self {
                header,
                dimensions,
                grid,
                classes,
                mobs,
                strings,
                lists,
                procs,
                variables,
                variable_footer,
                proc_references,
                instances,
                map_objects,
                world,
                resources,
            },
            list_spans,
        ))
    }

    /// Serializes decoded v516 records, recomputing string offsets and checksum.
    pub fn to_bytes(&self) -> io::Result<Vec<u8>> {
        self.to_bytes_with_list_spans().map(|(bytes, _)| bytes)
    }

    /// Serialize and produce the exact list-record index in the same pass.
    pub fn to_bytes_with_list_spans(&self) -> io::Result<(Vec<u8>, Vec<std::ops::Range<usize>>)> {
        if self.header.version_line != b"world bin v516\n"
            || !self
                .header
                .compatibility_line
                .starts_with(b"min compatibility v")
            || !self.header.compatibility_line.ends_with(b"\n")
            || self
                .header
                .compatibility_line
                .iter()
                .filter(|&&byte| byte == b'\n')
                .count()
                != 1
            || (self.header.flags & 0x8000_0000 != 0) != self.header.extended_flags.is_some()
        {
            return Err(invalid("unsupported DMB header"));
        }
        self.validate_references()?;
        let cells = self
            .dimensions
            .iter()
            .try_fold(1usize, |product, &value| {
                product.checked_mul(usize::from(value))
            })
            .ok_or_else(|| invalid("grid dimensions overflow"))?;
        let mut covered = 0usize;
        for run in &self.grid {
            if run.copies == 0 {
                return Err(invalid("zero-length grid run"));
            }
            covered = covered
                .checked_add(usize::from(run.copies))
                .ok_or_else(|| invalid("grid run count overflow"))?;
        }
        if covered != cells {
            return Err(invalid("grid runs do not cover map dimensions"));
        }
        if self.lists.iter().any(|list| list.len() > u16::MAX as usize) {
            return Err(invalid("list exceeds u16 element count"));
        }
        if self.world.client_script_files.len() > u16::MAX as usize {
            return Err(invalid("client script file list exceeds u16 count"));
        }
        if compatibility_version(&self.header.compatibility_line)? <= 514
            && self.world.savefile_byond_version != 0
        {
            return Err(invalid(
                "savefile version has no field at this compatibility level",
            ));
        }
        for class in &self.classes {
            if (class.interface == 15) != class.extended_interface.is_some()
                || (class.transform_flag != 0) != class.transform.is_some()
                || (class.color_matrix_flag != 0) != class.color_matrix.is_some()
            {
                return Err(invalid("class presence flag disagrees with data"));
            }
        }
        if self
            .mobs
            .iter()
            .any(|mob| (mob.sight & 0x80 != 0) != mob.extended_sight.is_some())
        {
            return Err(invalid("mob sight flag disagrees with data"));
        }
        if self
            .procs
            .iter()
            .any(|proc| (proc.flags & 0x80 != 0) != proc.extended_flags.is_some())
        {
            return Err(invalid("proc flag disagrees with data"));
        }
        let mut w = Writer::new(
            if self.header.flags & 0x4000_0000 != 0 {
                4
            } else {
                2
            },
            compatibility_version(&self.header.compatibility_line)?,
        );
        if let Some(line) = &self.header.executor_line {
            // Native world.executor text may contain newlines. The reader stops
            // at a version line followed by a compatibility line, so reject
            // that ambiguous sentinel rather than valid multiline text.
            if !line.starts_with(b"#!")
                || !line.ends_with(b"\n")
                || line
                    .windows(b"\nworld bin v516\nmin compatibility v".len())
                    .any(|part| part == b"\nworld bin v516\nmin compatibility v")
            {
                return Err(invalid("invalid executor shebang"));
            }
            w.raw(line);
        }
        w.raw(&self.header.version_line);
        w.raw(&self.header.compatibility_line);
        w.u32(self.header.flags);
        if let Some(flags) = self.header.extended_flags {
            w.u32(flags);
        }
        for value in self.dimensions {
            w.u16(value);
        }
        for run in &self.grid {
            w.object(run.turf);
            w.object(run.area);
            w.object(run.contents);
            w.u8(run.copies);
        }
        let total_string_bytes = self.strings.iter().try_fold(0usize, |sum, string| {
            sum.checked_add(string.data.len() + 1)
                .ok_or_else(|| invalid("string total overflow"))
        })?;
        w.u32(u32::try_from(total_string_bytes).map_err(|_| invalid("string total exceeds u32"))?);
        w.table(&self.classes, |w, item| item.write(w))?;
        w.table(&self.mobs, |w, item| item.write(w))?;
        w.object(
            u32::try_from(self.strings.len()).map_err(|_| invalid("string count exceeds u32"))?,
        );
        let mut string_hash = u32::MAX;
        let string_origin = self.header.executor_line.as_ref().map_or(0, Vec::len);
        for string in &self.strings {
            let mut remaining = string.data.len();
            for _ in 0..string.long_chunks {
                let offset = w.at() - string_origin;
                w.u16(u16::MAX ^ offset as u16);
                remaining = remaining
                    .checked_sub(u16::MAX as usize)
                    .ok_or_else(|| invalid("invalid long string chunks"))?;
            }
            if remaining >= u16::MAX as usize {
                return Err(invalid("string needs additional length chunks"));
            }
            let offset = w.at() - string_origin;
            w.u16((remaining as u16) ^ offset as u16);
            let offset = w.at() - string_origin;
            let mut encrypted = string.data.clone();
            crypt_string(&mut encrypted, offset);
            w.raw(&encrypted);
            string_hash = nqcrc(string_hash, &string.data);
            string_hash = nqcrc(string_hash, &[0]);
        }
        w.u32(string_hash);
        let mut list_spans = Vec::with_capacity(self.lists.len());
        w.table(&self.lists, |w, list| {
            let start = w.at();
            w.u16(list.len() as u16);
            for &value in list {
                w.object(value);
            }
            list_spans.push(start..w.at());
        })?;
        w.table(&self.procs, |w, item| item.write(w))?;
        w.table(&self.variables, |w, item| {
            w.u8(item.kind);
            w.u32(item.value);
            w.object(item.name);
        })?;
        w.u32(self.variable_footer);
        w.table(&self.proc_references, |w, value| w.object(*value))?;
        w.table(&self.instances, |w, item| {
            w.u8(item.kind);
            w.u32(item.class);
            w.object(item.initializer);
        })?;
        w.u32(
            u32::try_from(self.map_objects.len())
                .map_err(|_| invalid("map object count exceeds u32"))?,
        );
        for item in &self.map_objects {
            w.u16(item.offset);
            w.object(item.instance);
        }
        self.world.write(&mut w);
        w.table(&self.resources, |w, item| {
            w.u32(item.id);
            w.u8(item.kind);
        })?;
        if w.object_overflow {
            return Err(invalid("object ID exceeds selected 16-bit width"));
        }
        Ok((w.bytes, list_spans))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rsc::{Entry, NamedResource};

    #[test]
    fn writer_rejects_unterminated_and_multiline_header_fields() {
        for line in [
            b"min compatibility v516 516".as_slice(),
            b"min compatibility v516 516\nextra\n",
        ] {
            let mut dmb =
                Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
            dmb.header.compatibility_line = line.to_vec();
            assert!(dmb.to_bytes().is_err());
        }
        let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        dmb.header.executor_line = Some(b"#!/usr/bin/env DreamDaemon".to_vec());
        assert!(dmb.to_bytes().is_err());
        dmb.header.executor_line =
            Some(b"#!cmd\nworld bin v516\nmin compatibility v516 516\n".to_vec());
        assert!(dmb.to_bytes().is_err());
    }

    #[test]
    fn native_wide_proc_reserved_record_is_the_only_blank_exception() {
        let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let filler = dmb.procs[0].clone();
        dmb.procs.resize(0x10000, filler);
        let blank = Proc {
            strings: [0xffff; 4],
            source_parameter: 255,
            source_kind: 0,
            flags: 4,
            extended_flags: None,
            code_locals_args: [0xffff; 3],
        };
        dmb.procs[0xffff] = blank.clone();
        assert!(dmb.is_reserved_proc_slot(0xffff));
        assert!(!dmb.is_reserved_proc_slot(0x10000));
        dmb.lists.resize(0x10000, Vec::new());
        dmb.lists[0xffff] = vec![0, 0, 0, 0];
        assert!(dmb.proc_code_words(0xffff).is_none());
        assert!(dmb.proc_arguments(0xffff).is_none());
        dmb.validate_references().unwrap();
        dmb.procs[0xffff].flags = 0;
        assert!(!dmb.is_reserved_proc_slot(0xffff));
        assert!(dmb.validate_references().is_err());
        dmb.procs[0xffff] = blank.clone();
        dmb.procs[0xfffe] = blank;
        assert!(!dmb.is_reserved_proc_slot(0xfffe));
        assert!(dmb.validate_references().is_err());
    }

    #[test]
    fn finalized_list_compaction_preserves_semantics_and_roundtrip() {
        let mut dmb = Dmb::from_bytes(include_bytes!(
            "../fixtures/translation/builtin_next.native.bin"
        ))
        .unwrap();
        let before = dmb.clone();
        // A duplicate live procedure body plus an unreachable construction snapshot.
        let old = dmb.procs[0].code_locals_args[0];
        let duplicate = dmb.lists.len() as u32;
        dmb.lists.push(dmb.lists[old as usize].clone());
        dmb.procs[0].code_locals_args[0] = duplicate;
        dmb.lists.push(vec![0xdead_beef]);
        assert!(dmb.compact_lists().unwrap() >= 2);
        assert!(crate::compare::compare_dmbs(&before, &dmb, &Default::default()).is_empty());
        assert!(crate::compare::compare_maps(&before, &dmb, 100).is_empty());
        for index in 0..before.procs.len() {
            assert_eq!(before.proc_code_words(index), dmb.proc_code_words(index));
        }
        let encoded = dmb.to_bytes().unwrap();
        let decoded = Dmb::from_bytes(&encoded).unwrap();
        assert_eq!(decoded.to_bytes().unwrap(), encoded);
        assert_eq!(dmb.compact_lists().unwrap(), 0);
    }

    #[test]
    fn list_compaction_keeps_none_reserved_above_u16() {
        let mut dmb = minimal();
        dmb.lists = (0..65_538).map(|i| vec![i]).collect();
        dmb.grid = (0..65_538)
            .filter(|&i| i != 0xffff)
            .map(|i| GridRun {
                turf: 0xffff,
                area: 0xffff,
                contents: i,
                copies: 1,
            })
            .collect();
        let words: Vec<_> = dmb
            .grid
            .iter()
            .map(|run| dmb.lists[run.contents as usize].clone())
            .collect();
        dmb.compact_lists().unwrap();
        assert_eq!(dmb.world.ids[3], 0xffff);
        assert_eq!(dmb.variable_footer, 0xffff);
        assert!(dmb.lists.len() > 65_535);
        assert!(dmb.lists[65_535].is_empty());
        for (run, expected) in dmb.grid.iter().zip(words) {
            assert_ne!(run.contents, 0xffff);
            assert_eq!(dmb.lists[run.contents as usize], expected);
        }
    }

    #[test]
    fn optional_class_list_ids_do_not_resolve_list_65535() {
        let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let class_id = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(b"/alist"))
            .unwrap();
        assert_eq!(dmb.classes[class_id].defining_variable_list_id(), 0xffff);
        assert_eq!(dmb.classes[class_id].initialized_variable_list_id(), 0xffff);
        assert_eq!(dmb.classes[class_id].overriding_variable_list_id(), 0xffff);
        dmb.lists.resize(65_536, Vec::new());
        dmb.lists[65_535] = vec![0, 0];
        assert_eq!(dmb.class_variable_declarations(class_id), None);
        assert_eq!(dmb.class_initial_values(class_id), None);
        assert_eq!(dmb.class_builtin_overrides(class_id), None);
    }

    fn minimal() -> Dmb {
        Dmb {
            header: Header {
                executor_line: None,
                version_line: b"world bin v516\n".to_vec(),
                compatibility_line: b"min compatibility v516 516\n".to_vec(),
                flags: 0x4000_0000,
                extended_flags: None,
            },
            dimensions: [1, 1, 1],
            grid: vec![GridRun {
                turf: 0xffff,
                area: 0xffff,
                contents: 0xffff,
                copies: 1,
            }],
            classes: vec![],
            mobs: vec![],
            strings: vec![DmString {
                data: b"hello".to_vec(),
                long_chunks: 0,
            }],
            lists: vec![vec![0, 42]],
            procs: vec![],
            variables: vec![],
            variable_footer: 0xffff,
            proc_references: vec![],
            instances: vec![],
            map_objects: vec![],
            world: World {
                ids: [0xffff; 7],
                tick_lag: 10,
                client: 0xffff,
                image: 0xffff,
                savefile_byond_version: 0,
                eye: 0,
                direction: 2,
                control: 0,
                unknown_byte: 0,
                client_script: 0xffff,
                client_script_files: vec![],
                view_dimensions: 0x0b0b,
                hub_password: 0xffff,
                server_name: 0xffff,
                hub_number: 0,
                version: 0,
                cache_lifespan: 0,
                command_ids: [0xffff; 2],
                hub_channel_skin: [0xffff; 3],
                icon_dimensions_format: [32, 32, 0],
            },
            resources: vec![ResourceRef { id: 23, kind: 6 }],
        }
    }

    #[test]
    fn list_delta_validator_checks_affected_local_and_argument_schemas() {
        let mut dmb = minimal();
        dmb.variables.push(Variable {
            kind: 0,
            value: 0,
            name: 0,
        });
        dmb.lists.extend([vec![0], Vec::new()]);
        dmb.procs.push(Proc {
            strings: [0; 4],
            source_parameter: 0,
            source_kind: 0,
            flags: 0,
            extended_flags: None,
            code_locals_args: [0, 1, 2],
        });
        dmb.validate_references().unwrap();
        dmb.lists[0] = vec![0, 42, 0];
        dmb.validate_changed_lists(&[0]).unwrap();
        dmb.lists[1] = vec![1];
        assert!(dmb.validate_changed_lists(&[1]).is_err());
        assert!(dmb.validate_references().is_err());
        dmb.lists[1] = vec![0];
        dmb.lists[2] = vec![7];
        assert!(dmb.validate_changed_lists(&[2]).is_err());
        assert!(dmb.validate_changed_lists(&[u32::MAX]).is_err());
        dmb.lists[2].clear();
        dmb.validate_changed_lists(&[0, 1, 2]).unwrap();
        dmb.validate_references().unwrap();
    }

    #[test]
    fn string_change_reencodes_offsets_and_checksum() {
        let mut dmb = minimal();
        let original = dmb.to_bytes().unwrap();
        assert_eq!(Dmb::from_bytes(&original).unwrap(), dmb);
        dmb.strings[0].data = b"a longer string".to_vec();
        let changed = dmb.to_bytes().unwrap();
        assert_ne!(changed, original);
        assert_eq!(Dmb::from_bytes(&changed).unwrap(), dmb);
    }

    #[test]
    fn narrow_object_ids_roundtrip_and_reject_overflow() {
        let mut dmb = minimal();
        dmb.header.flags &= !0x4000_0000;
        dmb.header.compatibility_line = b"min compatibility v516 468\n".to_vec();
        let encoded = dmb.to_bytes().unwrap();
        assert_eq!(Dmb::from_bytes(&encoded).unwrap(), dmb);
        dmb.grid[0].turf = 0x1_0000;
        assert!(dmb.to_bytes().is_err());
    }

    #[test]
    fn compatibility_514_omits_savefile_version() {
        let mut dmb = minimal();
        dmb.header.flags &= !0x4000_0000;
        dmb.header.compatibility_line = b"min compatibility v514 468\n".to_vec();
        let bytes = dmb.to_bytes().unwrap();
        assert_eq!(Dmb::from_bytes(&bytes).unwrap(), dmb);
    }

    #[test]
    fn world_view_dimensions_match_dm_order() {
        let mut world = minimal().world;
        world.set_view_size(9, 13);
        assert_eq!(world.view_dimensions, 0x090d);
        assert_eq!(world.view_size(), (9, 13));
    }

    #[test]
    fn extended_header_word_round_trips() {
        let mut dmb = minimal();
        assert_eq!(dmb.header.movement_mode_setting(), Some(0));
        dmb.header.flags |= 0x8000_0000;
        dmb.header.extended_flags = Some(0x1234_567c);
        assert_eq!(dmb.header.movement_mode_setting(), None);
        let encoded = dmb.to_bytes().unwrap();
        assert_eq!(Dmb::from_bytes(&encoded).unwrap(), dmb);
        dmb.header.extended_flags = None;
        assert!(dmb.to_bytes().is_err());
    }

    #[test]
    fn declaration_and_argument_lists_decode_without_losing_raw_words() {
        let mut dmb = minimal();
        dmb.strings.push(DmString {
            data: b"target".to_vec(),
            long_chunks: 0,
        });
        dmb.variables.push(Variable {
            kind: 0,
            value: 0,
            name: 1,
        });
        dmb.lists.push(vec![0, 5]);
        let declarations = (dmb.lists.len() - 1) as u32;
        dmb.classes.push(Class {
            initial_ids: [0; 6],
            direction: 2,
            interface: 1,
            extended_interface: None,
            text: 0xffff,
            maptext: 0xffff,
            maptext_geometry: [0; 4],
            suffix: 0xffff,
            flags: 4,
            lists_and_procs: [0xffff, 0xffff, 0xffff, 0xffff, declarations, 0xffff],
            layer_bits: 0,
            transform_flag: 0,
            transform: None,
            color_matrix_flag: 0,
            color_matrix: None,
            overrides: 0xffff,
        });
        assert_eq!(dmb.class_variable_declarations(0), Some(vec![(0, 5)]));
        dmb.lists.push(vec![8, 0x7d01, 0, 0]);
        let args = (dmb.lists.len() - 1) as u32;
        dmb.procs.push(Proc {
            strings: [0; 4],
            source_parameter: 0,
            source_kind: 0,
            flags: 0,
            extended_flags: None,
            code_locals_args: [0xffff, 0xffff, args],
        });
        let decoded = dmb.proc_arguments(0).unwrap();
        assert_eq!(decoded.len(), 1);
        assert_eq!(decoded[0].value_source_kind(), 1);
        assert_eq!(decoded[0].value_source_parameter(), 125);
        assert_eq!(decoded[0].variable_id, 0);
        let source = ProcArgument {
            value_source: 0x140,
            ..decoded[0]
        };
        assert_eq!(source.source_expression_index(), Some(1));
        dmb.proc_references = vec![0, 7];
        assert_eq!(dmb.argument_source_proc_id(&source), Some(7));
    }

    #[test]
    fn extended_proc_flags_match_compiler_settings() {
        let proc = Proc {
            strings: [0; 4],
            source_parameter: 0,
            source_kind: 0,
            flags: 0x80,
            extended_flags: Some((0x285, 0)),
            code_locals_args: [0; 3],
        };
        assert!(proc.is_hidden());
        assert!(proc.is_instant());
        assert!(proc.waits_for_completion());
        assert!(!proc.runs_in_background());
        assert_eq!(proc.invisibility_setting(), None);
        let mut proc = proc;
        proc.extended_flags = Some((0x9c, 42));
        assert_eq!(proc.invisibility_setting(), Some(42));
        proc.extended_flags = Some((0x8c, 255));
        assert_eq!(proc.invisibility_setting(), Some(0));
        proc.source_kind = 1;
        proc.source_parameter = 5;
        assert_eq!(proc.source_location(), ProcSource::InView(5));
    }

    #[test]
    fn extended_mob_sight_keeps_setting_bytes_distinct_from_flags() {
        let mob = MobType {
            class: 0,
            key: 0xffff,
            sight: 0x80,
            extended_sight: Some((0x10084, 12, 42)),
        };
        assert_eq!(
            mob.sight_bits(),
            mob_sight::SEE_INFRARED | mob_sight::SEE_MOBS
        );
        assert_eq!(mob.see_in_dark_setting(), Some(12));
        assert_eq!(mob.see_invisible_setting(), Some(42));
    }

    #[test]
    fn appearance_flags_occupy_high_class_flag_bits() {
        let mut class = Class {
            initial_ids: [0; 6],
            direction: 2,
            interface: 1,
            extended_interface: None,
            text: 0xffff,
            maptext: 0xffff,
            maptext_geometry: [0; 4],
            suffix: 0xffff,
            flags: 0x6430_4804,
            lists_and_procs: [0xffff; 6],
            layer_bits: 0,
            transform_flag: 0,
            transform: None,
            color_matrix_flag: 0,
            color_matrix: None,
            overrides: 0xffff,
        };
        assert_eq!(class.appearance_flags(), 0x321);
        assert_eq!(class.native_interface(), ClassInterface::Regular);
        assert!(!class.is_dense());
        assert!(!class.is_opaque());
        assert_eq!(class.gender_code(), 0);
        assert_eq!(class.mouse_opacity(), 1);
        assert!(class.is_normally_visible());
        assert!(class.has_mouse_event_proc());
        assert!(!class.has_mouse_move_proc());
        assert!(class.has_mouse_wheel_proc());
        assert_eq!(class.animate_movement(), 2);
        class.set_opaque(true);
        assert!(class.is_opaque());
        class.set_opaque(false);
        class.set_dense(true);
        assert!(class.is_dense());
        class.set_dense(false);
        class.set_gender_code(2).unwrap();
        assert_eq!(class.gender_code(), 2);
        class.set_gender_code(0).unwrap();
        class.set_mouse_opacity(0).unwrap();
        assert_eq!(class.mouse_opacity(), 0);
        class.set_mouse_opacity(1).unwrap();
        class.set_luminosity(7).unwrap();
        assert_eq!(class.luminosity(), 7);
        class.set_luminosity(0).unwrap();
        class.set_animate_movement(0).unwrap();
        assert_eq!(class.animate_movement(), 0);
        class.set_animate_movement(2).unwrap();
        class.set_appearance_flags(0x100);
        assert_eq!(class.flags, 0x2010_4804);
    }

    #[test]
    fn resource_refs_match_archive_id_and_kind() {
        let dmb = minimal();
        let archive = [Entry::Named(NamedResource {
            kind: 6,
            id: 23,
            timestamp: 0,
            source_timestamp: 0,
            declared_size: 0,
            name: b"icon.png".to_vec(),
            data: vec![],
        })];
        assert!(dmb.missing_resources(&archive).is_empty());
        assert_eq!(dmb.missing_resources(&[]), dmb.resources);
        assert_eq!(
            ResourceLookup::new(&archive)
                .get(&dmb, ResourceId::from_raw(0).unwrap())
                .unwrap()
                .name,
            b"icon.png"
        );
    }

    #[test]
    fn writer_rejects_dangling_cross_table_reference() {
        let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        dmb.validate_references().unwrap();
        dmb.classes[0].lists_and_procs[2] = dmb.procs.len() as u32 + 1;
        assert_eq!(dmb.to_bytes().unwrap_err().kind(), ErrorKind::InvalidData);
    }

    #[test]
    fn attach_resource_writes_matching_dmb_and_rsc_entries() {
        let mut dmb = minimal();
        let mut archive = Vec::new();
        let resource =
            NamedResource::from_data(6, b"new.png".to_vec(), b"abc".to_vec(), 0, 0).unwrap();
        let index = {
            let mut batch = ResourceAttachment::new(&mut dmb, &mut archive);
            let index = batch.attach(resource.clone()).unwrap();
            assert_eq!(batch.attach(resource.clone()).unwrap(), index);
            index
        };
        assert_eq!(index.raw(), 1);
        assert_eq!(
            ResourceLookup::new(&archive).get(&dmb, index),
            Some(&resource)
        );
        assert_eq!(archive.len(), 1);
    }

    #[test]
    fn indexed_resource_batch_reuses_entries() {
        let mut dmb = minimal();
        let mut archive = Vec::new();
        let first =
            NamedResource::from_data(6, b"one.txt".to_vec(), b"one".to_vec(), 0, 0).unwrap();
        let second =
            NamedResource::from_data(6, b"two.txt".to_vec(), b"two".to_vec(), 0, 0).unwrap();
        let (first_id, second_id) = {
            let mut batch = ResourceAttachment::new(&mut dmb, &mut archive);
            let first_id = batch.attach(first.clone()).unwrap();
            let second_id = batch.attach(second.clone()).unwrap();
            assert_eq!(batch.attach(first.clone()).unwrap(), first_id);
            (first_id, second_id)
        };
        assert_eq!(archive.len(), 2);
        let lookup = ResourceLookup::new(&archive);
        assert_eq!(lookup.get(&dmb, first_id), Some(&first));
        assert_eq!(lookup.get(&dmb, second_id), Some(&second));
    }

    #[test]
    fn code_edit_uses_a_fresh_list_slot() {
        let mut dmb = minimal();
        // The raw list under test is not a procedure locals/arguments table.
        let empty_list = dmb.lists.len() as u32;
        dmb.lists.push(Vec::new());
        dmb.procs.push(Proc {
            strings: [0; 4],
            source_parameter: 0,
            source_kind: 0,
            flags: 0,
            extended_flags: None,
            code_locals_args: [0, empty_list, empty_list],
        });
        let old_list = dmb.lists[0].clone();
        let instructions = crate::bytecode::decode(&[0x50, 7, 0]).unwrap();
        dmb.replace_proc_code(0, &instructions).unwrap();
        assert_eq!(dmb.lists[0], old_list);
        assert_eq!(dmb.proc_code_words(0).unwrap(), [0x50, 7, 0]);
        let reparsed = Dmb::from_bytes(&dmb.to_bytes().unwrap()).unwrap();
        assert_eq!(reparsed.proc_code_words(0).unwrap(), [0x50, 7, 0]);
    }
}
