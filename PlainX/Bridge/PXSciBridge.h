//
//  PXSciBridge.h
//  PlainX Editor
//
//  Small Objective-C++ layer between Swift and the Scintilla/Lexilla
//  C++ world. Swift must not touch raw C++ types; everything crosses this
//  boundary as C-compatible values.
//

#import <Foundation/Foundation.h>
#import "ScintillaView.h"

NS_ASSUME_NONNULL_BEGIN

/// Style IDs produced by PlainX's bundled Swift lexer (LexSwiftPx.cxx).
/// These are PlainX-reserved style numbers, intentionally outside the
/// Lexilla-assigned SCE_ ranges.
typedef NS_ENUM(NSInteger, PXSwiftStyle) {
    PXSwiftStyleDefault = 0,
    PXSwiftStyleCommentLine = 1,
    PXSwiftStyleCommentLineDoc = 2,
    PXSwiftStyleCommentBlock = 3,
    PXSwiftStyleCommentBlockDoc = 4,
    PXSwiftStyleNumber = 5,
    PXSwiftStyleKeyword = 6,
    PXSwiftStyleType = 7,
    PXSwiftStyleString = 8,
    PXSwiftStyleStringMultiline = 9,
    PXSwiftStyleInterpolation = 10,
    PXSwiftStyleAttribute = 11,
    PXSwiftStylePreprocessor = 12,
    PXSwiftStyleOperator = 13,
    PXSwiftStyleIdentifier = 14,
    PXSwiftStyleEscape = 15,
    PXSwiftStyleSelfKeyword = 16,
    PXSwiftStyleParameter = 17,
};

@interface PXSciBridge : NSObject

/// Creates a lexer by name. PlainX custom lexers ("swift") are checked first,
/// then the Lexilla catalogue. Returns an owning pointer that Scintilla takes
/// ownership of when passed to -applyLexer:toView:.
+ (nullable void *)createLexerNamed:(NSString *)name;

/// Applies a lexer created by +createLexerNamed: to a Scintilla view, or
/// clears the lexer when nil is passed. Scintilla takes ownership of the
/// lexer pointer when non-nil.
+ (void)applyLexer:(nullable void *)lexer toView:(ScintillaView *)view;

/// Installs the PlainX Swift lexer's style→keyword mapping and applies the
/// supplied keyword lists (space-separated words) to the view.
+ (void)applySwiftLexerToView:(ScintillaView *)view
                 keywords:(NSString *)keywords
                    types:(NSString *)types
                 builtins:(NSString *)builtins;

/// Lexilla library version string (for diagnostics).
+ (NSString *)lexillaVersion;

@end

NS_ASSUME_NONNULL_END
