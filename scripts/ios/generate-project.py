#!/usr/bin/env python3
"""Generate the small native mock app/extension project without external tooling."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / 'iOS'
objects = {}
def uid(label): return hashlib.sha256(label.encode()).hexdigest()[:24].upper()
def add(label, **values):
    key = uid(label); objects[key] = values; return key

def file_ref(path, kind):
    return add('file:' + path, isa='PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')

def config_list(name, settings):
    configs = []
    for mode in ['Debug', 'Release']:
        values = dict(settings)
        values.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode == 'Debug' else '-O',
                      SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG $(inherited)' if mode == 'Debug' else '$(inherited)',
                      DEBUG_INFORMATION_FORMAT='dwarf' if mode == 'Debug' else 'dwarf-with-dsym')
        if mode == 'Debug':
            values['ENABLE_TESTABILITY'] = 'YES'
            values['ONLY_ACTIVE_ARCH'] = 'YES'
        configs.append(add(f'config:{name}:{mode}', isa='XCBuildConfiguration', buildSettings=values, name=mode))
    return add('configs:' + name, isa='XCConfigurationList', buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')

project = uid('project')
package = add('package', isa='XCLocalSwiftPackageReference', relativePath='../SwiftKeyPasskeys')
products = []
files = []
base = dict(SDKROOT='iphoneos', IPHONEOS_DEPLOYMENT_TARGET='17.0', SWIFT_VERSION='6.0',
            CLANG_ENABLE_MODULES='YES', CODE_SIGN_STYLE='Automatic', TARGETED_DEVICE_FAMILY='1,2',
            SUPPORTED_PLATFORMS='iphoneos iphonesimulator', SUPPORTS_MACCATALYST='NO',
            CURRENT_PROJECT_VERSION='1', MARKETING_VERSION='0.1.0',
            ENABLE_USER_SCRIPT_SANDBOXING='YES', SWIFT_EMIT_LOC_STRINGS='YES')
fonts = [str(p.relative_to(IOS)) for p in sorted((IOS/"Resources/Fonts").glob("*.ttf"))]
licenses = ['../SwiftKeyDesign/licenses/Host-Grotesk-OFL.txt', '../SwiftKeyDesign/licenses/JetBrains-Mono-OFL.txt']

def dependency(target):
    proxy = add('proxy:' + target, isa='PBXContainerItemProxy', containerPortal=project, proxyType=1,
                remoteGlobalIDString=uid('target:' + target), remoteInfo=target)
    return add('dependency:' + target, isa='PBXTargetDependency', target=uid('target:' + target), targetProxy=proxy)

def target(name, dirs, product_type, suffix, plist=None, entitlements=None, resources=False, core=True, host=None):
    sources = sorted({p for folder in dirs for p in (IOS / folder).glob('**/*.swift')})
    source_builds = []
    for source in sources:
        path = str(source.relative_to(IOS)); ref = file_ref(path, 'sourcecode.swift'); files.append(ref)
        source_builds.append(add(f'build:{name}:{path}', isa='PBXBuildFile', fileRef=ref))
    source_phase = add('sources:' + name, isa='PBXSourcesBuildPhase', buildActionMask=2147483647,
                       files=source_builds, runOnlyForDeploymentPostprocessing=0)
    framework_builds=[]; packages=[]
    if core:
        prod = add('package-product:' + name, isa='XCSwiftPackageProductDependency', package=package, productName='SwiftKeyPasskeys')
        packages.append(prod)
        framework_builds.append(add('package-build:' + name, isa='PBXBuildFile', productRef=prod))
    framework_phase = add('frameworks:' + name, isa='PBXFrameworksBuildPhase', buildActionMask=2147483647,
                          files=framework_builds, runOnlyForDeploymentPostprocessing=0)
    resource_builds=[]
    if resources:
        for path in fonts + licenses:
            ref = file_ref(path, 'file' if path.endswith('.ttf') else 'text'); files.append(ref)
            resource_builds.append(add(f'build:{name}:{path}', isa='PBXBuildFile', fileRef=ref))
    resource_phase = add('resources:' + name, isa='PBXResourcesBuildPhase', buildActionMask=2147483647,
                         files=resource_builds, runOnlyForDeploymentPostprocessing=0)
    settings = dict(base, PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER='com.maceip.swiftkey.mock' + suffix)
    if plist: settings['INFOPLIST_FILE'] = plist
    else: settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    if entitlements: settings['CODE_SIGN_ENTITLEMENTS'] = entitlements
    dependencies = []; phases=[source_phase, framework_phase, resource_phase]
    if product_type == 'com.apple.product-type.app-extension':
        settings.update(APPLICATION_EXTENSION_API_ONLY='YES', SKIP_INSTALL='YES',
                        LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks')
        extension='appex'; filetype='wrapper.app-extension'
    elif product_type == 'com.apple.product-type.application':
        extension='app'; filetype='wrapper.application'
        settings.update(LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks')
        dependencies.append(dependency('SwiftKeyMockProvider'))
        embed = add('embed-provider-build', isa='PBXBuildFile', fileRef=uid('product:SwiftKeyMockProvider'),
                    settings={'ATTRIBUTES': ['CodeSignOnCopy','RemoveHeadersOnCopy']})
        phases.append(add('embed-provider', isa='PBXCopyFilesBuildPhase', buildActionMask=2147483647,
                          dstPath='', dstSubfolderSpec=13, files=[embed], name='Embed App Extensions', runOnlyForDeploymentPostprocessing=0))
    else:
        extension='xctest'; filetype='wrapper.cfbundle'
        dependencies.append(dependency('SwiftKeyMock'))
        settings['TEST_TARGET_NAME']='SwiftKeyMock'
        if host:
            settings.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/SwiftKeyMock.app/SwiftKeyMock', BUNDLE_LOADER='$(TEST_HOST)')
        settings['LD_RUNPATH_SEARCH_PATHS']='$(inherited) @executable_path/Frameworks @loader_path/Frameworks'
    product_ref=add('product:' + name, isa='PBXFileReference', explicitFileType=filetype,
                    includeInIndex=0, path=name + '.' + extension, sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product_ref)
    return add('target:' + name, isa='PBXNativeTarget', buildConfigurationList=config_list(name, settings),
               buildPhases=phases, buildRules=[], dependencies=dependencies, name=name,
               packageProductDependencies=packages, productName=name, productReference=product_ref, productType=product_type)

targets=[target('SwiftKeyMockProvider',['Shared','Extension'],'com.apple.product-type.app-extension','.provider',
                'Configuration/Provider-Info.plist','Configuration/Provider.entitlements',True),
         target('SwiftKeyMock',['Shared','App'],'com.apple.product-type.application','',
                'Configuration/App-Info.plist','Configuration/App.entitlements',True),
         target('SwiftKeyMockUITests',['Tests/UI'],'com.apple.product-type.bundle.ui-testing','.uitests',core=False)]
if list((IOS/'Tests/Unit').glob('*.swift')):
    targets.append(target('SwiftKeyMockTests',['Shared','Extension','Tests/Unit'],'com.apple.product-type.bundle.unit-test','.tests',host=True))
product_group=add('products',isa='PBXGroup',children=products,name='Products',sourceTree='<group>')
main_group=add('main-group',isa='PBXGroup',children=list(dict.fromkeys(files))+[product_group],sourceTree='<group>')
add('project',isa='PBXProject',attributes={'LastUpgradeCheck':'2640','BuildIndependentTargetsInParallel':'YES'},
    buildConfigurationList=config_list('project',base),compatibilityVersion='Xcode 14.0', developmentRegion='en',
    hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main_group,productRefGroup=product_group,
    projectDirPath='',projectRoot='',targets=targets,packageReferences=[package])

def render(value, level=0):
    indent='\t'*level
    if isinstance(value, dict):
        return '{\n'+''.join('\t'*(level+1)+json.dumps(str(k))+ ' = ' + render(v,level+1)+';\n' for k,v in value.items())+indent+'}'
    if isinstance(value, list): return '(\n'+''.join('\t'*(level+1)+render(v,level+1)+',\n' for v in value)+indent+')'
    if isinstance(value, int): return str(value)
    return json.dumps(value)

path=IOS/'SwiftKey.xcodeproj/project.pbxproj'
path.parent.mkdir(parents=True,exist_ok=True)
path.write_text('// !$*UTF8*$!\n'+render(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project))+'\n')

def ref(name, extension):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:"+name)}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:SwiftKey.xcodeproj"/>'
testrefs=''.join(f'<TestableReference skipped="NO">{ref(name,"xctest")}</TestableReference>' for name in ['SwiftKeyMockUITests']+(['SwiftKeyMockTests'] if len(targets)>3 else []))
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref('SwiftKeyMock','app')}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{testrefs}</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('SwiftKeyMock','app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref('SwiftKeyMock','app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_path = IOS/'SwiftKey.xcodeproj/xcshareddata/xcschemes/SwiftKeyMock.xcscheme'
scheme_path.parent.mkdir(parents=True, exist_ok=True)
scheme_path.write_text(scheme)
print('Generated iOS/SwiftKey.xcodeproj')
