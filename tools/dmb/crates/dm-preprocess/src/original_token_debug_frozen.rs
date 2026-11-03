// Frozen source-derived reference from pinned Dreammaker lexer/docs. Test-only.
macro_rules! table {
    (
        $(#[$attr:meta])* table $tabname:ident: $repr:ty => $enum_:ident;
        $($literal:expr, $name:ident $(-> $close:ident)*;)*
    ) => {
        $(#[$attr])*
        #[derive(Copy, Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
        pub enum $enum_ {
            $(
                $name,
                $($close,)*
            )*
        }

        impl $enum_ {
            fn value(self) -> $repr {
                match self {
                    $(
                        $enum_::$name => $literal,
                        $($enum_::$close => $literal,)*
                    )*
                }
            }

            pub fn single_quoted(self) -> &'static str {
                match self {
                    $(
                        $enum_::$name => concat!("'", $literal, "'"),
                        $($enum_::$close => concat!("'", $literal, "'"),)*
                    )*
                }
            }

            fn close(self) -> Self {
                match self {
                    $(
                        $($enum_::$name => $enum_::$close,)*
                    )*
                    _ => self,
                }
            }
        }

        const $tabname: &'static [($repr, $enum_)] = &[
            $(($literal, $enum_::$name),)*
        ];
    }
}

// (paren) {brace} [bracket]
table! {
    /// A punctuation token recognized by the language.
    ///
    /// Not all punctuation types will actually appear in the lexer's output;
    /// some (such as comments) are handled internally.
    table PUNCT_TABLE: &'static str => Punctuation;
    // Order is significant; see filter_punct below.
    "\t",  Tab;
    "\n",  Newline;
    " ",   Space;
    "!",   Not;
    "!=",  NotEq;
    "\"",  DoubleQuote;
    "#",   Hash;
    "##",  TokenPaste;
    "%",   Mod;
    "%%",  FloatMod;
    "%%=", FloatModAssign;
    "%=",  ModAssign;
    "&",   BitAnd;
    "&&",  And;
    "&&=", AndAssign;
    "&=",  BitAndAssign;
    "'",   SingleQuote;
    "(",   LParen;
    ")",   RParen;
    "*",   Mul;
    "**",  Pow;
    "*=",  MulAssign;
    "+",   Add;
    "++",  PlusPlus;
    "+=",  AddAssign;
    ",",   Comma;
    "-",   Sub;
    "--",  MinusMinus;
    "-=",  SubAssign;
    ".",   Dot;
    "..",  Super;
    "...", Ellipsis;
    "/",   Slash;
    "/*",  BlockComment;
    "//",  LineComment;
    "/=",  DivAssign;
    ":",   Colon -> CloseColon;
    "::",  Scope;
    ":=",  AssignInto;
    ";",   Semicolon;
    "<",   Less;
    "<<",  LShift;
    "<<=", LShiftAssign;
    "<=",  LessEq;
    "<=>", LessOrGreater;
    "<>",  LessGreater;
    "=",   Assign;
    "==",  Eq;
    ">",   Greater;
    ">=",  GreaterEq;
    ">>",  RShift;
    ">>=", RShiftAssign;
    "?",   QuestionMark;
    "?.",  SafeDot;
    "?:",  SafeColon;
    "?[",  SafeLBracket;
    "[",   LBracket;
    "]",   RBracket;
    "^",   BitXor;
    "^=",  BitXorAssign;
    "{",   LBrace;
    "{\"", BlockString;
    "|",   BitOr;
    "|=",  BitOrAssign;
    "||",  Or;
    "||=", OrAssign;
    "}",   RBrace;
    "~",   BitNot;
    "~!",  NotEquiv;
    "~=",  Equiv;
    // Keywords - not checked by read_punct
    "in",  In;
}


#[derive(Clone,Debug)]pub enum CommentKind{Block,Line}
#[derive(Clone,Debug)]pub enum DocTarget{FollowingItem,EnclosingItem}
#[derive(Clone,Debug)]pub struct DocComment{pub kind:CommentKind,pub target:DocTarget,pub text:String}
type Ident=String;
#[derive(Clone,Debug)]
pub enum Token {
    /// An end-of-file. Exists as a convenience and is not emitted by the lexer.
    Eof,
    /// A punctuation symbol.
    Punct(Punctuation),
    /// A raw identifier or keyword. Indicates whether it is followed by whitespace.
    Ident(Ident, bool),
    /// A string literal with no interpolation.
    String(String),
    /// The opening portion of an interpolated string. Followed by an expression.
    InterpStringBegin(String),
    /// An internal portion of an interpolated string. Preceded and followed by an expression.
    InterpStringPart(String),
    /// The closing portion of an interpolated string. Preceded by an expression.
    InterpStringEnd(String),
    /// A resource literal, referring to a filename.
    Resource(String),
    /// An integer literal.
    Int(i32),
    /// A floating-point literal.
    Float(f32),
    /// A documentation comment.
    DocComment(DocComment),
}
