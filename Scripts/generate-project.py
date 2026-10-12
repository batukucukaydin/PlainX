#!/usr/bin/env python3
"""
PlainX Editor - Xcode project generator.

Generates PlainX.xcodeproj deterministically:
  * PlainX          - the application target (Swift + Objective-C++), whose Swift
                      sources and resources live in the PlainX/ synchronized folder
                      group (Xcode 16+ file-system synchronized groups), so new
                      source files are picked up automatically.
  * PlainXTests     - unit / integration / performance tests (synchronized group).
  * PlainXUITests   - UI tests (synchronized group).

Vendored Scintilla 5.5.4 and Lexilla 5.4.4 sources are enumerated explicitly and
compiled directly into the application target. Lexilla lexers are curated to the
language set that PlainX Editor ships in v1.0.

Run from anywhere:  python3 Scripts/generate-project.py
"""

from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = "PlainX"
PROJECT_DIR = ROOT / f"{PROJECT_NAME}.xcodeproj"

# ---------------------------------------------------------------------------
# Curated Lexilla lexer set (v1.0 language coverage).
# Scintilla 5.5.4 / Lexilla 5.4.4 do not ship Swift, Java, Go, TypeScript, or
# C# dedicated lexers; those are mapped in the app's LanguageRegistry to the
# closest shipped lexer or to the PlainX custom Swift lexer.
# ---------------------------------------------------------------------------
LEXILLA_LEXERS = [
    "LexAsm", "LexBash", "LexBatch", "LexCPP", "LexCSS", "LexCIL", "LexCmake",
    "LexConf", "LexDiff", "LexHTML", "LexJSON", "LexMake", "LexMarkdown",
    "LexMySQL", "LexPerl", "LexPowerShell", "LexProps", "LexPython",
    "LexRuby", "LexRust", "LexSQL", "LexTOML", "LexYAML", "LexVB",
]


def uuid_for(key: str) -> str:
    """Deterministic 24-hex-character object identifier."""
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def collect_vendor_sources() -> list[Path]:
    files: list[Path] = []

    scintilla_src = ROOT / "Vendor/scintilla/src"
    files += sorted(p for p in scintilla_src.glob("*.cxx") if p.suffix == ".cxx")

    cocoa = ROOT / "Vendor/scintilla/cocoa"
    files += sorted(cocoa.glob("*.mm"))

    lexilla_src = ROOT / "Vendor/lexilla/src"
    # Lexilla.cxx aggregates every lexer in the catalogue; PlainX links only a
    # curated lexer set and provides its own factory in PXSciBridge.mm.
    files += sorted(p for p in lexilla_src.glob("*.cxx") if p.name != "Lexilla.cxx")

    lexlib = ROOT / "Vendor/lexilla/lexlib"
    files += sorted(p for p in lexlib.glob("*.cxx"))

    lexers = ROOT / "Vendor/lexilla/lexers"
    for name in LEXILLA_LEXERS:
        candidate = lexers / f"{name}.cxx"
        if not candidate.exists():
            sys.exit(f"error: curated lexer missing: {candidate}")
        files.append(candidate)

    return files


class ProjectGenerator:
    def __init__(self) -> None:
        self.objects: list[str] = []  # raw pbxproj object strings
        self.vendor_sources = collect_vendor_sources()

    # -- helpers ------------------------------------------------------------

    def obj(self, key: str, body: str) -> str:
        uid = uuid_for(key)
        self.objects.append(f"\t\t{uid} /* {key} */ = {{\n{body}\t\t}};")
        return uid

    # -- sections -----------------------------------------------------------

    def emit_build_files(self) -> tuple[dict[Path, str], list[str]]:
        refs: dict[Path, str] = {}
        lines = ["/* Begin PBXBuildFile section */"]
        for path in self.vendor_sources:
            file_ref = uuid_for(f"fileref:{rel(path)}")
            build_file = uuid_for(f"buildfile:{rel(path)}")
            lines.append(
                f"\t\t{build_file} /* {path.name} in Sources */ = {{isa = PBXBuildFile; "
                f"fileRef = {file_ref} /* {path.name} */; }};"
            )
            refs[path] = file_ref
        lines.append("/* End PBXBuildFile section */")
        self.objects.append("\n".join(lines) + "\n")
        return refs, []

    def emit_file_references(self, vendor_refs: dict[Path, str]) -> None:
        lines = ["/* Begin PBXFileReference section */"]
        for path, uid in sorted(vendor_refs.items(), key=lambda kv: rel(kv[0])):
            ext = path.suffix.lstrip(".")
            lines.append(
                f"\t\t{uid} /* {path.name} */ = {{isa = PBXFileReference; "
                f"lastKnownFileType = sourcecode.{'objcpp' if ext == 'mm' else 'cpp'}.{ext}; "
                f'name = {path.name}; path = "{rel(path)}"; sourceTree = "<group>"; }};'
            )
        product_specs = [
            ("PlainX", "app", "PlainX.app"),
            ("PlainXTests", "bundle.unit-test", "PlainXTests.xctest"),
            ("PlainXUITests", "bundle.ui-testing", "PlainXUITests.xctest"),
        ]
        for product, kind, product_path in product_specs:
            lines.append(
                f"\t\t{uuid_for('product:' + product)} /* {product} */ = {{isa = PBXFileReference; "
                f"explicitFileType = wrapper.{kind}; includeInIndex = 0; "
                f'path = "{product_path}"; sourceTree = BUILT_PRODUCTS_DIR; }};'
            )
        lines.append(
            f"\t\t{uuid_for('fileref:Config/Info.plist')} /* Info.plist */ = {{isa = PBXFileReference; "
            'lastKnownFileType = text.plist.xml; name = Info.plist; path = "Config/Info.plist"; sourceTree = "<group>"; };'
        )
        lines.append("/* End PBXFileReference section */")
        self.objects.append("\n".join(lines) + "\n")

    def emit_groups(self, vendor_refs: dict[Path, str]) -> None:
        main_group = uuid_for("group:main")

        vendor_children = []
        scintilla_children = []
        lexilla_children = []

        for path, uid in sorted(vendor_refs.items(), key=lambda kv: rel(kv[0])):
            r = rel(path)
            entry = f"\t\t\t\t{uid} /* {path.name} */,\n"
            if r.startswith("Vendor/scintilla/"):
                scintilla_children.append(entry)
            else:
                lexilla_children.append(entry)

        scintilla_group = self.obj(
            "group:Vendor/scintilla",
            "\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" + "".join(scintilla_children) +
            "\t\t\t);\n\t\t\tname = scintilla;\n\t\t\tsourceTree = \"<group>\";\n"
        )
        lexilla_group = self.obj(
            "group:Vendor/lexilla",
            "\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" + "".join(lexilla_children) +
            "\t\t\t);\n\t\t\tname = lexilla;\n\t\t\tsourceTree = \"<group>\";\n"
        )
        vendor_group = self.obj(
            "group:Vendor",
            "\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
            f"\t\t\t\t{scintilla_group} /* scintilla */,\n"
            f"\t\t\t\t{lexilla_group} /* lexilla */,\n"
            "\t\t\t);\n\t\t\tname = Vendor;\n\t\t\tsourceTree = \"<group>\";\n"
        )

        sync_groups = []
        for name in ("PlainX", "PlainXTests", "PlainXUITests"):
            sync_groups.append(self.obj(
                f"syncgroup:{name}",
                f"\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = {name};\n\t\t\tsourceTree = \"<group>\";\n"
            ))

        products_children = "".join(
            f"\t\t\t\t{uuid_for('product:' + p)} /* {p} */,\n" for p in ("PlainX", "PlainXTests", "PlainXUITests")
        )
        products_group = self.obj(
            "group:Products",
            "\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" + products_children +
            "\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n"
        )

        self.obj(
            "group:main",
            "\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
            f"\t\t\t\t{sync_groups[0]} /* PlainX */,\n"
            f"\t\t\t\t{sync_groups[1]} /* PlainXTests */,\n"
            f"\t\t\t\t{sync_groups[2]} /* PlainXUITests */,\n"
            f"\t\t\t\t{uuid_for('fileref:Config/Info.plist')} /* Info.plist */,\n"
            f"\t\t\t\t{vendor_group} /* Vendor */,\n"
            f"\t\t\t\t{products_group} /* Products */,\n"
            "\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n"
        )
        self.main_group = main_group
        self.products_group = products_group

    def emit_phases_and_targets(self, vendor_refs: dict[Path, str]) -> None:
        sources_children = "".join(
            f"\t\t\t\t{uuid_for('buildfile:' + rel(p))} /* {p.name} in Sources */,\n"
            for p in self.vendor_sources
        )
        sources_phase = self.obj(
            "phase:sources:app",
            "\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n" +
            sources_children + "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        )
        frameworks_phase = self.obj(
            "phase:frameworks:app",
            "\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        )
        resources_phase = self.obj(
            "phase:resources:app",
            "\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        )
        # Codesign rejects bundles containing extended attributes such as
        # com.apple.lastuseddate; strip them before signing runs.
        strip_xattrs_phase = self.obj(
            "phase:xattrs:app",
            "\t\t\tisa = PBXShellScriptBuildPhase;\n"
            "\t\t\talwaysOutOfDate = 1;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\tinputFileListPaths = (\n\t\t\t);\n"
            "\t\t\tinputPaths = (\n\t\t\t);\n"
            "\t\t\tname = \"Strip Extended Attributes\";\n"
            "\t\t\toutputFileListPaths = (\n\t\t\t);\n"
            "\t\t\toutputPaths = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            "\t\t\tshellPath = /bin/sh;\n"
            "\t\t\tshellScript = \"xattr -cr \\\"$TARGET_BUILD_DIR/$WRAPPER_NAME\\\" 2>/dev/null || true\\n\";\n"
        )

        empty_sources = self.obj(
            "phase:sources:tests",
            "\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        )
        empty_resources = self.obj(
            "phase:resources:tests",
            "\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        )
        empty_frameworks = self.obj(
            "phase:frameworks:tests",
            "\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        )
        ui_sources = self.obj(
            "phase:sources:uitests",
            "\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        )
        ui_frameworks = self.obj(
            "phase:frameworks:uitests",
            "\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        )
        ui_resources = self.obj(
            "phase:resources:uitests",
            "\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        )

        # Target dependencies (tests -> app)
        for test_target in ("PlainXTests", "PlainXUITests"):
            proxy = self.obj(
                f"proxy:{test_target}",
                f"\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {uuid_for('project')};\n"
                "\t\t\tproxyType = 1;\n"
                f"\t\t\tremoteGlobalIDString = {uuid_for('target:PlainX')};\n"
                "\t\t\tremoteInfo = PlainX;\n"
            )
            self.obj(
                f"dependency:{test_target}",
                f"\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {uuid_for('target:PlainX')};\n"
                f"\t\t\ttargetProxy = {proxy};\n"
            )

        self.obj(
            "target:PlainX",
            "\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {uuid_for('configlist:PlainX')};\n"
            "\t\t\tbuildPhases = (\n"
            f"\t\t\t\t{sources_phase} /* Sources */,\n"
            f"\t\t\t\t{frameworks_phase} /* Frameworks */,\n"
            f"\t\t\t\t{resources_phase} /* Resources */,\n"
            f"\t\t\t\t{strip_xattrs_phase} /* Strip Extended Attributes */,\n"
            "\t\t\t);\n"
            "\t\t\tbuildRules = (\n\t\t\t);\n"
            "\t\t\tdependencies = (\n\t\t\t);\n"
            f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{uuid_for('syncgroup:PlainX')} /* PlainX */,\n\t\t\t);\n"
            "\t\t\tname = PlainX;\n"
            f"\t\t\tproductName = PlainX;\n"
            f"\t\t\tproductReference = {uuid_for('product:PlainX')} /* PlainX */;\n"
            "\t\t\tproductType = \"com.apple.product-type.application\";\n"
        )

        self.obj(
            "target:PlainXTests",
            "\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {uuid_for('configlist:PlainXTests')};\n"
            "\t\t\tbuildPhases = (\n"
            f"\t\t\t\t{empty_sources} /* Sources */,\n"
            f"\t\t\t\t{empty_frameworks} /* Frameworks */,\n"
            f"\t\t\t\t{empty_resources} /* Resources */,\n"
            "\t\t\t);\n"
            "\t\t\tbuildRules = (\n\t\t\t);\n"
            "\t\t\tdependencies = (\n"
            f"\t\t\t\t{uuid_for('dependency:PlainXTests')} /* PBXTargetDependency */,\n"
            "\t\t\t);\n"
            f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{uuid_for('syncgroup:PlainXTests')} /* PlainXTests */,\n\t\t\t);\n"
            "\t\t\tname = PlainXTests;\n"
            f"\t\t\tproductName = PlainXTests;\n"
            f"\t\t\tproductReference = {uuid_for('product:PlainXTests')} /* PlainXTests */;\n"
            "\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";\n"
        )

        self.obj(
            "target:PlainXUITests",
            "\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {uuid_for('configlist:PlainXUITests')};\n"
            "\t\t\tbuildPhases = (\n"
            f"\t\t\t\t{ui_sources} /* Sources */,\n"
            f"\t\t\t\t{ui_frameworks} /* Frameworks */,\n"
            f"\t\t\t\t{ui_resources} /* Resources */,\n"
            "\t\t\t);\n"
            "\t\t\tbuildRules = (\n\t\t\t);\n"
            "\t\t\tdependencies = (\n"
            f"\t\t\t\t{uuid_for('dependency:PlainXUITests')} /* PBXTargetDependency */,\n"
            "\t\t\t);\n"
            f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{uuid_for('syncgroup:PlainXUITests')} /* PlainXUITests */,\n\t\t\t);\n"
            "\t\t\tname = PlainXUITests;\n"
            f"\t\t\tproductName = PlainXUITests;\n"
            f"\t\t\tproductReference = {uuid_for('product:PlainXUITests')} /* PlainXUITests */;\n"
            "\t\t\tproductType = \"com.apple.product-type.bundle.ui-testing\";\n"
        )

    def emit_project(self) -> None:
        self.obj(
            "project",
            "\t\t\tisa = PBXProject;\n"
            "\t\t\tattributes = {\n"
            "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
            "\t\t\t\tLastSwiftUpdateCheck = 1600;\n"
            "\t\t\t\tLastUpgradeCheck = 1600;\n"
            "\t\t\t\tTargetAttributes = {\n"
            f"\t\t\t\t\t{uuid_for('target:PlainX')} = {{CreatedOnToolsVersion = 16.0; }};\n"
            f"\t\t\t\t\t{uuid_for('target:PlainXTests')} = {{CreatedOnToolsVersion = 16.0; TestTargetID = {uuid_for('target:PlainX')}; }};\n"
            f"\t\t\t\t\t{uuid_for('target:PlainXUITests')} = {{CreatedOnToolsVersion = 16.0; TestTargetID = {uuid_for('target:PlainX')}; }};\n"
            "\t\t\t\t};\n"
            "\t\t\t};\n"
            "\t\t\tbuildConfigurationList = " + uuid_for("configlist:project") + ";\n"
            "\t\t\tdevelopmentRegion = en;\n"
            "\t\t\thasScannedForEncodings = 0;\n"
            "\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
            f"\t\t\tmainGroup = {uuid_for('group:main')};\n"
            f"\t\t\tproductRefGroup = {uuid_for('group:Products')} /* Products */;\n"
            "\t\t\tprojectDirPath = \"\";\n"
            "\t\t\tprojectRoot = \"\";\n"
            "\t\t\ttargets = (\n"
            f"\t\t\t\t{uuid_for('target:PlainX')} /* PlainX */,\n"
            f"\t\t\t\t{uuid_for('target:PlainXTests')} /* PlainXTests */,\n"
            f"\t\t\t\t{uuid_for('target:PlainXUITests')} /* PlainXUITests */,\n"
            "\t\t\t);\n"
        )

    def emit_configurations(self) -> None:
        shared_debug = {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_ANALYZER_NONNULL": "YES",
            "CLANG_CXX_LANGUAGE_STANDARD": '"c++17"',
            "CLANG_CXX_LIBRARY": '"libc++"',
            "CLANG_ENABLE_MODULES": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES",
            "CLANG_ENABLE_OBJC_WEAK": "YES",
            "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
            "CLANG_WARN_BOOL_CONVERSION": "YES",
            "CLANG_WARN_COMMA": "YES",
            "CLANG_WARN_CONSTANT_CONVERSION": "YES",
            "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
            "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
            "CLANG_WARN_DOCUMENTATION_COMMENTS": "NO",
            "CLANG_WARN_EMPTY_BODY": "YES",
            "CLANG_WARN_ENUM_CONVERSION": "YES",
            "CLANG_WARN_INFINITE_RECURSION": "YES",
            "CLANG_WARN_INT_CONVERSION": "YES",
            "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
            "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
            "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
            "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
            "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
            "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
            "CLANG_WARN_STRICT_PROTOTYPES": "YES",
            "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
            "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
            "CLANG_WARN_UNREACHABLE_CODE": "YES",
            "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
            "COPY_PHASE_STRIP": "NO",
            "ENABLE_STRICT_OBJC_MSGSEND": "YES",
            "GCC_C_LANGUAGE_STANDARD": "gnu17",
            "GCC_NO_COMMON_BLOCKS": "YES",
            "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"SCI_LEXER=1",\n\t\t\t\t)',
            "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
            "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
            "GCC_WARN_UNDECLARED_SELECTOR": "YES",
            "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
            "GCC_WARN_UNUSED_FUNCTION": "YES",
            "GCC_WARN_UNUSED_VARIABLE": "YES",
            "HEADER_SEARCH_PATHS": '(\n\t\t\t\t\t"$(SRCROOT)/Vendor/scintilla/include",\n\t\t\t\t\t"$(SRCROOT)/Vendor/scintilla/src",\n\t\t\t\t\t"$(SRCROOT)/Vendor/scintilla/cocoa",\n\t\t\t\t\t"$(SRCROOT)/Vendor/lexilla/include",\n\t\t\t\t\t"$(SRCROOT)/Vendor/lexilla/src",\n\t\t\t\t\t"$(SRCROOT)/Vendor/lexilla/lexlib",\n\t\t\t\t)',
            "MACOSX_DEPLOYMENT_TARGET": "13.0",
            "SDKROOT": "macosx",
            "SWIFT_STRICT_CONCURRENCY": "minimal",
        }

        debug = dict(shared_debug)
        debug.update({
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"SCI_LEXER=1",\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t)',
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
            "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
        })

        release = dict(shared_debug)
        release.update({
            "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
            "ENABLE_NS_ASSERTIONS": "NO",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
        })

        def settings_block(settings: dict[str, str], indent: str = "\t\t\t\t") -> str:
            out = []
            for key in sorted(settings):
                out.append(f"{indent}{key} = {settings[key]};")
            return "\n".join(out)

        app = {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_IDENTITY": '"-"',
            "CODE_SIGN_STYLE": "Manual",
            "COMBINE_HIDPI_IMAGES": "YES",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "Config/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/../Frameworks",\n\t\t\t\t)',
            "MARKETING_VERSION": "1.0.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.batukucukaydin.plainx",
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SWIFT_EMIT_LOC_STRINGS": "NO",
            "SWIFT_OBJC_BRIDGING_HEADER": "PlainX/Bridge/PlainX-Bridging-Header.h",
            "SWIFT_VERSION": "5.0",
        }

        unit_tests = {
            "BUNDLE_LOADER": '"$(TEST_HOST)"',
            "CODE_SIGN_IDENTITY": '"-"',
            "CODE_SIGN_STYLE": "Manual",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "MARKETING_VERSION": "1.0.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.batukucukaydin.plainx.tests.unit",
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SWIFT_VERSION": "5.0",
            "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/PlainX.app/Contents/MacOS/PlainX"',
        }

        ui_tests = {
            "CODE_SIGN_IDENTITY": '"-"',
            "CODE_SIGN_STYLE": "Manual",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "MARKETING_VERSION": "1.0.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.batukucukaydin.plainx.tests.ui",
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SWIFT_VERSION": "5.0",
            "TEST_TARGET_NAME": "PlainX",
        }

        def config_list(name: str, debug_settings: dict[str, str], release_settings: dict[str, str]) -> None:
            debug_uid = self.obj(
                f"config:{name}:Debug",
                f"\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings_block(debug_settings)}\n\t\t\t}};\n\t\t\tname = Debug;\n",
            )
            release_uid = self.obj(
                f"config:{name}:Release",
                f"\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings_block(release_settings)}\n\t\t\t}};\n\t\t\tname = Release;\n",
            )
            self.obj(
                f"configlist:{name}",
                "\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
                f"\t\t\t\t{debug_uid} /* Debug */,\n"
                f"\t\t\t\t{release_uid} /* Release */,\n"
                "\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n",
            )

        config_list("project", debug, release)
        config_list("PlainX", app, app)
        config_list("PlainXTests", unit_tests, unit_tests)
        config_list("PlainXUITests", ui_tests, ui_tests)

    def write(self) -> None:
        vendor_refs, _ = self.emit_build_files()
        self.emit_file_references(vendor_refs)
        self.emit_groups(vendor_refs)
        self.emit_phases_and_targets(vendor_refs)
        self.emit_project()
        self.emit_configurations()

        header = (
            "// !$*UTF8*$!\n{\n"
            "\tarchiveVersion = 1;\n"
            "\tclasses = {\n\t};\n"
            "\tobjectVersion = 77;\n"
            "\tobjects = {\n\n"
        )
        body = "\n\n".join(self.objects)
        footer = "\n\t};\n\trootObject = " + uuid_for("project") + " /* Project object */;\n}\n"

        PROJECT_DIR.mkdir(parents=True, exist_ok=True)
        (PROJECT_DIR / "project.pbxproj").write_text(header + body + footer)

        # Shared scheme
        schemes_dir = PROJECT_DIR / "xcshareddata" / "xcschemes"
        schemes_dir.mkdir(parents=True, exist_ok=True)
        (schemes_dir / "PlainX.xcscheme").write_text(SCHEME_XML)

        print(f"Generated {rel(PROJECT_DIR / 'project.pbxproj')} ({len(self.vendor_sources)} vendor sources)")
        print(f"Generated {rel(schemes_dir / 'PlainX.xcscheme')}")


SCHEME_XML = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "PLAINX_TARGET"
               BuildableName = "PlainX.app"
               BlueprintName = "PlainX"
               ReferencedContainer = "container:PlainX.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "PLAINX_TESTS_TARGET"
               BuildableName = "PlainXTests.xctest"
               BlueprintName = "PlainXTests"
               ReferencedContainer = "container:PlainX.xcodeproj">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "PLAINX_UITESTS_TARGET"
               BuildableName = "PlainXUITests.xctest"
               BlueprintName = "PlainXUITests"
               ReferencedContainer = "container:PlainX.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "PLAINX_TARGET"
            BuildableName = "PlainX.app"
            BlueprintName = "PlainX"
            ReferencedContainer = "container:PlainX.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "PLAINX_TARGET"
            BuildableName = "PlainX.app"
            BlueprintName = "PlainX"
            ReferencedContainer = "container:PlainX.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def main() -> None:
    generator = ProjectGenerator()
    generator.write()

    # Substitute deterministic target identifiers into the shared scheme.
    scheme_path = PROJECT_DIR / "xcshareddata" / "xcschemes" / "PlainX.xcscheme"
    text = scheme_path.read_text()
    text = text.replace("PLAINX_TARGET", uuid_for("target:PlainX"))
    text = text.replace("PLAINX_TESTS_TARGET", uuid_for("target:PlainXTests"))
    text = text.replace("PLAINX_UITESTS_TARGET", uuid_for("target:PlainXUITests"))
    scheme_path.write_text(text)


if __name__ == "__main__":
    main()
