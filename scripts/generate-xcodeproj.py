#!/usr/bin/env python3
"""
生成 IELTSCDPractice.xcodeproj/project.pbxproj。

扫描 IELTSCDPractice/ 下的 Swift 源文件；ExamEngine/ 与 Content/ 以文件夹引用方式打包，
保持目录结构。新增或删除 Swift 文件后重新运行：

    python3 scripts/generate-xcodeproj.py [--team <Team ID>] [--bundle-id <Bundle ID>]

签名设置保存在 signing.local.json（不提交到 git），之后运行时沿用：
  --team       Apple 开发者团队 ID（10 位，免费 Apple ID 也有）
  --bundle-id  App 的 Bundle ID，默认 com.ieltscdpractice.<团队 ID 小写>
"""
import argparse, hashlib, json, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
APP = os.path.join(ROOT, "IELTSCDPractice")
SIGNING_FILE = os.path.join(ROOT, "signing.local.json")

parser = argparse.ArgumentParser(description="生成 Xcode 工程")
parser.add_argument("--team", help="Apple 开发者团队 ID")
parser.add_argument("--bundle-id", help="App 的 Bundle ID")
args = parser.parse_args()

signing = {}
if os.path.exists(SIGNING_FILE):
    signing = json.load(open(SIGNING_FILE))
if args.team:
    signing["team"] = args.team
if args.bundle_id:
    signing["bundleID"] = args.bundle_id
if signing.get("team") and not signing.get("bundleID"):
    signing["bundleID"] = "com.ieltscdpractice." + signing["team"].lower()
if args.team or args.bundle_id:
    json.dump(signing, open(SIGNING_FILE, "w"), indent=2)
TEAM = signing.get("team", "")
BUNDLE_ID = signing.get("bundleID", "com.example.ieltscdpractice")

def uid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

FOLDER_REFERENCES = ["ExamEngine", "Content"]
swift_groups = {}
for dirpath, dirnames, filenames in os.walk(APP):
    rel = os.path.relpath(dirpath, APP)
    top = rel.split(os.sep)[0]
    if top in FOLDER_REFERENCES or top.endswith(".xcassets"):
        dirnames[:] = []
        continue
    dirnames.sort()
    for name in sorted(filenames):
        if name.endswith(".swift"):
            swift_groups.setdefault(rel, []).append(name)
resource_in_group = {}

objects = []
def add(s): objects.append(s)

project = uid("project"); main_group = uid("mainGroup"); products_group = uid("products")
app_group = uid("group.IELTSCDPractice"); target = uid("target"); product = uid("product.app")
sources_phase = uid("phase.sources"); resources_phase = uid("phase.resources"); frameworks_phase = uid("phase.frameworks")
proj_cfg_list = uid("cfglist.project"); tgt_cfg_list = uid("cfglist.target")
proj_debug = uid("cfg.project.debug"); proj_release = uid("cfg.project.release")
tgt_debug = uid("cfg.target.debug"); tgt_release = uid("cfg.target.release")

file_refs = []   # (id, isa line)
build_files = [] # (id, fileRef, name, phase)
group_children = {}

for group, files in swift_groups.items():
    group_children.setdefault(group, [])
    for f in files:
        ref = uid("ref." + group + "/" + f)
        file_refs.append(f'\t\t{ref} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = "<group>"; }};')
        group_children[group].append((ref, f))
        bf = uid("bf." + group + "/" + f)
        build_files.append((bf, ref, f, "Sources"))
for group, files in resource_in_group.items():
    for f in files:
        ref = uid("ref." + group + "/" + f)
        file_refs.append(f'\t\t{ref} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.javascript; path = {f}; sourceTree = "<group>"; }};')
        group_children[group].append((ref, f))
        bf = uid("bf." + group + "/" + f)
        build_files.append((bf, ref, f, "Resources"))

assets_ref = uid("ref.Assets.xcassets"); plist_ref = uid("ref.Info.plist")
folder_refs = {name: uid("ref." + name) for name in FOLDER_REFERENCES}
file_refs.append(f'\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};')
for name, ref in folder_refs.items():
    file_refs.append(f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = folder; path = {name}; sourceTree = "<group>"; }};')
file_refs.append(f'\t\t{plist_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};')
file_refs.append(f'\t\t{product} /* IELTS CD Practice.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "IELTS CD Practice.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
build_files.append((uid("bf.Assets"), assets_ref, "Assets.xcassets", "Resources"))
for name, ref in folder_refs.items():
    build_files.append((uid("bf." + name), ref, name, "Resources"))

out = []
out.append("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n")
out.append("/* Begin PBXBuildFile section */")
for bf, ref, name, phase in build_files:
    out.append(f'\t\t{bf} /* {name} in {phase} */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};')
out.append("/* End PBXBuildFile section */\n")
out.append("/* Begin PBXFileReference section */")
out.extend(file_refs)
out.append("/* End PBXFileReference section */\n")
out.append("/* Begin PBXFrameworksBuildPhase section */")
out.append(f'\t\t{frameworks_phase} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};')
out.append("/* End PBXFrameworksBuildPhase section */\n")

out.append("/* Begin PBXGroup section */")
def group_block(gid, name, children, path=None):
    lines = [f'\t\t{gid} /* {name} */ = {{', '\t\t\tisa = PBXGroup;', '\t\t\tchildren = (']
    for cid, cname in children:
        lines.append(f'\t\t\t\t{cid} /* {cname} */,')
    lines.append('\t\t\t);')
    if path:
        lines.append(f'\t\t\tpath = {path};')
    lines.append('\t\t\tsourceTree = "<group>";')
    lines.append('\t\t};')
    return "\n".join(lines)

out.append(group_block(main_group, "Root", [(app_group, "IELTSCDPractice"), (products_group, "Products")]))
out.append(group_block(products_group, "Products", [(product, "IELTS CD Practice.app")]).replace('\t\t\tsourceTree', '\t\t\tname = Products;\n\t\t\tsourceTree'))
# 由目录生成嵌套分组
tree = {}
for rel in group_children:
    parts = [] if rel == "." else rel.split(os.sep)
    node = tree
    for part in parts:
        node = node.setdefault(part, {})

def emit(node, prefix):
    children = []
    for name in sorted(node):
        rel = os.path.join(prefix, name) if prefix else name
        gid = uid("group." + rel)
        sub_children = emit(node[name], rel) + group_children.get(rel, [])
        out.append(group_block(gid, name, sub_children, path=name))
        children.append((gid, name))
    return children

top_children = emit(tree, "") + group_children.get(".", [])
folder_children = [(folder_refs[name], name) for name in FOLDER_REFERENCES]
out.append(group_block(app_group, "IELTSCDPractice", top_children + [(assets_ref, "Assets.xcassets")] + folder_children + [(plist_ref, "Info.plist")], path="IELTSCDPractice"))
out.append("/* End PBXGroup section */\n")

out.append("/* Begin PBXNativeTarget section */")
out.append(f'''\t\t{target} /* IELTSCDPractice */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {tgt_cfg_list} /* Build configuration list for PBXNativeTarget "IELTSCDPractice" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase} /* Sources */,
\t\t\t\t{frameworks_phase} /* Frameworks */,
\t\t\t\t{resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = IELTSCDPractice;
\t\t\tproductName = IELTSCDPractice;
\t\t\tproductReference = {product} /* IELTS CD Practice.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};''')
out.append("/* End PBXNativeTarget section */\n")

out.append("/* Begin PBXProject section */")
out.append(f'''\t\t{project} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2700;
\t\t\t\tLastUpgradeCheck = 2700;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject "IELTSCDPractice" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = "zh-Hans";
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t\t"zh-Hans",
\t\t\t);
\t\t\tmainGroup = {main_group};
\t\t\tproductRefGroup = {products_group} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target} /* IELTSCDPractice */,
\t\t\t);
\t\t}};''')
out.append("/* End PBXProject section */\n")

def phase(pid, isa, name, kind):
    lines = [f'\t\t{pid} /* {name} */ = {{', f'\t\t\tisa = {isa};', '\t\t\tbuildActionMask = 2147483647;', '\t\t\tfiles = (']
    for bf, ref, fname, ph in build_files:
        if ph == kind:
            lines.append(f'\t\t\t\t{bf} /* {fname} in {kind} */,')
    lines += ['\t\t\t);', '\t\t\trunOnlyForDeploymentPostprocessing = 0;', '\t\t};']
    return "\n".join(lines)
out.append("/* Begin PBXResourcesBuildPhase section */")
out.append(phase(resources_phase, "PBXResourcesBuildPhase", "Resources", "Resources"))
out.append("/* End PBXResourcesBuildPhase section */\n")
out.append("/* Begin PBXSourcesBuildPhase section */")
out.append(phase(sources_phase, "PBXSourcesBuildPhase", "Sources", "Sources"))
out.append("/* End PBXSourcesBuildPhase section */\n")

common_project = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
}
debug_project = dict(common_project, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
})
release_project = dict(common_project, **{
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})
target_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "2",
    "DEVELOPMENT_TEAM": f'"{TEAM}"',
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "IELTSCDPractice/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": '"IELTS CD Practice"',
    "INFOPLIST_KEY_LSApplicationCategoryType": '"public.app-category.education"',
    "INFOPLIST_KEY_UIRequiresFullScreen": "NO",
    "INFOPLIST_KEY_NSMicrophoneUsageDescription": '"口语练习时录下你的回答，方便回放对比。录音只保存在本机。"',
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
    "INFOPLIST_KEY_UIStatusBarStyle": "UIStatusBarStyleDefault",
    "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
    "MARKETING_VERSION": "1.0.1",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": '"IELTS CD Practice"',
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "2",
}

def cfg(cid, name, settings):
    lines = [f'\t\t{cid} /* {name} */ = {{', '\t\t\tisa = XCBuildConfiguration;', '\t\t\tbuildSettings = {']
    for k in sorted(settings):
        lines.append(f'\t\t\t\t{k} = {settings[k]};')
    lines += ['\t\t\t};', f'\t\t\tname = {name};', '\t\t};']
    return "\n".join(lines)
out.append("/* Begin XCBuildConfiguration section */")
out.append(cfg(proj_debug, "Debug", debug_project))
out.append(cfg(proj_release, "Release", release_project))
out.append(cfg(tgt_debug, "Debug", target_settings))
out.append(cfg(tgt_release, "Release", target_settings))
out.append("/* End XCBuildConfiguration section */\n")

out.append("/* Begin XCConfigurationList section */")
for lid, label, d, r in [(proj_cfg_list, 'PBXProject "IELTSCDPractice"', proj_debug, proj_release), (tgt_cfg_list, 'PBXNativeTarget "IELTSCDPractice"', tgt_debug, tgt_release)]:
    out.append(f'''\t\t{lid} /* Build configuration list for {label} */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{d} /* Debug */,
\t\t\t\t{r} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};''')
out.append("/* End XCConfigurationList section */")
out.append(f"\t}};\n\trootObject = {project} /* Project object */;\n}}\n")

project_dir = os.path.join(ROOT, "IELTSCDPractice.xcodeproj")
os.makedirs(project_dir, exist_ok=True)
open(os.path.join(project_dir, "project.pbxproj"), "w").write("\n".join(out))
print("Generated", os.path.relpath(project_dir, ROOT), "with", sum(len(v) for v in swift_groups.values()), "Swift files")
print("Signing:", ("team " + TEAM) if TEAM else "未设置团队（只能在模拟器运行）", "· bundle ID", BUNDLE_ID)
