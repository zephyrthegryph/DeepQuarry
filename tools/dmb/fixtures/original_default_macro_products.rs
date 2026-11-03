//! Immutable independent Original default-definition function, GPL-3.0,
//! Tad Hardesty and SpacemanDMM contributors, commit0290db5c752fa292f9824521515b603a2afd11dc.
//! The selected function below is byte-for-byte copied from pinned builtins.rs.
//! Surrounding minimal test-only data facades replace no production judge.
use std::collections::BTreeMap;
#[derive(Clone,Copy,Debug,Default)]pub struct Location;impl Location{fn builtins()->Self{Self}}
#[derive(Clone,Debug)]pub enum Define{Constant{subst:Vec<lexer::Token>,docs:()},Function{params:Vec<String>,subst:Vec<lexer::Token>,variadic:bool,docs:()}}
#[derive(Default)]pub struct DefineMap(BTreeMap<String,(Location,Define)>);impl DefineMap{fn insert(&mut self,name:String,value:(Location,Define))->Option<Location>{self.0.insert(name,value).map(|(location,_)|location)}}
pub mod lexer{
 #[derive(Clone,Debug)]pub enum Token{Ident(String,bool),Punct(Punctuation),Int(i32),InterpStringBegin(String),InterpStringPart(String),InterpStringEnd(String)}
 #[derive(Clone,Copy,Debug)]pub enum Punctuation{Slash,LParen,RParen,Not,LBrace,RBrace,Hash}
 impl Punctuation{pub fn spelling(self)->&'static str{match self{Self::Slash=>"/",Self::LParen=>"(",Self::RParen=>")",Self::Not=>"!",Self::LBrace=>"{",Self::RBrace=>"}",Self::Hash=>"#"}}}
}
const DM_VERSION:i32=516;const DM_BUILD:i32=1666;
mod selected{use super::*;
pub fn default_defines(defines: &mut DefineMap) {
    use super::lexer::Token::*;
    use super::lexer::*;
    let location = Location::builtins();

    // #define EXCEPTION(value) new /exception(value)
    defines.insert("EXCEPTION".to_owned(), (location, Define::Function {
        params: vec!["value".to_owned()],
        variadic: false,
        subst: vec![
            Ident("new".to_owned(), true),
            Punct(Punctuation::Slash),
            Ident("exception".to_owned(), false),
            Punct(Punctuation::LParen),
            Ident("value".to_owned(), false),
            Punct(Punctuation::RParen),
        ],
        docs: Default::default(),
    }));

    // #define ASSERT(expression) if (!(expression)) { CRASH("[__FILE__]:[__LINE__]:Assertion Failed: [#X]") }
    defines.insert("ASSERT".to_owned(), (location, Define::Function {
        params: vec!["expression".to_owned()],
        variadic: false,
        subst: vec![
            Ident("if".to_owned(), true),
            Punct(Punctuation::LParen),
            Punct(Punctuation::Not),
            Punct(Punctuation::LParen),
            Ident("expression".to_owned(), false),
            Punct(Punctuation::RParen),
            Punct(Punctuation::RParen),
            Punct(Punctuation::LBrace),
            Ident("CRASH".to_owned(), false),
            Punct(Punctuation::LParen),
            InterpStringBegin("".to_owned()),
            Ident("__FILE__".to_owned(), false),
            InterpStringPart(":".to_owned()),
            Ident("__LINE__".to_owned(), false),
            InterpStringPart(":Assertion Failed: ".to_owned()),
            Punct(Punctuation::Hash),
            Ident("expression".to_owned(), false),
            InterpStringEnd("".to_owned()),
            Punct(Punctuation::RParen),
            Punct(Punctuation::RBrace),
        ],
        docs: Default::default(),
    }));

    // constants
    macro_rules! c {
        ($($i:ident = $($x:expr),*;)*) => {
            for (name, value) in &[
                $((stringify!($i), [$($x,)*]),)*
            ] {
                let previous = defines.insert(name.to_string(), (location, Define::Constant { subst: value.to_vec(), docs: Default::default() }));
                assert!(previous.is_none(), "redefined: {}", name);
            }
        }
    }
    c! {
        DM_VERSION = Int(DM_VERSION);
        DM_BUILD = Int(DM_BUILD);
        SPACEMAN_DMM = Int(1);

        FALSE = Int(0);
        TRUE = Int(1);

        // eye and sight
        SEEINVIS = Int(2);
        SEEMOBS = Int(4);
        SEEOBJS = Int(8);
        SEETURFS = Int(16);

        // gliding
        NO_STEPS = Int(0);
        FORWARD_STEPS = Int(1);
        SLIDE_STEPS = Int(2);
        SYNC_STEPS = Int(3);

        // appearance_flags
        LONG_GLIDE = Int(1);
        RESET_COLOR = Int(2);
        RESET_ALPHA = Int(4);
        RESET_TRANSFORM = Int(8);
        NO_CLIENT_COLOR = Int(16);
        KEEP_TOGETHER = Int(32);
        KEEP_APART = Int(64);
        PLANE_MASTER = Int(128);
        TILE_BOUND = Int(256);
        PIXEL_SCALE = Int(512);
        PASS_MOUSE = Int(1024);
        TILE_MOVER = Int(2048); // 514

        CONTROL_FREAK_ALL = Int(1);
        CONTROL_FREAK_SKIN = Int(2);
        CONTROL_FREAK_MACROS = Int(4);

        // icons
        ICON_ADD = Int(0);
        ICON_SUBTRACT = Int(1);
        ICON_MULTIPLY = Int(2);
        ICON_OVERLAY = Int(3);
        ICON_AND = Int(4);
        ICON_OR = Int(5);
        ICON_UNDERLAY = Int(6);

        // matrix
        MATRIX_COPY = Int(0);
        MATRIX_MULTIPLY = Int(1);
        MATRIX_ADD = Int(2);
        MATRIX_SUBTRACT = Int(3);
        MATRIX_INVERT = Int(4);
        MATRIX_ROTATE = Int(5);
        MATRIX_SCALE = Int(6);
        MATRIX_TRANSLATE = Int(7);
        MATRIX_INTERPOLATE = Int(8);
        MATRIX_MODIFY = Int(128);

        // animation easing
        LINEAR_EASING = Int(0);
        SINE_EASING = Int(1);
        CIRCULAR_EASING = Int(2);
        CUBIC_EASING = Int(3);
        BOUNCE_EASING = Int(4);
        ELASTIC_EASING = Int(5);
        BACK_EASING = Int(6);
        QUAD_EASING = Int(7);
        JUMP_EASING = Int(8); // 513
        EASE_IN = Int(64);
        EASE_OUT = Int(128);

        // animation flags
        ANIMATION_END_NOW = Int(1);
        ANIMATION_LINEAR_TRANSFORM = Int(2);
        ANIMATION_PARALLEL = Int(4);
        ANIMATION_SLICE = Int(8); // 515
        ANIMATION_END_LOOP = Int(16); // 516
        ANIMATION_RELATIVE = Int(256);
        ANIMATION_CONTINUE = Int(512); // 515

        // database
        DATABASE_OPEN = Int(0);
        DATABASE_CLOSE = Int(1);
        DATABASE_ERROR_CODE = Int(2);
        DATABASE_ERROR = Int(3);
        DATABASE_QUERY_CLEAR = Int(4);
        DATABASE_QUERY_ADD = Int(5);
        DATABASE_QUERY_EXEC = Int(8);
        DATABASE_QUERY_NEXT = Int(9);
        DATABASE_QUERY_ABORT = Int(10);
        DATABASE_QUERY_RESET = Int(11);
        DATABASE_QUERY_ROWS_AFFECTED = Int(12);
        DATABASE_ROW_COLUMN_NAMES = Int(16);
        DATABASE_ROW_COLUMN_VALUE = Int(17);
        DATABASE_ROW_LIST = Int(18);

        // vis_flags (513)
        VIS_INHERIT_ICON = Int(1);
        VIS_INHERIT_ICON_STATE = Int(2);
        VIS_INHERIT_DIR = Int(4);
        VIS_INHERIT_LAYER = Int(8);
        VIS_INHERIT_PLANE = Int(16);
        VIS_INHERIT_ID = Int(32);
        VIS_UNDERLAY = Int(64);
        VIS_HIDE = Int(128);

        // color spaces (514)
        COLORSPACE_RGB = Int(0);
        COLORSPACE_HSV = Int(1);
        COLORSPACE_HSL = Int(2);
        COLORSPACE_HCY = Int(3);

        // world.Profile() (513)
        PROFILE_STOP = Int(1);
        PROFILE_CLEAR = Int(2);
        PROFILE_AVERAGE = Int(4);
        PROFILE_START = Int(0);
        PROFILE_REFRESH = Int(0);
        PROFILE_RESTART = Int(2);

        // generator functions (514)
        UNIFORM_RAND = Int(0);
        NORMAL_RAND = Int(1);
        LINEAR_RAND = Int(2);
        SQUARE_RAND = Int(3);


        // json encode flags (515)
        JSON_PRETTY_PRINT = Int(1);

        // json decode flags (515)
        JSON_STRICT = Int(1);
        JSON_ALLOW_COMMENTS = Int(2); // default
    }
}
}
pub fn all()->BTreeMap<String,Define>{let mut map=DefineMap::default();selected::default_defines(&mut map);map.0.into_iter().map(|(name,(_,value))|(name,value)).collect()}
