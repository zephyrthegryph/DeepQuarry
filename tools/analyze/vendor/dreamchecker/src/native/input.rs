//! What the native checker reads besides its [`Model`](super::model::Model): each proc body as the compiler front end's typed
//! statements (`dm_syntax::Statement`, offsets in the front end's expanded text) and a [`Site`] that places an offset where
//! SpacemanDMM places the token there.
use std::ops::Range;

use dm::Location;

/// `as mob|obj` input types (SpacemanDMM's `InputType` bits).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct InputType(pub u32);

impl InputType {
    pub const MOB: u32 = 1 << 0;
    pub const OBJ: u32 = 1 << 1;
    pub const TEXT: u32 = 1 << 2;
    pub const NUM: u32 = 1 << 3;
    pub const FILE: u32 = 1 << 4;
    pub const TURF: u32 = 1 << 5;
    pub const KEY: u32 = 1 << 6;
    pub const NULL: u32 = 1 << 7;
    pub const AREA: u32 = 1 << 8;
    pub const ICON: u32 = 1 << 9;
    pub const SOUND: u32 = 1 << 10;
    pub const MESSAGE: u32 = 1 << 11;
    pub const ANYTHING: u32 = 1 << 12;
    pub const PASSWORD: u32 = 1 << 15;
    pub const COMMAND_TEXT: u32 = 1 << 16;
    pub const COLOR: u32 = 1 << 17;
    pub const MOVABLE: u32 = Self::OBJ | Self::MOB;
    pub const ATOM: u32 = Self::AREA | Self::TURF | Self::OBJ | Self::MOB;
    pub const LIST: u32 = 1 << 31;

    pub fn bit(name: &str) -> Option<u32> {
        Some(match name {
            "mob" => Self::MOB,
            "obj" => Self::OBJ,
            "text" => Self::TEXT,
            "num" => Self::NUM,
            "file" => Self::FILE,
            "turf" => Self::TURF,
            "key" => Self::KEY,
            "null" => Self::NULL,
            "area" => Self::AREA,
            "icon" => Self::ICON,
            "sound" => Self::SOUND,
            "message" => Self::MESSAGE,
            "anything" => Self::ANYTHING,
            "password" => Self::PASSWORD,
            "command_text" => Self::COMMAND_TEXT,
            "color" => Self::COLOR,
            "movable" => Self::MOVABLE,
            "atom" => Self::ATOM,
            "list" => Self::LIST,
            _ => return None,
        })
    }

    /// The input type `a|b|c` names (unknown names are left out, as SpacemanDMM's parse of a known spelling).
    pub fn from_names<S: AsRef<str>>(names: &[S]) -> InputType {
        InputType(names.iter().filter_map(|n| Self::bit(n.as_ref().trim())).fold(0, |a, b| a | b))
    }

    pub fn is_empty(self) -> bool {
        self.0 == 0
    }

    /// A type path approximating this input type, if any (SpacemanDMM's `InputType::to_typepath`).
    pub fn to_typepath(self) -> Option<&'static str> {
        let v = self.0;
        if v == 0 {
            None
        } else if v == Self::MOB {
            Some("/mob")
        } else if v == Self::OBJ {
            Some("/obj")
        } else if v == Self::TURF {
            Some("/turf")
        } else if v == Self::AREA {
            Some("/area")
        } else if v == Self::LIST {
            Some("/list")
        } else if v & !Self::MOVABLE == 0 {
            Some("/atom/movable")
        } else if v & !Self::ATOM == 0 {
            Some("/atom")
        } else {
            None
        }
    }
}

/// A place not located yet: SpacemanDMM's place of the token at an offset, the end of an offset's source line, or a location. The
/// walk keeps places as offsets and locates only those a diagnostic prints (locating is the costly part of reading the tree).
#[derive(Clone, Copy, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum Where {
    At(usize),
    LineEnd(usize),
    /// Where SpacemanDMM places a var declaration with no value that starts at the offset: the end of its line, or (a declaration a
    /// macro wrote) the invocation.
    DeclEnd(usize),
    Fixed(Location),
}

impl Where {
    /// No place (SpacemanDMM's default location).
    pub fn none() -> Where {
        Where::Fixed(Location::default())
    }
}

/// Places offsets of the front end's expanded text, for one worker thread.
pub trait Site {
    /// Where SpacemanDMM places the token starting at `offset`.
    fn locate(&self, offset: usize) -> Location;
    /// One column past the end of the source line holding `offset` (its comments included): where SpacemanDMM's newline token
    /// after that line sits.
    fn line_end(&self, offset: usize) -> Location;
    /// See [`Where::DeclEnd`].
    fn decl_end(&self, offset: usize) -> Location {
        self.line_end(offset)
    }
    /// The expanded text the offsets index.
    fn text(&self) -> &str;
    /// The macro invocation written in the source whose expansion holds `offset`: the expansion's output, the macro's name and the
    /// names expanded inside it.
    fn invocation(&self, offset: usize) -> Option<(Range<usize>, String, Vec<String>)>;
    /// A [`Where`]'s location.
    fn place(&self, at: Where) -> Location {
        match at {
            Where::At(offset) => self.locate(offset),
            Where::LineEnd(offset) => self.line_end(offset),
            Where::DeclEnd(offset) => self.decl_end(offset),
            Where::Fixed(location) => location,
        }
    }
}

/// Makes a [`Site`] for each worker thread.
pub trait Sites: Sync {
    fn site(&self) -> Box<dyn Site + '_>;
}

/// The proc bodies (`ProcValue::body` indexes them), read when a result for one is computed.
pub trait Bodies: Sync {
    /// The body's typed statements (`None`: the front end has none for it).
    fn statements(&self, body: u32) -> Option<std::sync::Arc<Vec<dm_syntax::Statement>>>;
    /// Where the body starts in the expanded text its places index (the folded facts keep their places relative to it).
    fn start(&self, body: u32) -> usize;
}

/// Everything the native checker reads.
pub struct CheckerInput<'s> {
    pub model: super::model::Model,
    pub bodies: &'s dyn Bodies,
    pub sites: &'s dyn Sites,
}
