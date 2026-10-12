//
//  PlainX-Bridging-Header.h
//  PlainX Editor
//
//  Exposes the vendored Scintilla / Lexilla C and C++ APIs to Swift.
//  Numeric Scintilla message IDs must only be referenced inside
//  Editor/ScintillaFacade.swift; the rest of the application talks to the
//  editor through the facade.
//

#import <Cocoa/Cocoa.h>

#import "Scintilla.h"
#import "ScintillaView.h"
#import "SciLexer.h"

#import "PXSciBridge.h"
