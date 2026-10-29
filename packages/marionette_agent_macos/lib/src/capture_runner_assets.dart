// Self-contained public-XCTest runner assets. Kept in the AOT executable so
// installation does not depend on a checkout, Ruby, or downloaded runner code.
const captureRunnerFiles = <String, String>{
  'ScreenCapture.xcodeproj/project.pbxproj': r'''// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 46;
	objects = {

/* Begin PBXBuildFile section */
		7BBE6EB0BCD8CF137EF7CD5B /* Capture.swift in Sources */ = {isa = PBXBuildFile; fileRef = 970965F29F9C83B68E0D3AEC /* Capture.swift */; };
		B0E2B9F323AF0B6DBEF59575 /* Foundation.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = 4482CE498C102FA7E8D0755D /* Foundation.framework */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		4482CE498C102FA7E8D0755D /* Foundation.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Foundation.framework; path = System/Library/Frameworks/Foundation.framework; sourceTree = SDKROOT; };
		970965F29F9C83B68E0D3AEC /* Capture.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = Capture.swift; sourceTree = "<group>"; };
		D26E762E8567BBEC244810FA /* ScreenCapture.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ScreenCapture.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		D863F57A4B952802105344F0 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				B0E2B9F323AF0B6DBEF59575 /* Foundation.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		1DD12348DA084ED32CF94261 /* macOS */ = {
			isa = PBXGroup;
			children = (
				4482CE498C102FA7E8D0755D /* Foundation.framework */,
			);
			name = macOS;
			sourceTree = "<group>";
		};
		8FB7A028154AF9FC930B1157 /* Frameworks */ = {
			isa = PBXGroup;
			children = (
				1DD12348DA084ED32CF94261 /* macOS */,
			);
			name = Frameworks;
			sourceTree = "<group>";
		};
		BCEE8427A2F54ECCFC6F8CB1 /* Sources */ = {
			isa = PBXGroup;
			children = (
				970965F29F9C83B68E0D3AEC /* Capture.swift */,
			);
			name = Sources;
			sourceTree = "<group>";
		};
		C0C1520B780236A4EE01D2C2 /* Products */ = {
			isa = PBXGroup;
			children = (
				D26E762E8567BBEC244810FA /* ScreenCapture.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		CE3C839F80E69E43AE3FAEF5 = {
			isa = PBXGroup;
			children = (
				C0C1520B780236A4EE01D2C2 /* Products */,
				8FB7A028154AF9FC930B1157 /* Frameworks */,
				BCEE8427A2F54ECCFC6F8CB1 /* Sources */,
			);
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		20526C4E25790882CE207A59 /* ScreenCapture */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 2FA30C190792202861FA59CF /* Build configuration list for PBXNativeTarget "ScreenCapture" */;
			buildPhases = (
				C1C39BA256044F43CEC667C4 /* Sources */,
				D863F57A4B952802105344F0 /* Frameworks */,
				DDB916B17D6771DF33FB5903 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = ScreenCapture;
			productName = ScreenCapture;
			productReference = D26E762E8567BBEC244810FA /* ScreenCapture.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		84C49CF0645B7FD920166B8F /* Project object */ = {
			isa = PBXProject;
			attributes = {
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
			};
			buildConfigurationList = 7BB9A011CD54ABF830995756 /* Build configuration list for PBXProject "ScreenCapture" */;
			compatibilityVersion = "Xcode 3.2";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = CE3C839F80E69E43AE3FAEF5;
			minimizedProjectReferenceProxies = 0;
			preferredProjectObjectVersion = 77;
			productRefGroup = C0C1520B780236A4EE01D2C2 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				20526C4E25790882CE207A59 /* ScreenCapture */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		DDB916B17D6771DF33FB5903 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		C1C39BA256044F43CEC667C4 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				7BBE6EB0BCD8CF137EF7CD5B /* Capture.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		272C6AEC18C15FCA806984AE /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CLANG_ENABLE_OBJC_WEAK = NO;
				CODE_SIGN_IDENTITY = "-";
                CODE_SIGNING_ALLOWED = YES;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_BITCODE = NO;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				PRODUCT_BUNDLE_IDENTIFIER = dev.marionette.ScreenCapture;
				SDKROOT = macosx;
				SUPPORTED_PLATFORMS = macosx;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
				ENABLE_APP_SANDBOX = NO;
				USES_XCTRUNNER = YES;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		86E79789120907DCA88B42A1 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++14";
				CLANG_CXX_LIBRARY = "libc++";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
		95FECE704988923F7580B095 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CLANG_ENABLE_OBJC_WEAK = NO;
				CODE_SIGN_IDENTITY = "-";
                CODE_SIGNING_ALLOWED = YES;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_BITCODE = NO;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				PRODUCT_BUNDLE_IDENTIFIER = dev.marionette.ScreenCapture;
				SDKROOT = macosx;
				SUPPORTED_PLATFORMS = macosx;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
				ENABLE_APP_SANDBOX = NO;
				USES_XCTRUNNER = YES;
			};
			name = Debug;
		};
		99EBC9CDA7DA0628678BB39E /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++14";
				CLANG_CXX_LIBRARY = "libc++";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		2FA30C190792202861FA59CF /* Build configuration list for PBXNativeTarget "ScreenCapture" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				272C6AEC18C15FCA806984AE /* Release */,
				95FECE704988923F7580B095 /* Debug */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		7BB9A011CD54ABF830995756 /* Build configuration list for PBXProject "ScreenCapture" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				99EBC9CDA7DA0628678BB39E /* Debug */,
				86E79789120907DCA88B42A1 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = 84C49CF0645B7FD920166B8F /* Project object */;
}
''',
  'ScreenCapture.xcodeproj/xcshareddata/xcschemes/ScreenCapture.xcscheme':
      r'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.3">
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
               BlueprintIdentifier = "20526C4E25790882CE207A59"
               BuildableName = "ScreenCapture.xctest"
               BlueprintName = "ScreenCapture"
               ReferencedContainer = "container:ScreenCapture.xcodeproj">
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
               BlueprintIdentifier = "20526C4E25790882CE207A59"
               BuildableName = "ScreenCapture.xctest"
               BlueprintName = "ScreenCapture"
               ReferencedContainer = "container:ScreenCapture.xcodeproj">
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
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
''',
  'Capture.swift': r'''import XCTest
import CoreGraphics
final class Capture: XCTestCase {
    @MainActor func testCapture() throws {
        let env = ProcessInfo.processInfo.environment
        let index = try XCTUnwrap(Int(env["MRA_DISPLAY_INDEX"] ?? ""))
        let count = try XCTUnwrap(Int(env["MRA_DISPLAY_COUNT"] ?? ""))
        let screens = XCUIScreen.screens
        XCTAssertEqual(screens.count, count)
        guard index >= 1, index <= screens.count,
              index == 1 || screens.count <= 2 else {
            XCTFail("Cannot identify selected display with public XCTest APIs")
            return
        }
        let attachment = XCTAttachment(screenshot: screens[index - 1].screenshot())
        attachment.name = "marionette-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
''',
};
