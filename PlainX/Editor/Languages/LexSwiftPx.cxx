//
//  LexSwiftPx.cxx
//  PlainX Editor
//
//  A Swift lexer for Scintilla/Lexilla, original to PlainX Editor.
//  Copyright (c) 2026 PlainX Editor contributors. MIT licensed.
//
//  Lexilla 5.4.4 does not include a Swift lexer. PlainX ships this one and
//  installs it through SCI_SETILEXER (see PXSciBridge.mm). Style numbers are
//  PlainX-reserved (PXSwiftStyle* in PXSciBridge.h) and intentionally outside
//  the Lexilla-assigned SCE_ ranges.
//

#include <cassert>
#include <cstring>
#include <string_view>

#include "ILexer.h"
#include "Scintilla.h"
#include "SciLexer.h"

#include "WordList.h"
#include "LexAccessor.h"
#include "Accessor.h"
#include "StyleContext.h"
#include "CharacterSet.h"
#include "LexerModule.h"

using namespace Lexilla;

namespace {

enum PXSwiftStyle {
	pxDefault = 0,
	pxCommentLine = 1,
	pxCommentLineDoc = 2,
	pxCommentBlock = 3,
	pxCommentBlockDoc = 4,
	pxNumber = 5,
	pxKeyword = 6,
	pxType = 7,
	pxString = 8,
	pxStringMultiline = 9,
	pxInterpolation = 10,
	pxAttribute = 11,
	pxPreprocessor = 12,
	pxOperator = 13,
	pxIdentifier = 14,
	pxEscape = 15,
	pxSelfKeyword = 16,
	pxParameter = 17,
};

// PlainX-reserved language identifier for the Swift lexer.
constexpr int SCLEX_PLAINX_SWIFT = 1500;

constexpr bool IsEOLChar(int ch) noexcept {
	return ch == '\r' || ch == '\n';
}

constexpr bool IsIdentifierStart(int ch) noexcept {
	return IsUpperOrLowerCase(ch) || ch == '_' || ch == '$' || ch >= 0x80;
}

constexpr bool IsIdentifierChar(int ch) noexcept {
	return IsAlphaNumeric(ch) || ch == '_' || ch == '$' || ch >= 0x80;
}

constexpr bool IsNumberContinue(int chPrev, int ch) noexcept {
	// digits, hex digits, underscores, and scientific-notation exponents
	if (IsADigit(ch) || IsAHeXDigit(ch) || ch == '_' || ch == '.') {
		return true;
	}
	if ((ch == '+' || ch == '-') && (chPrev == 'e' || chPrev == 'E' || chPrev == 'p' || chPrev == 'P')) {
		return true;
	}
	return false;
}

// Walks backwards, bounded, to determine the nesting depth of an open block
// comment at position startPos. Swift permits nested /* */ comments.
int BlockCommentDepth(Accessor &styler, Sci_PositionU startPos) noexcept {
	constexpr Sci_PositionU maxScanBack = 256 * 1024;
	const Sci_PositionU lowerBound = (startPos > maxScanBack) ? (startPos - maxScanBack) : 0;
	int depth = 1;
	for (Sci_PositionU pos = startPos; pos > lowerBound + 1;) {
		pos--;
		const char ch = styler.SafeGetCharAt(pos);
		if (ch == '/' && styler.SafeGetCharAt(pos + 1) == '*') {
			depth++;
			if (pos >= 1) {
				pos--;
			}
		} else if (ch == '*' && styler.SafeGetCharAt(pos + 1) == '/') {
			depth--;
			if (depth <= 0) {
				return 1;
			}
			if (pos >= 1) {
				pos--;
			}
		}
	}
	return (depth > 0) ? depth : 1;
}

void ColouriseSwiftDoc(Sci_PositionU startPos, Sci_Position length, int initStyle,
		WordList *keywordlists[], Accessor &styler) {
	WordList &keywords = *keywordlists[0];
	WordList &types = *keywordlists[1];
	WordList &builtins = *keywordlists[2];

	StyleContext sc(startPos, static_cast<Sci_PositionU>(length), initStyle, styler);

	int blockCommentDepth = 1;
	if (initStyle == pxCommentBlock || initStyle == pxCommentBlockDoc) {
		blockCommentDepth = (initStyle == pxCommentBlockDoc) ? 1 : BlockCommentDepth(styler, startPos);
	}
	// Where a string returns to when it terminates.
	int stringReturnState = pxDefault;
	// Where an escape sequence returns to when it terminates.
	int escapeReturnState = pxString;
	// Where an interpolation returns to when its closing ')' is seen.
	int interpolationReturnState = pxString;
	int interpolationDepth = 0;

	while (sc.More()) {
		if (sc.atLineStart) {
			if (sc.state == pxCommentLine || sc.state == pxCommentLineDoc || sc.state == pxPreprocessor) {
				sc.SetState(pxDefault);
			}
			if (sc.state == pxInterpolation && interpolationReturnState == pxString) {
				// Unterminated single-line string interpolation.
				sc.SetState(pxDefault);
			}
		}

		switch (sc.state) {
		case pxDefault:
			if (sc.Match("///") || sc.Match("//!")) {
				sc.SetState(pxCommentLineDoc);
			} else if (sc.Match("//")) {
				sc.SetState(pxCommentLine);
			} else if (sc.Match("/**") || sc.Match("/*!")) {
				sc.SetState(pxCommentBlockDoc);
				blockCommentDepth = 1;
			} else if (sc.Match("/*")) {
				sc.SetState(pxCommentBlock);
				blockCommentDepth = 1;
			} else if (sc.ch == '"') {
				stringReturnState = pxDefault;
				if (sc.Match("\"\"\"")) {
					sc.SetState(pxStringMultiline);
				} else {
					sc.SetState(pxString);
				}
			} else if (sc.ch == '#' && sc.chNext == '"') {
				// Raw string literal #"..."# — treated as an ordinary string.
				stringReturnState = pxDefault;
				sc.Forward();
				if (sc.Match("\"\"\"")) {
					sc.SetState(pxStringMultiline);
				} else {
					sc.SetState(pxString);
				}
			} else if (sc.ch == '#' && IsUpperOrLowerCase(sc.chNext)) {
				sc.SetState(pxPreprocessor);
			} else if (sc.ch == '@' && IsIdentifierStart(sc.chNext)) {
				sc.SetState(pxAttribute);
			} else if (sc.ch == '`' && IsIdentifierStart(sc.chNext)) {
				sc.SetState(pxIdentifier);
			} else if (IsADigit(sc.ch) || (sc.ch == '.' && IsADigit(sc.chNext))) {
				sc.SetState(pxNumber);
			} else if (IsIdentifierStart(sc.ch)) {
				sc.SetState(pxIdentifier);
			}
			// Always consume the character; state transitions above apply from
			// this position onward.
			sc.Forward();
			break;

		case pxIdentifier: {
			if (sc.ch == '`') {
				sc.ForwardSetState(pxDefault);
				break;
			}
			if (!IsIdentifierChar(sc.ch)) {
				char s[128];
				sc.GetCurrent(s, sizeof(s));
				if (strcmp(s, "self") == 0 || strcmp(s, "Self") == 0 || strcmp(s, "super") == 0) {
					sc.ChangeState(pxSelfKeyword);
				} else if (keywords.InList(s)) {
					sc.ChangeState(pxKeyword);
				} else if (types.InList(s) || builtins.InList(s)) {
					sc.ChangeState(pxType);
				} else if (IsUpperCase(s[0])) {
					sc.ChangeState(pxType);
				}
				sc.SetState(pxDefault);
				continue;
			}
			if (sc.ch == '$' && IsADigit(sc.chNext)) {
				sc.ChangeState(pxParameter);
			}
			sc.Forward();
			break;
		}

		case pxNumber:
			if (!IsNumberContinue(sc.chPrev, sc.ch)) {
				sc.SetState(pxDefault);
				continue;
			}
			sc.Forward();
			break;

		case pxAttribute:
			if (!IsIdentifierChar(sc.ch)) {
				sc.SetState(pxDefault);
				continue;
			}
			sc.Forward();
			break;

		case pxCommentLine:
		case pxCommentLineDoc:
		case pxPreprocessor:
			if (IsEOLChar(sc.ch)) {
				sc.SetState(pxDefault);
			} else {
				sc.Forward();
			}
			break;

		case pxCommentBlock:
		case pxCommentBlockDoc:
			if (sc.state == pxCommentBlock && sc.Match("/*")) {
				blockCommentDepth++;
				sc.Forward(2);
			} else if (sc.Match("*/")) {
				blockCommentDepth--;
				sc.Forward(2);
				if (blockCommentDepth <= 0) {
					sc.SetState(pxDefault);
				}
			} else {
				sc.Forward();
			}
			break;

		case pxString:
		case pxStringMultiline: {
			const bool multiline = (sc.state == pxStringMultiline);
			if (!multiline && IsEOLChar(sc.ch)) {
				sc.SetState(stringReturnState);
				continue;
			}
			if (multiline && sc.Match("\"\"\"")) {
				sc.Forward(3);
				sc.SetState(stringReturnState);
				continue;
			}
			if (!multiline && sc.ch == '"') {
				sc.Forward();
				sc.SetState(stringReturnState);
				continue;
			}
			if (sc.ch == '\\' && sc.chNext == '(') {
				interpolationReturnState = sc.state;
				interpolationDepth = 0;
				sc.Forward(2);
				sc.SetState(pxInterpolation);
				continue;
			}
			if (sc.ch == '\\') {
				escapeReturnState = sc.state;
				sc.SetState(pxEscape);
				sc.Forward();
				continue;
			}
			sc.Forward();
			break;
		}

		case pxEscape:
			if (sc.ch == 'u' && sc.chNext == '{') {
				sc.Forward(2);
				while (sc.More() && sc.ch != '}' && !IsEOLChar(sc.ch)) {
					sc.Forward();
				}
				if (sc.ch == '}') {
					sc.Forward();
				}
			} else if (sc.More() && !IsEOLChar(sc.ch)) {
				sc.Forward();
			}
			sc.SetState(escapeReturnState);
			break;

		case pxInterpolation:
			// Interpolation contents are styled uniformly; nested strings are
			// still recognised so that a ')' inside them does not close the
			// interpolation early.
			if (sc.ch == '(') {
				interpolationDepth++;
				sc.Forward();
			} else if (sc.ch == ')') {
				if (interpolationDepth == 0) {
					sc.Forward();
					sc.SetState(interpolationReturnState);
				} else {
					interpolationDepth--;
					sc.Forward();
				}
			} else if (sc.Match("\"\"\"")) {
				stringReturnState = pxInterpolation;
				sc.SetState(pxStringMultiline);
			} else if (sc.ch == '"') {
				stringReturnState = pxInterpolation;
				sc.SetState(pxString);
			} else {
				sc.Forward();
			}
			break;

		default:
			sc.SetState(pxDefault);
			sc.Forward();
			break;
		}
	}
	sc.Complete();
	(void)pxOperator;
}

// Brace-based folding. Braces inside comments/strings are ignored by
// consulting the per-byte styles written by the colouriser.
void FoldSwiftDoc(Sci_PositionU startPos, Sci_Position lengthDoc, int, WordList *[], Accessor &styler) {
	const Sci_Position docLength = styler.Length();
	if (docLength <= 0) {
		return;
	}
	Sci_Position endPos = static_cast<Sci_Position>(startPos) + lengthDoc;
	if (endPos > docLength) {
		endPos = docLength;
	}

	Sci_Position lineCurrent = styler.GetLine(startPos);
	const Sci_Position maxLine = styler.GetLine(endPos > 0 ? endPos - 1 : 0);

	int levelCurrent = SC_FOLDLEVELBASE;
	if (lineCurrent > 0) {
		levelCurrent = styler.LevelAt(lineCurrent - 1) & SC_FOLDLEVELNUMBERMASK;
	}

	for (; lineCurrent <= maxLine; lineCurrent++) {
		const Sci_PositionU lineStart = static_cast<Sci_PositionU>(styler.LineStart(lineCurrent));
		Sci_PositionU lineEnd = static_cast<Sci_PositionU>(styler.LineStart(lineCurrent + 1));
		if (lineEnd > static_cast<Sci_PositionU>(docLength)) {
			lineEnd = static_cast<Sci_PositionU>(docLength);
		}

		int delta = 0;
		bool firstNonSpaceFound = false;
		bool startsWithCloseBrace = false;
		for (Sci_PositionU pos = lineStart; pos < lineEnd; pos++) {
			const char ch = styler.SafeGetCharAt(pos);
			if (!firstNonSpaceFound && ch != ' ' && ch != '\t') {
				firstNonSpaceFound = true;
				startsWithCloseBrace = (ch == '}');
			}
			const int style = styler.StyleAt(pos);
			if (style == pxCommentLine || style == pxCommentLineDoc || style == pxCommentBlock ||
			    style == pxCommentBlockDoc || style == pxString || style == pxStringMultiline ||
			    style == pxEscape || style == pxPreprocessor || style == pxInterpolation) {
				continue;
			}
			if (ch == '{') {
				delta++;
			} else if (ch == '}') {
				delta--;
			}
		}

		int levelNext = levelCurrent + delta;
		if (levelNext < SC_FOLDLEVELBASE) {
			levelNext = SC_FOLDLEVELBASE;
		}

		int levelToSet = levelCurrent;
		if (startsWithCloseBrace && levelNext < levelCurrent) {
			// "} else {" lines visually join the parent block.
			levelToSet = levelNext;
		}
		int flags = 0;
		if (levelNext > levelToSet) {
			flags |= SC_FOLDLEVELHEADERFLAG;
		}
		styler.SetLevel(lineCurrent, (levelToSet & SC_FOLDLEVELNUMBERMASK) | flags | ((levelNext & SC_FOLDLEVELNUMBERMASK) << 16));
		levelCurrent = levelNext;
	}
}

const char *const swiftWordListDesc[] = {
	"Keywords",
	"Types",
	"Built-in values",
	nullptr,
};

}

extern const Lexilla::LexerModule lmPlainXSwift(SCLEX_PLAINX_SWIFT, ColouriseSwiftDoc, "swift", FoldSwiftDoc, swiftWordListDesc);
