//
//  LanguageRegistry.swift
//  PlainX Editor
//
//  Maps file names/extensions to lexers and provides every piece of
//  language metadata PlainX needs: lexer name, keyword lists, comment
//  tokens, folding support, and the lexer-style → semantic-theme mapping.
//

import Foundation

struct LanguageDefinition {
    let id: String
    let displayName: String
    /// Lexilla lexer name, or nil for plain text (no lexer installed).
    let lexerName: String?
    let extensions: [String]
    let fileNames: [String]
    let keywords: [String]
    let types: [String]
    let builtins: [String]
    let lineComment: String?
    let blockComment: (start: String, end: String)?
    let styleMap: [Int: SemanticStyle]
    let supportsFolding: Bool

    var keywordString: String { keywords.joined(separator: " ") }
    var typeString: String { types.joined(separator: " ") }
    var builtinString: String { builtins.joined(separator: " ") }
}

// Swift lexer style numbers (mirrors PXSwiftStyle in PXSciBridge.h).
private enum PXSwiftStyle {
    static let defaultValue = 0
    static let commentLine = 1
    static let commentLineDoc = 2
    static let commentBlock = 3
    static let commentBlockDoc = 4
    static let number = 5
    static let keyword = 6
    static let type = 7
    static let string = 8
    static let stringMultiline = 9
    static let interpolation = 10
    static let attribute = 11
    static let preprocessor = 12
    static let operatorStyle = 13
    static let identifier = 14
    static let escape = 15
    static let selfKeyword = 16
    static let parameter = 17
}

enum LanguageRegistry {

    // MARK: - Style maps

    private static let swiftStyleMap: [Int: SemanticStyle] = [
        PXSwiftStyle.defaultValue: .text,
        PXSwiftStyle.commentLine: .comment,
        PXSwiftStyle.commentLineDoc: .docComment,
        PXSwiftStyle.commentBlock: .comment,
        PXSwiftStyle.commentBlockDoc: .docComment,
        PXSwiftStyle.number: .number,
        PXSwiftStyle.keyword: .keyword,
        PXSwiftStyle.type: .type,
        PXSwiftStyle.string: .string,
        PXSwiftStyle.stringMultiline: .string,
        PXSwiftStyle.interpolation: .text,
        PXSwiftStyle.attribute: .attribute,
        PXSwiftStyle.preprocessor: .preprocessor,
        PXSwiftStyle.operatorStyle: .operatorSymbol,
        PXSwiftStyle.identifier: .identifier,
        PXSwiftStyle.escape: .character,
        PXSwiftStyle.selfKeyword: .keywordSecondary,
        PXSwiftStyle.parameter: .constant,
    ]

    private static let cppStyleMap: [Int: SemanticStyle] = [
        Int(SCE_C_DEFAULT): .text,
        Int(SCE_C_COMMENT): .comment,
        Int(SCE_C_COMMENTLINE): .comment,
        Int(SCE_C_COMMENTDOC): .docComment,
        Int(SCE_C_COMMENTLINEDOC): .docComment,
        Int(SCE_C_COMMENTDOCKEYWORD): .docComment,
        Int(SCE_C_COMMENTDOCKEYWORDERROR): .error,
        Int(SCE_C_NUMBER): .number,
        Int(SCE_C_WORD): .keyword,
        Int(SCE_C_WORD2): .type,
        Int(SCE_C_STRING): .string,
        Int(SCE_C_STRINGRAW): .string,
        Int(SCE_C_TRIPLEVERBATIM): .string,
        Int(SCE_C_HASHQUOTEDSTRING): .string,
        Int(SCE_C_CHARACTER): .character,
        Int(SCE_C_UUID): .constant,
        Int(SCE_C_PREPROCESSOR): .preprocessor,
        Int(SCE_C_PREPROCESSORCOMMENT): .comment,
        Int(SCE_C_PREPROCESSORCOMMENTDOC): .docComment,
        Int(SCE_C_OPERATOR): .operatorSymbol,
        Int(SCE_C_IDENTIFIER): .identifier,
        Int(SCE_C_STRINGEOL): .error,
        Int(SCE_C_VERBATIM): .string,
        Int(SCE_C_REGEX): .string,
        Int(SCE_C_GLOBALCLASS): .type,
        Int(SCE_C_USERLITERAL): .constant,
        Int(SCE_C_TASKMARKER): .comment,
        Int(SCE_C_ESCAPESEQUENCE): .character,
    ]

    private static let pythonStyleMap: [Int: SemanticStyle] = [
        Int(SCE_P_DEFAULT): .text,
        Int(SCE_P_COMMENTLINE): .comment,
        Int(SCE_P_COMMENTBLOCK): .comment,
        Int(SCE_P_NUMBER): .number,
        Int(SCE_P_STRING): .string,
        Int(SCE_P_CHARACTER): .string,
        Int(SCE_P_TRIPLE): .string,
        Int(SCE_P_TRIPLEDOUBLE): .string,
        Int(SCE_P_FSTRING): .string,
        Int(SCE_P_FCHARACTER): .string,
        Int(SCE_P_FTRIPLE): .string,
        Int(SCE_P_FTRIPLEDOUBLE): .string,
        Int(SCE_P_WORD): .keyword,
        Int(SCE_P_WORD2): .type,
        Int(SCE_P_CLASSNAME): .type,
        Int(SCE_P_DEFNAME): .function,
        Int(SCE_P_OPERATOR): .operatorSymbol,
        Int(SCE_P_IDENTIFIER): .identifier,
        Int(SCE_P_DECORATOR): .attribute,
        Int(SCE_P_ATTRIBUTE): .attribute,
        Int(SCE_P_STRINGEOL): .error,
    ]

    private static let shellStyleMap: [Int: SemanticStyle] = [
        Int(SCE_SH_DEFAULT): .text,
        Int(SCE_SH_ERROR): .error,
        Int(SCE_SH_COMMENTLINE): .comment,
        Int(SCE_SH_NUMBER): .number,
        Int(SCE_SH_WORD): .keyword,
        Int(SCE_SH_STRING): .string,
        Int(SCE_SH_CHARACTER): .character,
        Int(SCE_SH_OPERATOR): .operatorSymbol,
        Int(SCE_SH_IDENTIFIER): .identifier,
        Int(SCE_SH_SCALAR): .constant,
        Int(SCE_SH_PARAM): .constant,
        Int(SCE_SH_BACKTICKS): .string,
        Int(SCE_SH_HERE_DELIM): .constant,
        Int(SCE_SH_HERE_Q): .string,
    ]

    private static let powershellStyleMap: [Int: SemanticStyle] = [
        Int(SCE_POWERSHELL_DEFAULT): .text,
        Int(SCE_POWERSHELL_COMMENT): .comment,
        Int(SCE_POWERSHELL_COMMENTSTREAM): .comment,
        Int(SCE_POWERSHELL_COMMENTDOCKEYWORD): .docComment,
        Int(SCE_POWERSHELL_STRING): .string,
        Int(SCE_POWERSHELL_HERE_STRING): .string,
        Int(SCE_POWERSHELL_CHARACTER): .character,
        Int(SCE_POWERSHELL_HERE_CHARACTER): .character,
        Int(SCE_POWERSHELL_NUMBER): .number,
        Int(SCE_POWERSHELL_VARIABLE): .constant,
        Int(SCE_POWERSHELL_OPERATOR): .operatorSymbol,
        Int(SCE_POWERSHELL_IDENTIFIER): .identifier,
        Int(SCE_POWERSHELL_KEYWORD): .keyword,
        Int(SCE_POWERSHELL_CMDLET): .function,
        Int(SCE_POWERSHELL_ALIAS): .function,
        Int(SCE_POWERSHELL_FUNCTION): .function,
    ]

    private static let htmlStyleMap: [Int: SemanticStyle] = [
        Int(SCE_H_DEFAULT): .text,
        Int(SCE_H_TAG): .keyword,
        Int(SCE_H_TAGUNKNOWN): .keyword,
        Int(SCE_H_TAGEND): .keyword,
        Int(SCE_H_ATTRIBUTE): .attribute,
        Int(SCE_H_ATTRIBUTEUNKNOWN): .identifier,
        Int(SCE_H_NUMBER): .number,
        Int(SCE_H_DOUBLESTRING): .string,
        Int(SCE_H_SINGLESTRING): .string,
        Int(SCE_H_OTHER): .operatorSymbol,
        Int(SCE_H_COMMENT): .comment,
        Int(SCE_H_ENTITY): .constant,
        Int(SCE_H_VALUE): .string,
        Int(SCE_H_XMLSTART): .keyword,
        Int(SCE_H_XMLEND): .keyword,
        Int(SCE_H_CDATA): .string,
        Int(SCE_H_QUESTION): .preprocessor,
        Int(SCE_H_XCCOMMENT): .comment,
    ]

    private static let embeddedJavaScriptStyleMap: [Int: SemanticStyle] = [
        Int(SCE_HJ_DEFAULT): .text,
        Int(SCE_HJ_COMMENT): .comment,
        Int(SCE_HJ_COMMENTLINE): .comment,
        Int(SCE_HJ_COMMENTDOC): .docComment,
        Int(SCE_HJ_NUMBER): .number,
        Int(SCE_HJ_WORD): .identifier,
        Int(SCE_HJ_KEYWORD): .keyword,
        Int(SCE_HJ_DOUBLESTRING): .string,
        Int(SCE_HJ_SINGLESTRING): .string,
        Int(SCE_HJ_SYMBOLS): .operatorSymbol,
        Int(SCE_HJ_STRINGEOL): .error,
        Int(SCE_HJ_REGEX): .string,
        Int(SCE_HJ_TEMPLATELITERAL): .string,
    ]

    private static let cssStyleMap: [Int: SemanticStyle] = [
        Int(SCE_CSS_DEFAULT): .text,
        Int(SCE_CSS_TAG): .keyword,
        Int(SCE_CSS_CLASS): .type,
        Int(SCE_CSS_PSEUDOCLASS): .keywordSecondary,
        Int(SCE_CSS_UNKNOWN_PSEUDOCLASS): .identifier,
        Int(SCE_CSS_OPERATOR): .operatorSymbol,
        Int(SCE_CSS_IDENTIFIER): .identifier,
        Int(SCE_CSS_UNKNOWN_IDENTIFIER): .identifier,
        Int(SCE_CSS_VALUE): .constant,
        Int(SCE_CSS_COMMENT): .comment,
        Int(SCE_CSS_ID): .type,
        Int(SCE_CSS_IMPORTANT): .keywordSecondary,
        Int(SCE_CSS_DIRECTIVE): .preprocessor,
        Int(SCE_CSS_DOUBLESTRING): .string,
        Int(SCE_CSS_SINGLESTRING): .string,
        Int(SCE_CSS_IDENTIFIER2): .identifier,
        Int(SCE_CSS_ATTRIBUTE): .attribute,
        Int(SCE_CSS_IDENTIFIER3): .identifier,
        Int(SCE_CSS_PSEUDOELEMENT): .keywordSecondary,
        Int(SCE_CSS_GROUP_RULE): .keyword,
        Int(SCE_CSS_VARIABLE): .constant,
    ]

    private static let jsonStyleMap: [Int: SemanticStyle] = [
        Int(SCE_JSON_DEFAULT): .text,
        Int(SCE_JSON_NUMBER): .number,
        Int(SCE_JSON_STRING): .string,
        Int(SCE_JSON_STRINGEOL): .error,
        Int(SCE_JSON_PROPERTYNAME): .attribute,
        Int(SCE_JSON_ESCAPESEQUENCE): .character,
        Int(SCE_JSON_LINECOMMENT): .comment,
        Int(SCE_JSON_BLOCKCOMMENT): .comment,
        Int(SCE_JSON_OPERATOR): .operatorSymbol,
        Int(SCE_JSON_URI): .string,
        Int(SCE_JSON_KEYWORD): .keyword,
        Int(SCE_JSON_ERROR): .error,
    ]

    private static let yamlStyleMap: [Int: SemanticStyle] = [
        Int(SCE_YAML_DEFAULT): .text,
        Int(SCE_YAML_COMMENT): .comment,
        Int(SCE_YAML_IDENTIFIER): .identifier,
        Int(SCE_YAML_KEYWORD): .keyword,
        Int(SCE_YAML_NUMBER): .number,
        Int(SCE_YAML_REFERENCE): .constant,
        Int(SCE_YAML_DOCUMENT): .preprocessor,
        Int(SCE_YAML_TEXT): .string,
        Int(SCE_YAML_ERROR): .error,
        Int(SCE_YAML_OPERATOR): .operatorSymbol,
    ]

    private static let tomlStyleMap: [Int: SemanticStyle] = [
        Int(SCE_TOML_DEFAULT): .text,
        Int(SCE_TOML_COMMENT): .comment,
        Int(SCE_TOML_IDENTIFIER): .identifier,
        Int(SCE_TOML_KEYWORD): .keyword,
        Int(SCE_TOML_NUMBER): .number,
        Int(SCE_TOML_TABLE): .type,
        Int(SCE_TOML_KEY): .attribute,
        Int(SCE_TOML_ERROR): .error,
        Int(SCE_TOML_OPERATOR): .operatorSymbol,
        Int(SCE_TOML_STRING_SQ): .string,
        Int(SCE_TOML_STRING_DQ): .string,
        Int(SCE_TOML_TRIPLE_STRING_SQ): .string,
        Int(SCE_TOML_TRIPLE_STRING_DQ): .string,
        Int(SCE_TOML_ESCAPECHAR): .character,
        Int(SCE_TOML_DATETIME): .constant,
    ]

    private static let propsStyleMap: [Int: SemanticStyle] = [
        Int(SCE_PROPS_DEFAULT): .text,
        Int(SCE_PROPS_COMMENT): .comment,
        Int(SCE_PROPS_SECTION): .type,
        Int(SCE_PROPS_ASSIGNMENT): .operatorSymbol,
        Int(SCE_PROPS_DEFVAL): .constant,
        Int(SCE_PROPS_KEY): .attribute,
    ]

    private static let sqlStyleMap: [Int: SemanticStyle] = [
        Int(SCE_SQL_DEFAULT): .text,
        Int(SCE_SQL_COMMENT): .comment,
        Int(SCE_SQL_COMMENTLINE): .comment,
        Int(SCE_SQL_COMMENTDOC): .docComment,
        Int(SCE_SQL_COMMENTLINEDOC): .docComment,
        Int(SCE_SQL_COMMENTDOCKEYWORD): .docComment,
        Int(SCE_SQL_COMMENTDOCKEYWORDERROR): .error,
        Int(SCE_SQL_NUMBER): .number,
        Int(SCE_SQL_WORD): .keyword,
        Int(SCE_SQL_WORD2): .type,
        Int(SCE_SQL_STRING): .string,
        Int(SCE_SQL_CHARACTER): .character,
        Int(SCE_SQL_SQLPLUS): .preprocessor,
        Int(SCE_SQL_SQLPLUS_PROMPT): .preprocessor,
        Int(SCE_SQL_SQLPLUS_COMMENT): .comment,
        Int(SCE_SQL_OPERATOR): .operatorSymbol,
        Int(SCE_SQL_IDENTIFIER): .identifier,
        Int(SCE_SQL_QUOTEDIDENTIFIER): .identifier,
        Int(SCE_SQL_USER1): .constant,
        Int(SCE_SQL_USER2): .constant,
        Int(SCE_SQL_USER3): .constant,
        Int(SCE_SQL_USER4): .constant,
    ]

    private static let markdownStyleMap: [Int: SemanticStyle] = [
        Int(SCE_MARKDOWN_DEFAULT): .text,
        Int(SCE_MARKDOWN_LINE_BEGIN): .text,
        Int(SCE_MARKDOWN_STRONG1): .keyword,
        Int(SCE_MARKDOWN_STRONG2): .keyword,
        Int(SCE_MARKDOWN_EM1): .comment,
        Int(SCE_MARKDOWN_EM2): .comment,
        Int(SCE_MARKDOWN_HEADER1): .keyword,
        Int(SCE_MARKDOWN_HEADER2): .keyword,
        Int(SCE_MARKDOWN_HEADER3): .keyword,
        Int(SCE_MARKDOWN_HEADER4): .keyword,
        Int(SCE_MARKDOWN_HEADER5): .keyword,
        Int(SCE_MARKDOWN_HEADER6): .keyword,
        Int(SCE_MARKDOWN_PRECHAR): .preprocessor,
        Int(SCE_MARKDOWN_ULIST_ITEM): .constant,
        Int(SCE_MARKDOWN_OLIST_ITEM): .constant,
        Int(SCE_MARKDOWN_BLOCKQUOTE): .comment,
        Int(SCE_MARKDOWN_STRIKEOUT): .comment,
        Int(SCE_MARKDOWN_HRULE): .operatorSymbol,
        Int(SCE_MARKDOWN_LINK): .attribute,
        Int(SCE_MARKDOWN_CODE): .string,
        Int(SCE_MARKDOWN_CODE2): .string,
        Int(SCE_MARKDOWN_CODEBK): .string,
    ]

    private static let rubyStyleMap: [Int: SemanticStyle] = [
        Int(SCE_RB_DEFAULT): .text,
        Int(SCE_RB_ERROR): .error,
        Int(SCE_RB_COMMENTLINE): .comment,
        Int(SCE_RB_POD): .docComment,
        Int(SCE_RB_NUMBER): .number,
        Int(SCE_RB_WORD): .keyword,
        Int(SCE_RB_WORD_DEMOTED): .identifier,
        Int(SCE_RB_STRING): .string,
        Int(SCE_RB_CHARACTER): .character,
        Int(SCE_RB_CLASSNAME): .type,
        Int(SCE_RB_MODULE_NAME): .type,
        Int(SCE_RB_DEFNAME): .function,
        Int(SCE_RB_OPERATOR): .operatorSymbol,
        Int(SCE_RB_IDENTIFIER): .identifier,
        Int(SCE_RB_REGEX): .string,
        Int(SCE_RB_GLOBAL): .constant,
        Int(SCE_RB_SYMBOL): .constant,
        Int(SCE_RB_INSTANCE_VAR): .constant,
        Int(SCE_RB_CLASS_VAR): .constant,
        Int(SCE_RB_BACKTICKS): .string,
        Int(SCE_RB_STRING_Q): .string,
        Int(SCE_RB_STRING_QQ): .string,
        Int(SCE_RB_STRING_QX): .string,
        Int(SCE_RB_STRING_QR): .string,
        Int(SCE_RB_STRING_QW): .string,
        Int(SCE_RB_STRING_W): .string,
        Int(SCE_RB_STRING_I): .string,
        Int(SCE_RB_HERE_DELIM): .constant,
        Int(SCE_RB_HERE_Q): .string,
        Int(SCE_RB_HERE_QQ): .string,
        Int(SCE_RB_HERE_QX): .string,
        Int(SCE_RB_DATASECTION): .comment,
    ]

    private static let rustStyleMap: [Int: SemanticStyle] = [
        Int(SCE_RUST_DEFAULT): .text,
        Int(SCE_RUST_COMMENTBLOCK): .comment,
        Int(SCE_RUST_COMMENTLINE): .comment,
        Int(SCE_RUST_COMMENTBLOCKDOC): .docComment,
        Int(SCE_RUST_COMMENTLINEDOC): .docComment,
        Int(SCE_RUST_NUMBER): .number,
        Int(SCE_RUST_WORD): .keyword,
        Int(SCE_RUST_WORD2): .type,
        Int(SCE_RUST_WORD3): .type,
        Int(SCE_RUST_WORD4): .constant,
        Int(SCE_RUST_WORD5): .constant,
        Int(SCE_RUST_WORD6): .constant,
        Int(SCE_RUST_WORD7): .constant,
        Int(SCE_RUST_STRING): .string,
        Int(SCE_RUST_STRINGR): .string,
        Int(SCE_RUST_CHARACTER): .character,
        Int(SCE_RUST_OPERATOR): .operatorSymbol,
        Int(SCE_RUST_IDENTIFIER): .identifier,
        Int(SCE_RUST_LIFETIME): .attribute,
        Int(SCE_RUST_MACRO): .function,
        Int(SCE_RUST_LEXERROR): .error,
        Int(SCE_RUST_BYTESTRING): .string,
        Int(SCE_RUST_BYTESTRINGR): .string,
        Int(SCE_RUST_BYTECHARACTER): .character,
        Int(SCE_RUST_CSTRING): .string,
        Int(SCE_RUST_CSTRINGR): .string,
    ]

    private static let batchStyleMap: [Int: SemanticStyle] = [
        Int(SCE_BAT_DEFAULT): .text,
        Int(SCE_BAT_COMMENT): .comment,
        Int(SCE_BAT_WORD): .keyword,
        Int(SCE_BAT_LABEL): .preprocessor,
        Int(SCE_BAT_HIDE): .comment,
        Int(SCE_BAT_COMMAND): .function,
        Int(SCE_BAT_IDENTIFIER): .identifier,
        Int(SCE_BAT_OPERATOR): .operatorSymbol,
        Int(SCE_BAT_AFTER_LABEL): .text,
    ]

    private static let perlStyleMap: [Int: SemanticStyle] = [
        Int(SCE_PL_DEFAULT): .text,
        Int(SCE_PL_ERROR): .error,
        Int(SCE_PL_COMMENTLINE): .comment,
        Int(SCE_PL_POD): .docComment,
        Int(SCE_PL_POD_VERB): .docComment,
        Int(SCE_PL_NUMBER): .number,
        Int(SCE_PL_WORD): .keyword,
        Int(SCE_PL_STRING): .string,
        Int(SCE_PL_STRING_Q): .string,
        Int(SCE_PL_STRING_QQ): .string,
        Int(SCE_PL_STRING_QX): .string,
        Int(SCE_PL_STRING_QR): .string,
        Int(SCE_PL_STRING_QW): .string,
        Int(SCE_PL_CHARACTER): .character,
        Int(SCE_PL_PUNCTUATION): .operatorSymbol,
        Int(SCE_PL_PREPROCESSOR): .preprocessor,
        Int(SCE_PL_OPERATOR): .operatorSymbol,
        Int(SCE_PL_IDENTIFIER): .identifier,
        Int(SCE_PL_SCALAR): .constant,
        Int(SCE_PL_ARRAY): .constant,
        Int(SCE_PL_HASH): .constant,
        Int(SCE_PL_SYMBOLTABLE): .constant,
        Int(SCE_PL_REGEX): .string,
        Int(SCE_PL_REGSUBST): .string,
        Int(SCE_PL_LONGQUOTE): .string,
        Int(SCE_PL_BACKTICKS): .string,
        Int(SCE_PL_DATASECTION): .comment,
        Int(SCE_PL_HERE_DELIM): .constant,
        Int(SCE_PL_HERE_Q): .string,
        Int(SCE_PL_HERE_QQ): .string,
        Int(SCE_PL_HERE_QX): .string,
    ]

    private static let makeStyleMap: [Int: SemanticStyle] = [
        Int(SCE_MAKE_DEFAULT): .text,
        Int(SCE_MAKE_COMMENT): .comment,
        Int(SCE_MAKE_PREPROCESSOR): .preprocessor,
        Int(SCE_MAKE_IDENTIFIER): .identifier,
        Int(SCE_MAKE_OPERATOR): .operatorSymbol,
        Int(SCE_MAKE_TARGET): .function,
        Int(SCE_MAKE_IDEOL): .error,
    ]

    private static let diffStyleMap: [Int: SemanticStyle] = [
        Int(SCE_DIFF_DEFAULT): .text,
        Int(SCE_DIFF_COMMENT): .comment,
        Int(SCE_DIFF_COMMAND): .preprocessor,
        Int(SCE_DIFF_HEADER): .keyword,
        Int(SCE_DIFF_POSITION): .constant,
        Int(SCE_DIFF_DELETED): .diffRemoved,
        Int(SCE_DIFF_ADDED): .diffAdded,
        Int(SCE_DIFF_CHANGED): .diffChanged,
        Int(SCE_DIFF_PATCH_ADD): .diffAdded,
        Int(SCE_DIFF_PATCH_DELETE): .diffRemoved,
        Int(SCE_DIFF_REMOVED_PATCH_ADD): .diffAdded,
        Int(SCE_DIFF_REMOVED_PATCH_DELETE): .diffRemoved,
    ]

    private static func cppLikeStyleMap() -> [Int: SemanticStyle] { cppStyleMap }

    // MARK: - Keyword sets

    private static let swiftKeywords = [
        "actor", "any", "as", "associatedtype", "async", "await", "borrowing", "break", "case",
        "catch", "class", "consume", "consuming", "continue", "convenience", "copy", "default",
        "defer", "deinit", "didSet", "distributed", "do", "dynamic", "each", "else", "enum",
        "extension", "fallthrough", "fileprivate", "final", "for", "func", "get", "guard", "if",
        "import", "in", "indirect", "infix", "init", "inout", "internal", "is", "isolated", "lazy",
        "let", "macro", "mutating", "nonisolated", "nonmutating", "open", "operator", "optional",
        "override", "package", "postfix", "precedencegroup", "prefix", "private", "protocol",
        "public", "repeat", "required", "rethrows", "return", "sending", "set", "some", "static",
        "struct", "subscript", "super", "switch", "throws", "throw", "try", "typealias", "unowned",
        "var", "weak", "where", "while", "willSet", "yield", "break", "continue",
    ]

    private static let swiftBuiltinTypes = [
        "Any", "AnyObject", "Array", "Bool", "Character", "Dictionary", "Double", "Error",
        "Float", "Int", "Int8", "Int16", "Int32", "Int64", "Never", "Optional", "Result", "Set",
        "String", "Substring", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Void",
        "CGFloat", "Codable", "Decodable", "Encodable", "Equatable", "Hashable", "Identifiable",
        "Comparable", "Sequence", "Collection", "IteratorProtocol", "Error", "Sendable",
        "AsyncSequence", "Task", "URL", "UUID", "Data", "Date", "CGRect", "CGPoint", "CGSize",
    ]

    private static let swiftBuiltins = [
        "true", "false", "nil", "self", "Self", "super", "print", "debugPrint", "fatalError",
        "precondition", "preconditionFailure", "assert", "assertionFailure", "min", "max", "abs",
        "stride", "zip", "repeatElement", "swap", "type", "MemoryLayout", "withUnsafePointer",
    ]

    private static let cKeywords = [
        "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else",
        "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register",
        "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef",
        "union", "unsigned", "void", "volatile", "while", "_Bool", "_Complex", "_Atomic",
    ]

    private static let cTypes = [
        "bool", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t",
        "uint64_t", "intptr_t", "uintptr_t", "size_t", "ssize_t", "ptrdiff_t", "FILE", "time_t",
        "va_list", "NULL", "true", "false", "stdin", "stdout", "stderr",
    ]

    private static let cppKeywords = [
        "alignas", "alignof", "and", "asm", "auto", "bitand", "bitor", "bool", "break", "case",
        "catch", "char", "char8_t", "char16_t", "char32_t", "class", "compl", "concept", "const",
        "consteval", "constexpr", "constinit", "const_cast", "continue", "co_await", "co_return",
        "co_yield", "decltype", "default", "delete", "do", "double", "dynamic_cast", "else",
        "enum", "explicit", "export", "extern", "false", "float", "for", "friend", "goto", "if",
        "inline", "int", "long", "mutable", "namespace", "new", "noexcept", "not", "nullptr",
        "operator", "or", "private", "protected", "public", "register", "reinterpret_cast",
        "requires", "return", "short", "signed", "sizeof", "static", "static_assert",
        "static_cast", "struct", "switch", "template", "this", "thread_local", "throw", "true",
        "try", "typedef", "typeid", "typename", "union", "unsigned", "using", "virtual", "void",
        "volatile", "wchar_t", "while", "xor", "override", "final", "import", "module",
    ]

    private static let cppTypes = [
        "std", "string", "string_view", "vector", "map", "unordered_map", "set", "unordered_set",
        "array", "deque", "list", "forward_list", "stack", "queue", "priority_queue", "pair",
        "tuple", "optional", "variant", "any", "shared_ptr", "unique_ptr", "weak_ptr", "function",
        "span", "byte", "size_t", "ptrdiff_t", "int8_t", "int16_t", "int32_t", "int64_t",
        "uint8_t", "uint16_t", "uint32_t", "uint64_t", "ssize_t", "nullptr_t",
    ]

    private static let objCKeywords = cppKeywords + [
        "id", "instancetype", "nonatomic", "atomic", "strong", "weak", "copy", "assign", "retain",
        "readonly", "readwrite", "property", "synthesize", "dynamic", "interface", "implementation",
        "protocol", "selector", "encode", "synchronized", "autoreleasepool", "try", "catch",
        "@end", "@interface", "@implementation", "@protocol", "@property", "@synthesize",
        "@dynamic", "@selector", "@encode", "@class", "@public", "@private", "@protected",
        "@package", "@import", "@autoreleasepool", "@available", "@synchronized",
    ]

    private static let csharpKeywords = [
        "abstract", "as", "base", "bool", "break", "byte", "case", "catch", "char", "checked",
        "class", "const", "continue", "decimal", "default", "delegate", "do", "double", "else",
        "enum", "event", "explicit", "extern", "false", "finally", "fixed", "float", "for",
        "foreach", "goto", "if", "implicit", "in", "int", "interface", "internal", "is", "lock",
        "long", "namespace", "new", "null", "object", "operator", "out", "override", "params",
        "private", "protected", "public", "readonly", "ref", "return", "sbyte", "sealed", "short",
        "sizeof", "stackalloc", "static", "string", "struct", "switch", "this", "throw", "true",
        "try", "typeof", "uint", "ulong", "unchecked", "unsafe", "ushort", "using", "virtual",
        "void", "volatile", "while", "async", "await", "var", "dynamic", "record", "init",
        "required", "file", "global", "when", "where", "yield", "nameof", "partial",
    ]

    private static let csharpTypes = [
        "System", "Console", "String", "Int32", "Int64", "Boolean", "Object", "Task", "List",
        "Dictionary", "IEnumerable", "IList", "IDictionary", "Exception", "Action", "Func",
        "Nullable", "Guid", "DateTime", "TimeSpan", "Math", "Convert", "Span", "Memory",
    ]

    private static let javaKeywords = [
        "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
        "const", "continue", "default", "do", "double", "else", "enum", "extends", "final",
        "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int",
        "interface", "long", "native", "new", "package", "private", "protected", "public",
        "return", "short", "static", "strictfp", "super", "switch", "synchronized", "this",
        "throw", "throws", "transient", "try", "var", "void", "volatile", "while", "true", "false",
        "null", "record", "sealed", "permits", "yield",
    ]

    private static let javaTypes = [
        "String", "Object", "Integer", "Long", "Double", "Float", "Boolean", "Character", "Byte",
        "Short", "List", "ArrayList", "Map", "HashMap", "Set", "HashSet", "Optional", "Stream",
        "Exception", "RuntimeException", "Thread", "Runnable", "System", "Math", "Path", "Files",
    ]

    private static let goKeywords = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
        "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range",
        "return", "select", "struct", "switch", "type", "var", "true", "false", "nil", "iota",
        "append", "cap", "close", "complex", "copy", "delete", "imag", "len", "make", "new",
        "panic", "print", "println", "real", "recover",
    ]

    private static let goTypes = [
        "bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8",
        "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32",
        "uint64", "uintptr", "any", "comparable",
    ]

    private static let javascriptKeywords = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
        "default", "delete", "do", "else", "export", "extends", "false", "finally", "for",
        "function", "get", "if", "import", "in", "instanceof", "let", "new", "null", "of",
        "return", "set", "static", "super", "switch", "this", "throw", "true", "try", "typeof",
        "var", "void", "while", "with", "yield", "from", "as", "undefined",
    ]

    private static let javascriptTypes = [
        "Array", "Boolean", "Date", "Error", "Function", "JSON", "Map", "Math", "Number",
        "Object", "Promise", "Proxy", "Reflect", "RegExp", "Set", "String", "Symbol",
        "WeakMap", "WeakSet", "console", "document", "window", "globalThis", "module", "require",
        "exports", "process", "Buffer", "setTimeout", "setInterval", "clearTimeout",
        "clearInterval", "fetch", "parseInt", "parseFloat", "isNaN", "isFinite", "encodeURIComponent",
        "decodeURIComponent",
    ]

    private static let typescriptKeywords = javascriptKeywords + [
        "abstract", "declare", "enum", "implements", "interface", "is", "keyof", "namespace",
        "private", "protected", "public", "readonly", "satisfies", "type", "infer", "asserts",
        "override", "unique", "out",
    ]

    private static let typescriptTypes = javascriptTypes + [
        "string", "number", "boolean", "any", "unknown", "never", "object", "symbol", "bigint",
        "Record", "Partial", "Required", "Readonly", "Pick", "Omit", "Exclude", "Extract",
        "NonNullable", "ReturnType", "Parameters", "Awaited", "Array", "ReadonlyArray", "Promise",
        "Map", "Set", "WeakMap", "WeakSet", "Iterable", "AsyncIterable",
    ]

    private static let pythonKeywords = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
        "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is",
        "lambda", "match", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
        "with", "yield", "None", "True", "False", "self",
    ]

    private static let pythonTypes = [
        "bool", "bytes", "bytearray", "complex", "dict", "float", "frozenset", "int", "list",
        "memoryview", "object", "range", "set", "str", "tuple", "type", "Exception",
        "ValueError", "TypeError", "KeyError", "IndexError", "RuntimeError", "BaseException",
        "StopIteration", "AttributeError", "ImportError", "OSError", "IOError", "FileNotFoundError",
        "print", "len", "range", "enumerate", "zip", "map", "filter", "sorted", "reversed",
        "isinstance", "issubclass", "super", "open", "input", "format", "repr", "hash", "id",
        "iter", "next", "getattr", "setattr", "hasattr", "delattr", "vars", "dir", "globals",
        "locals", "abs", "min", "max", "sum", "round", "any", "all",
    ]

    private static let shellKeywords = [
        "if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until", "do", "done",
        "in", "function", "select", "time", "coproc", "return", "break", "continue", "exit",
        "local", "declare", "typeset", "export", "readonly", "unset", "shift", "eval", "exec",
        "trap", "set", "shopt", "source", "alias", "unalias", "echo", "printf", "read", "cd",
        "pwd", "pushd", "popd", "test", "true", "false", "let",
    ]

    private static let shellBuiltins = [
        "awk", "sed", "grep", "egrep", "fgrep", "cat", "ls", "cp", "mv", "rm", "mkdir", "rmdir",
        "touch", "find", "xargs", "sort", "uniq", "head", "tail", "wc", "cut", "tr", "tee",
        "curl", "wget", "ssh", "scp", "rsync", "tar", "gzip", "gunzip", "zip", "unzip", "chmod",
        "chown", "kill", "ps", "top", "df", "du", "date", "env", "which", "man", "sudo", "jq",
        "git", "make", "docker", "systemctl", "journalctl", "launchctl",
    ]

    private static let dockerfileKeywords = [
        "FROM", "RUN", "CMD", "LABEL", "MAINTAINER", "EXPOSE", "ENV", "ADD", "COPY", "ENTRYPOINT",
        "VOLUME", "USER", "WORKDIR", "ARG", "ONBUILD", "STOPSIGNAL", "HEALTHCHECK", "SHELL",
        "AS", "as", "scratch",
    ]

    private static let powershellKeywords = [
        "begin", "break", "catch", "class", "continue", "data", "define", "do", "dynamicparam",
        "else", "elseif", "end", "enum", "exit", "filter", "finally", "for", "foreach", "from",
        "function", "if", "in", "param", "process", "return", "switch", "throw", "trap", "try",
        "until", "using", "var", "while", "workflow", "parallel", "sequence", "inlinescript",
    ]

    private static let powershellCmdlets = [
        "Add-Content", "Add-Member", "Clear-Content", "Compare-Object", "ConvertFrom-Json",
        "ConvertTo-Json", "Copy-Item", "Export-Csv", "ForEach-Object", "Format-List",
        "Format-Table", "Get-ChildItem", "Get-Command", "Get-Content", "Get-Date",
        "Get-Help", "Get-Item", "Get-ItemProperty", "Get-Location", "Get-Member",
        "Get-Process", "Get-Service", "Group-Object", "Import-Csv", "Import-Module",
        "Invoke-Command", "Invoke-Expression", "Invoke-RestMethod", "Invoke-WebRequest",
        "Join-Path", "Measure-Object", "Move-Item", "New-Item", "New-Object", "Out-File",
        "Out-Null", "Out-String", "Read-Host", "Remove-Item", "Rename-Item", "Resolve-Path",
        "Select-Object", "Select-String", "Set-Content", "Set-Item", "Set-Location",
        "Sort-Object", "Split-Path", "Start-Process", "Start-Sleep", "Stop-Process",
        "Test-Path", "Where-Object", "Write-Debug", "Write-Error", "Write-Host", "Write-Output",
        "Write-Verbose", "Write-Warning", "ConvertTo-SecureString", "Get-Credential",
        "Get-Random", "Get-Variable", "Set-Variable", "Tee-Object", "Unblock-File", "Wait-Process",
    ]

    private static let sqlKeywords = [
        "select", "from", "where", "and", "or", "not", "insert", "into", "values", "update",
        "set", "delete", "create", "table", "alter", "drop", "index", "view", "join", "inner",
        "left", "right", "outer", "full", "cross", "on", "group", "by", "having", "order",
        "asc", "desc", "limit", "offset", "union", "all", "distinct", "as", "case", "when",
        "then", "else", "end", "null", "is", "in", "between", "like", "exists", "primary",
        "key", "foreign", "references", "unique", "default", "check", "constraint", "with",
        "recursive", "begin", "commit", "rollback", "transaction", "grant", "revoke", "if",
        "replace", "truncate", "explain", "analyze", "vacuum", "pragma", "function", "procedure",
        "trigger", "returning", "conflict", "do", "nothing", "over", "partition", "window",
        "select", "database", "schema", "use",
    ]

    private static let sqlTypes = [
        "int", "integer", "smallint", "bigint", "decimal", "numeric", "real", "double",
        "precision", "float", "char", "varchar", "text", "blob", "date", "time", "timestamp",
        "datetime", "interval", "boolean", "bool", "serial", "bigserial", "uuid", "json",
        "jsonb", "array", "enum", "money", "bytea", "xml", "inet", "cidr", "macaddr",
    ]

    private static let rubyKeywords = [
        "BEGIN", "END", "alias", "and", "begin", "break", "case", "class", "def", "defined?",
        "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next",
        "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then",
        "true", "undef", "unless", "until", "when", "while", "yield", "require", "require_relative",
        "include", "extend", "attr_accessor", "attr_reader", "attr_writer", "puts", "print",
        "raise", "lambda", "proc", "new", "loop",
    ]

    private static let rubyTypes = [
        "Array", "Hash", "String", "Integer", "Float", "Symbol", "Range", "Regexp", "IO", "File",
        "Dir", "Time", "Date", "Struct", "Proc", "Class", "Module", "Exception", "StandardError",
        "RuntimeError", "ArgumentError", "TypeError", "NameError", "Kernel", "Enumerable",
        "Comparable", "Object", "NilClass", "TrueClass", "FalseClass", "Numeric",
    ]

    private static let rustKeywords = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
        "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod",
        "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super",
        "trait", "true", "type", "unsafe", "use", "where", "while", "try", "macro", "union",
        "gen", "raw",
    ]

    private static let rustTypes = [
        "bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str", "u8",
        "u16", "u32", "u64", "u128", "usize", "String", "Vec", "Option", "Result", "Box",
        "Rc", "Arc", "Cell", "RefCell", "Mutex", "RwLock", "HashMap", "HashSet", "BTreeMap",
        "BTreeSet", "VecDeque", "CString", "PathBuf", "Path", "OsString", "OsStr", "Cow",
        "Some", "None", "Ok", "Err", "println", "print", "eprintln", "eprint", "format",
        "vec", "panic", "assert", "assert_eq", "assert_ne", "debug_assert", "write", "writeln",
        "todo", "unimplemented", "unreachable", "dbg", "matches",
    ]

    private static let batchKeywords = [
        "echo", "set", "if", "else", "for", "in", "do", "goto", "call", "exit", "rem", "shift",
        "cd", "chdir", "md", "mkdir", "rd", "rmdir", "del", "erase", "copy", "move", "ren",
        "rename", "type", "dir", "path", "pause", "start", "title", "ver", "vol", "cls", "attrib",
        "find", "findstr", "sort", "xcopy", "robocopy", "net", "sc", "reg", "tasklist", "taskkill",
        "timeout", "choice", "not", "exist", "errorlevel", "defined", "enabledelayedexpansion",
        "setlocal", "endlocal",
    ]

    private static let perlKeywords = [
        "and", "or", "not", "if", "elsif", "else", "unless", "while", "until", "for", "foreach",
        "do", "last", "next", "redo", "sub", "my", "our", "local", "state", "use", "require",
        "package", "return", "die", "warn", "eval", "begin", "end", "given", "when", "default",
        "say", "print", "printf", "chomp", "chop", "split", "join", "map", "grep", "sort",
        "keys", "values", "each", "exists", "defined", "undef", "ref", "bless", "new", "continue",
        "wantarray", "scalar", "list", "sub", "format", "check", "m", "q", "qq", "qw", "qr", "s",
        "tr", "y",
    ]

    private static let perlTypes = [
        "STDIN", "STDOUT", "STDERR", "ARGV", "ENV", "SIG", "VERSION",
    ]

    private static let iniKeywords = [
        "true", "false", "yes", "no", "on", "off", "null", "none",
    ]

    private static let htmlKeywords = [
        "html", "head", "body", "title", "meta", "link", "script", "style", "div", "span",
        "p", "a", "img", "ul", "ol", "li", "table", "thead", "tbody", "tr", "th", "td", "form",
        "input", "button", "select", "option", "textarea", "label", "h1", "h2", "h3", "h4",
        "h5", "h6", "header", "footer", "nav", "main", "section", "article", "aside", "br",
        "hr", "iframe", "video", "audio", "source", "canvas", "svg", "template", "slot",
    ]

    private static let xmlKeywords = [
        "xml", "version", "encoding", "standalone", "DOCTYPE", "PUBLIC", "SYSTEM", "CDATA",
    ]

    // MARK: - Registry

    static let all: [LanguageDefinition] = [
        LanguageDefinition(
            id: "plain", displayName: "Plain Text", lexerName: nil,
            extensions: [], fileNames: [], keywords: [], types: [], builtins: [],
            lineComment: nil, blockComment: nil, styleMap: [:], supportsFolding: false
        ),
        LanguageDefinition(
            id: "swift", displayName: "Swift", lexerName: "swift",
            extensions: ["swift"],
            fileNames: [],
            keywords: swiftKeywords, types: swiftBuiltinTypes, builtins: swiftBuiltins,
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: swiftStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "c", displayName: "C", lexerName: "cpp",
            extensions: ["c", "h"],
            fileNames: [],
            keywords: cKeywords, types: cTypes, builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: cppLikeStyleMap(), supportsFolding: true
        ),
        LanguageDefinition(
            id: "cpp", displayName: "C++", lexerName: "cpp",
            extensions: ["cpp", "cxx", "cc", "c++", "hpp", "hxx", "hh", "h++", "ipp", "ixx", "inl"],
            fileNames: [],
            keywords: cppKeywords, types: cppTypes, builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: cppLikeStyleMap(), supportsFolding: true
        ),
        LanguageDefinition(
            id: "objc", displayName: "Objective-C / Objective-C++", lexerName: "cpp",
            extensions: ["m", "mm"],
            fileNames: [],
            keywords: objCKeywords, types: cppTypes, builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: cppLikeStyleMap(), supportsFolding: true
        ),
        LanguageDefinition(
            id: "csharp", displayName: "C#", lexerName: "cpp",
            extensions: ["cs", "csx"],
            fileNames: [],
            keywords: csharpKeywords, types: csharpTypes, builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: cppLikeStyleMap(), supportsFolding: true
        ),
        LanguageDefinition(
            id: "java", displayName: "Java", lexerName: "cpp",
            extensions: ["java"],
            fileNames: [],
            keywords: javaKeywords, types: javaTypes, builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: cppLikeStyleMap(), supportsFolding: true
        ),
        LanguageDefinition(
            id: "javascript", displayName: "JavaScript", lexerName: "cpp",
            extensions: ["js", "mjs", "cjs", "jsx"],
            fileNames: [],
            keywords: javascriptKeywords, types: javascriptTypes, builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: cppLikeStyleMap(), supportsFolding: true
        ),
        LanguageDefinition(
            id: "typescript", displayName: "TypeScript", lexerName: "cpp",
            extensions: ["ts", "tsx", "mts", "cts"],
            fileNames: [],
            keywords: typescriptKeywords, types: typescriptTypes, builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: cppLikeStyleMap(), supportsFolding: true
        ),
        LanguageDefinition(
            id: "go", displayName: "Go", lexerName: "cpp",
            extensions: ["go"],
            fileNames: [],
            keywords: goKeywords, types: goTypes, builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: cppLikeStyleMap(), supportsFolding: true
        ),
        LanguageDefinition(
            id: "python", displayName: "Python", lexerName: "python",
            extensions: ["py", "pyw", "pyi", "pyx", "pxd"],
            fileNames: [],
            keywords: pythonKeywords, types: pythonTypes, builtins: [],
            lineComment: "#", blockComment: nil,
            styleMap: pythonStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "ruby", displayName: "Ruby", lexerName: "ruby",
            extensions: ["rb", "rbw", "rake", "gemspec", "ru"],
            fileNames: ["Rakefile", "Gemfile", "Podfile", "Brewfile"],
            keywords: rubyKeywords, types: rubyTypes, builtins: [],
            lineComment: "#", blockComment: ("=begin", "=end"),
            styleMap: rubyStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "rust", displayName: "Rust", lexerName: "rust",
            extensions: ["rs"],
            fileNames: [],
            keywords: rustKeywords, types: rustTypes, builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: rustStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "php", displayName: "PHP", lexerName: "phpscript",
            extensions: ["php", "php3", "php4", "php5", "phtml", "phps"],
            fileNames: [],
            keywords: [], types: [], builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: htmlStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "perl", displayName: "Perl", lexerName: "perl",
            extensions: ["pl", "pm", "t", "pod"],
            fileNames: [],
            keywords: perlKeywords, types: perlTypes, builtins: [],
            lineComment: "#", blockComment: nil,
            styleMap: perlStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "shell", displayName: "Shell", lexerName: "bash",
            extensions: ["sh", "bash", "zsh", "ksh", "ash", "bashrc", "zshrc", "bash_profile", "profile"],
            fileNames: [".bashrc", ".zshrc", ".bash_profile", ".profile", ".zprofile"],
            keywords: shellKeywords, types: [], builtins: shellBuiltins,
            lineComment: "#", blockComment: nil,
            styleMap: shellStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "powershell", displayName: "PowerShell", lexerName: "powershell",
            extensions: ["ps1", "psm1", "psd1", "ps1xml", "pssc"],
            fileNames: [],
            keywords: powershellKeywords, types: [], builtins: powershellCmdlets,
            lineComment: "#", blockComment: ("<#", "#>"),
            styleMap: powershellStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "batch", displayName: "Batch", lexerName: "batch",
            extensions: ["bat", "cmd", "nt"],
            fileNames: [],
            keywords: batchKeywords, types: [], builtins: [],
            lineComment: "rem", blockComment: nil,
            styleMap: batchStyleMap, supportsFolding: false
        ),
        LanguageDefinition(
            id: "dockerfile", displayName: "Dockerfile", lexerName: "bash",
            extensions: ["dockerfile"],
            fileNames: ["Dockerfile", "Containerfile", "dockerfile"],
            keywords: dockerfileKeywords, types: [], builtins: [],
            lineComment: "#", blockComment: nil,
            styleMap: shellStyleMap, supportsFolding: false
        ),
        LanguageDefinition(
            id: "sql", displayName: "SQL", lexerName: "sql",
            extensions: ["sql", "ddl", "dml", "mysql", "pgsql", "plsql", "tsql", "sqlite"],
            fileNames: [],
            keywords: sqlKeywords, types: sqlTypes, builtins: [],
            lineComment: "--", blockComment: ("/*", "*/"),
            styleMap: sqlStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "html", displayName: "HTML", lexerName: "hypertext",
            extensions: ["html", "htm", "xhtml", "shtml", "vue", "svelte", "astro", "hbs", "handlebars"],
            fileNames: [],
            keywords: htmlKeywords, types: [], builtins: [],
            lineComment: nil, blockComment: ("<!--", "-->"),
            styleMap: htmlStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "xml", displayName: "XML", lexerName: "xml",
            extensions: ["xml", "xsd", "xsl", "xslt", "svg", "plist", "xib", "storyboard", "rss",
                         "atom", "pom", "csproj", "vcxproj", "gradle", "resx", "mobileconfig"],
            fileNames: [],
            keywords: xmlKeywords, types: [], builtins: [],
            lineComment: nil, blockComment: ("<!--", "-->"),
            styleMap: htmlStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "css", displayName: "CSS", lexerName: "css",
            extensions: ["css", "scss", "sass", "less"],
            fileNames: [],
            keywords: [], types: [], builtins: [],
            lineComment: "//", blockComment: ("/*", "*/"),
            styleMap: cssStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "json", displayName: "JSON", lexerName: "json",
            extensions: ["json", "jsonl", "ndjson", "geojson", "ipynb", "har", "webmanifest"],
            fileNames: ["composer.lock", "package-lock.json"],
            keywords: [], types: [], builtins: [],
            lineComment: nil, blockComment: nil,
            styleMap: jsonStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "yaml", displayName: "YAML", lexerName: "yaml",
            extensions: ["yaml", "yml"],
            fileNames: [],
            keywords: [], types: [], builtins: [],
            lineComment: "#", blockComment: nil,
            styleMap: yamlStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "toml", displayName: "TOML", lexerName: "toml",
            extensions: ["toml"],
            fileNames: ["Cargo.lock"],
            keywords: [], types: [], builtins: [],
            lineComment: "#", blockComment: nil,
            styleMap: tomlStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "ini", displayName: "INI / Properties", lexerName: "props",
            extensions: ["ini", "cfg", "conf", "properties", "editorconfig", "gitconfig",
                         "gitattributes", "env", "desktop", "service", "plist.ini"],
            fileNames: [".editorconfig", ".gitconfig", ".gitattributes", ".npmrc", ".env"],
            keywords: iniKeywords, types: [], builtins: [],
            lineComment: "#", blockComment: nil,
            styleMap: propsStyleMap, supportsFolding: false
        ),
        LanguageDefinition(
            id: "markdown", displayName: "Markdown", lexerName: "markdown",
            extensions: ["md", "markdown", "mdown", "mkd", "mkdn"],
            fileNames: ["README", "CHANGELOG", "LICENSE.md"],
            keywords: [], types: [], builtins: [],
            lineComment: nil, blockComment: ("<!--", "-->"),
            styleMap: markdownStyleMap, supportsFolding: true
        ),
        LanguageDefinition(
            id: "makefile", displayName: "Makefile", lexerName: "make",
            extensions: ["mak", "mk", "make"],
            fileNames: ["Makefile", "makefile", "GNUmakefile"],
            keywords: [], types: [], builtins: [],
            lineComment: "#", blockComment: nil,
            styleMap: makeStyleMap, supportsFolding: false
        ),
        LanguageDefinition(
            id: "diff", displayName: "Diff", lexerName: "diff",
            extensions: ["diff", "patch"],
            fileNames: [],
            keywords: [], types: [], builtins: [],
            lineComment: nil, blockComment: nil,
            styleMap: diffStyleMap, supportsFolding: false
        ),
        LanguageDefinition(
            id: "visualbasic", displayName: "Visual Basic", lexerName: "vb",
            extensions: ["vb", "vbs", "bas", "frm", "cls"],
            fileNames: [],
            keywords: [], types: [], builtins: [],
            lineComment: "'", blockComment: nil,
            styleMap: [
                Int(SCE_B_DEFAULT): .text,
                Int(SCE_B_COMMENT): .comment,
                Int(SCE_B_COMMENTBLOCK): .comment,
                Int(SCE_B_DOCLINE): .docComment,
                Int(SCE_B_DOCBLOCK): .docComment,
                Int(SCE_B_NUMBER): .number,
                Int(SCE_B_HEXNUMBER): .number,
                Int(SCE_B_BINNUMBER): .number,
                Int(SCE_B_KEYWORD): .keyword,
                Int(SCE_B_KEYWORD2): .keyword,
                Int(SCE_B_KEYWORD3): .keyword,
                Int(SCE_B_KEYWORD4): .keyword,
                Int(SCE_B_STRING): .string,
                Int(SCE_B_STRINGEOL): .error,
                Int(SCE_B_PREPROCESSOR): .preprocessor,
                Int(SCE_B_OPERATOR): .operatorSymbol,
                Int(SCE_B_IDENTIFIER): .identifier,
                Int(SCE_B_DATE): .constant,
                Int(SCE_B_CONSTANT): .constant,
                Int(SCE_B_LABEL): .preprocessor,
                Int(SCE_B_ERROR): .error,
            ],
            supportsFolding: true
        ),
        LanguageDefinition(
            id: "asm", displayName: "Assembly", lexerName: "asm",
            extensions: ["asm", "s"],
            fileNames: [],
            keywords: [], types: [], builtins: [],
            lineComment: ";", blockComment: nil,
            styleMap: [
                Int(SCE_ASM_DEFAULT): .text,
                Int(SCE_ASM_COMMENT): .comment,
                Int(SCE_ASM_COMMENTBLOCK): .comment,
                Int(SCE_ASM_NUMBER): .number,
                Int(SCE_ASM_OPERATOR): .operatorSymbol,
                Int(SCE_ASM_IDENTIFIER): .identifier,
                Int(SCE_ASM_CPUINSTRUCTION): .keyword,
                Int(SCE_ASM_MATHINSTRUCTION): .keywordSecondary,
                Int(SCE_ASM_REGISTER): .type,
                Int(SCE_ASM_DIRECTIVE): .preprocessor,
                Int(SCE_ASM_DIRECTIVEOPERAND): .constant,
                Int(SCE_ASM_COMMENTDIRECTIVE): .docComment,
                Int(SCE_ASM_STRING): .string,
                Int(SCE_ASM_CHARACTER): .character,
                Int(SCE_ASM_STRINGEOL): .error,
                Int(SCE_ASM_EXTINSTRUCTION): .function,
            ],
            supportsFolding: false
        ),
    ]

    // MARK: - Lookup

    private static let byID: [String: LanguageDefinition] = {
        var map: [String: LanguageDefinition] = [:]
        for language in all { map[language.id] = language }
        return map
    }()

    private static let byExtension: [String: LanguageDefinition] = {
        var map: [String: LanguageDefinition] = [:]
        for language in all {
            for ext in language.extensions {
                if map[ext.lowercased()] == nil {
                    map[ext.lowercased()] = language
                }
            }
        }
        return map
    }()

    private static let byFileName: [String: LanguageDefinition] = {
        var map: [String: LanguageDefinition] = [:]
        for language in all {
            for name in language.fileNames {
                if map[name.lowercased()] == nil {
                    map[name.lowercased()] = language
                }
            }
        }
        return map
    }()

    static func language(withID id: String) -> LanguageDefinition {
        byID[id] ?? plainText
    }

    static let plainText: LanguageDefinition = all.first ?? LanguageDefinition(
        id: "plain", displayName: "Plain Text", lexerName: nil,
        extensions: [], fileNames: [], keywords: [], types: [], builtins: [],
        lineComment: nil, blockComment: nil, styleMap: [:], supportsFolding: false
    )

    /// Detects the language for a URL. Explicit user overrides are applied by
    /// the caller and take precedence over this result.
    static func language(for url: URL?) -> LanguageDefinition {
        guard let url else { return plainText }
        let fileName = url.lastPathComponent

        // Compound names such as "foo.d.ts".
        if fileName.lowercased().hasSuffix(".d.ts") {
            return language(withID: "typescript")
        }
        if let exact = byFileName[fileName.lowercased()] {
            return exact
        }
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, let byExt = byExtension[ext] {
            return byExt
        }
        // Files such as "nginx.conf.d" or extension-less names.
        if let dotIndex = fileName.lastIndex(of: "."), dotIndex != fileName.startIndex {
            let trailing = String(fileName[fileName.index(after: dotIndex)...]).lowercased()
            if let byExt = byExtension[trailing] {
                return byExt
            }
        }
        return plainText
    }
}
