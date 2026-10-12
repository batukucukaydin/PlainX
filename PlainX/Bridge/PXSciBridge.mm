//
//  PXSciBridge.mm
//  PlainX Editor
//

#import "PXSciBridge.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>
#include <vector>
#include <map>
#include <set>

#include "ILexer.h"
#include "PropSetSimple.h"
#include "WordList.h"
#include "LexAccessor.h"
#include "Accessor.h"
#include "LexerModule.h"
#include "LexerBase.h"
#include "LexerSimple.h"

// PlainX custom Swift lexer (defined in LexSwiftPx.cxx, compiled into the app
// target). Lexilla 5.4.4 does not ship a Swift lexer.
extern const Lexilla::LexerModule lmPlainXSwift;

// Curated Lexilla lexer modules compiled into PlainX. Lexilla's aggregate
// Lexilla.cxx (which references every lexer) is intentionally not linked;
// this table is the complete lexer factory surface of the app.
extern const Lexilla::LexerModule lmAsm;
extern const Lexilla::LexerModule lmBash;
extern const Lexilla::LexerModule lmBatch;
extern const Lexilla::LexerModule lmCPP;
extern const Lexilla::LexerModule lmCss;
extern const Lexilla::LexerModule lmCIL;
extern const Lexilla::LexerModule lmCmake;
extern const Lexilla::LexerModule lmConf;
extern const Lexilla::LexerModule lmDiff;
extern const Lexilla::LexerModule lmHTML;
extern const Lexilla::LexerModule lmXML;
extern const Lexilla::LexerModule lmPHPSCRIPT;
extern const Lexilla::LexerModule lmJSON;
extern const Lexilla::LexerModule lmMake;
extern const Lexilla::LexerModule lmMarkdown;
extern const Lexilla::LexerModule lmMySQL;
extern const Lexilla::LexerModule lmPerl;
extern const Lexilla::LexerModule lmPowerShell;
extern const Lexilla::LexerModule lmProps;
extern const Lexilla::LexerModule lmPython;
extern const Lexilla::LexerModule lmRuby;
extern const Lexilla::LexerModule lmRust;
extern const Lexilla::LexerModule lmSQL;
extern const Lexilla::LexerModule lmTOML;
extern const Lexilla::LexerModule lmYAML;
extern const Lexilla::LexerModule lmVB;

@implementation PXSciBridge

+ (const Lexilla::LexerModule *)moduleForName:(const std::string &)name {
    using ModuleTable = std::map<std::string, const Lexilla::LexerModule *>;
    static const ModuleTable table = [] {
        ModuleTable modules;
        modules["swift"] = &lmPlainXSwift;
        modules["asm"] = &lmAsm;
        modules["bash"] = &lmBash;
        modules["batch"] = &lmBatch;
        modules["cpp"] = &lmCPP;
        modules["css"] = &lmCss;
        modules["cil"] = &lmCIL;
        modules["cmake"] = &lmCmake;
        modules["conf"] = &lmConf;
        modules["diff"] = &lmDiff;
        modules["hypertext"] = &lmHTML;
        modules["xml"] = &lmXML;
        modules["phpscript"] = &lmPHPSCRIPT;
        modules["php"] = &lmPHPSCRIPT;
        modules["json"] = &lmJSON;
        modules["makefile"] = &lmMake;
        modules["markdown"] = &lmMarkdown;
        modules["mysql"] = &lmMySQL;
        modules["perl"] = &lmPerl;
        modules["powershell"] = &lmPowerShell;
        modules["props"] = &lmProps;
        modules["python"] = &lmPython;
        modules["ruby"] = &lmRuby;
        modules["rust"] = &lmRust;
        modules["sql"] = &lmSQL;
        modules["toml"] = &lmTOML;
        modules["yaml"] = &lmYAML;
        modules["vb"] = &lmVB;
        return modules;
    }();
    const auto found = table.find(name);
    return found == table.end() ? nullptr : found->second;
}

+ (void *)createLexerNamed:(NSString *)name {
    if (name == nil) {
        return nullptr;
    }
    const std::string key(name.UTF8String ?: "");
    const Lexilla::LexerModule *module = [self moduleForName:key];
    if (module == nullptr) {
        return nullptr;
    }
    return module->Create();
}

+ (void)applyLexer:(void *)lexer toView:(ScintillaView *)view {
    // SCI_SETILEXER takes the ILexer5 pointer in lParam.
    [view message:SCI_SETILEXER wParam:0 lParam:(sptr_t)lexer];
}

+ (void)applySwiftLexerToView:(ScintillaView *)view
                     keywords:(NSString *)keywords
                        types:(NSString *)types
                     builtins:(NSString *)builtins {
    if (view == nil) {
        return;
    }
    [self applyLexer:[self createLexerNamed:@"swift"] toView:view];
    [view message:SCI_SETKEYWORDS wParam:0 lParam:(sptr_t)keywords.UTF8String];
    [view message:SCI_SETKEYWORDS wParam:1 lParam:(sptr_t)types.UTF8String];
    [view message:SCI_SETKEYWORDS wParam:2 lParam:(sptr_t)builtins.UTF8String];
}

+ (NSString *)lexillaVersion {
    return @"5.4.4";
}

@end
