import {
  ConfigPlugin,
  IOSConfig,
  withPlugins,
  withBaseMod,
  withXcodeProject,
  withEntitlementsPlist,
  withInfoPlist,
  withDangerousMod,
  withAndroidManifest,
  withAppBuildGradle,
} from "@expo/config-plugins";
import path from "node:path";
import fs from "node:fs/promises";

const withNotificationService: ConfigPlugin = (config) => {
  config = withPlugins(config, [
    withIosNotificationService,
    withFirebaseMessagingService,
  ]);

  return config;
};

// Android implementation
const withFirebaseMessagingService: ConfigPlugin = (config) => {
  const packageName = config.android?.package || "com.teamtailor.app";

  const props = {
    packageName,
  };

  return withPlugins(config, [
    [copyFirebaseMessagingService, props],
    [modifyAndroidManifest, props],
    [withFirebaseGradleConfig, props],
  ]);
};

const withFirebaseGradleConfig: ConfigPlugin = (config) => {
  // Add to app level build.gradle
  config = withAppBuildGradle(config, (config) => {
    if (config.modResults.contents.includes("firebase-messaging")) {
      return config;
    }

    const firebaseDependencies = `
    implementation platform('com.google.firebase:firebase-bom:32.7.0')
    implementation 'com.google.firebase:firebase-messaging'`;

    config.modResults.contents = config.modResults.contents.replace(
      /dependencies\s*{/,
      `dependencies {${firebaseDependencies}`
    );

    return config;
  });

  return config;
};

const copyFirebaseMessagingService: ConfigPlugin<{
  packageName: string;
}> = (config, { packageName }) => {
  return withDangerousMod(config, [
    "android",
    async (config) => {
      const packagePath = packageName.replace(/\./g, path.sep);
      const projectRoot = config.modRequest.projectRoot;

      const srcDir = path.resolve(__dirname, "../../android");
      const destDir = path.join(
        projectRoot,
        "android",
        "app",
        "src",
        "main",
        "java",
        packagePath
      );

      // Ensure the destination directory exists
      await fs.mkdir(destDir, { recursive: true });

      await fs.copyFile(path.join(srcDir, "TTFirebaseMessagingService.kt"), path.join(destDir, "TTFirebaseMessagingService.kt"));

      return config;
    },
  ]);
};

const modifyAndroidManifest: ConfigPlugin<{
  packageName: string;
}> = (config, { packageName }) => {
  return withAndroidManifest(config, async (config) => {
    const manifest = config.modResults;
    const application = manifest.manifest.application?.[0];

    if (!application) {
      throw new Error("AndroidManifest.xml is missing <application> element.");
    }

    // Ensure service array exists
    if (!application.service) {
      application.service = [];
    }

    // Check if the service is already declared
    const serviceExists = application.service.some(
      (service) =>
        service.$["android:name"] ===
        `${packageName}.TTFirebaseMessagingService`
    );

    if (!serviceExists) {
      application.service.push({
        $: {
          "android:name": `${packageName}.TTFirebaseMessagingService`,
          "android:exported": "false",
        },
        "intent-filter": [
          {
            action: [
              {
                $: {
                  "android:name": "com.google.firebase.MESSAGING_EVENT",
                },
              },
            ],
          },
        ],
      });
    }

    return config;
  });
};

// iOS implementation
const withIosNotificationService: ConfigPlugin = (config) => {
  const sanitizedName = IOSConfig.XcodeUtils.sanitizedName(config.name);

  const props = {
    bundleIdentifier: `${config.ios?.bundleIdentifier}.NotificationService`,
    targetName: `${sanitizedName}NotificationService`,
    buildNumber: config.ios!.buildNumber || "1",
    marketingVersion: config.version!,
  };

  config = withPlugins(config, [
    withAppGroupsEntitlements,
    [withEasAppExtensionConfig, props],
    [withNotificationServiceTarget, props],
    [withNotificationCommunicationsCapability, props],
    [withINSendMessageIntent, props],
    withWidgetsRenderEnrichment,
  ]);

  return config;
};

// Compiles LiveActivityRenderEnrichment.swift into the expo-widgets
// widget-extension target. The widget process is where Live Activity
// content-state is decoded and rendered; expo-widgets discovers the class by
// name (ExpoWidgetsLiveActivityPropsTransformer) at render time and lets it
// re-apply the enrichment that broadcast-channel pushes would otherwise wipe.
// The target is created by the expo-widgets plugin, so this package must be
// listed AFTER expo-widgets in the app config's plugins array.
const WIDGETS_TARGET_NAME = "ExpoWidgetsTarget";
const RENDER_ENRICHMENT_FILENAME = "LiveActivityRenderEnrichment.swift";

// withBaseMod + nextMod-first (NOT plain withXcodeProject): expo's ios
// xcodeproj mods do not run in plugin-array order — later registrations run
// OUTERMOST/first, so a plain mod would execute before expo-widgets has
// created the target. Deferring our work until after nextMod guarantees every
// inner mod (including expo-widgets' target creation) has finished. Same
// pattern as ttmobile's plugins/withMeetingActivityLogo.js.
const withWidgetsRenderEnrichment: ConfigPlugin = (config) => {
  return withBaseMod(config, {
    platform: "ios",
    mod: "xcodeproj",
    async action({ modRequest: { nextMod, ...modRequest }, ...cfg }: any) {
      const nextCfg = await nextMod({ ...cfg, modRequest });
      addRenderEnrichmentSource(nextCfg.modResults);
      return nextCfg;
    },
  });
};

const addRenderEnrichmentSource = (project: any) => {
    const targetKey = project.findTargetKey(WIDGETS_TARGET_NAME);
    if (!targetKey) {
      throw new Error(
        `${WIDGETS_TARGET_NAME} was not found — is expo-widgets in the app config plugins?`
      );
    }

    const swiftPath = path.resolve(
      __dirname,
      "../..",
      "ios",
      RENDER_ENRICHMENT_FILENAME
    );

    const fileReferences = project.pbxFileReferenceSection();
    const alreadyAdded = Object.keys(fileReferences).some(
      (key) =>
        !key.endsWith("_comment") &&
        String(fileReferences[key].path).replace(/^"|"$/g, "") === swiftPath
    );
    if (alreadyAdded) {
      return;
    }

    // The target already compiles index.swift, so a Sources phase exists —
    // append to it rather than creating a duplicate phase. Manual pbxproj
    // surgery because node-xcode's addSourceFile needs a source group this
    // generated target doesn't have.
    const target = project.pbxNativeTargetSection()[targetKey];
    const sourcesPhases =
      project.hash.project.objects.PBXSourcesBuildPhase || {};
    const sourcesPhase = (target.buildPhases || [])
      .map((phase: { value: string }) => sourcesPhases[phase.value])
      .find(Boolean);
    if (!sourcesPhase) {
      throw new Error(`${WIDGETS_TARGET_NAME} has no Sources build phase.`);
    }

    const fileReferenceUuid = project.generateUuid();
    fileReferences[fileReferenceUuid] = {
      isa: "PBXFileReference",
      fileEncoding: 4,
      lastKnownFileType: "sourcecode.swift",
      name: RENDER_ENRICHMENT_FILENAME,
      path: `"${swiftPath}"`,
      sourceTree: '"<group>"',
      includeInIndex: 0,
    };
    fileReferences[`${fileReferenceUuid}_comment`] =
      RENDER_ENRICHMENT_FILENAME;

    const buildFiles = project.pbxBuildFileSection();
    const buildFileUuid = project.generateUuid();
    buildFiles[buildFileUuid] = {
      isa: "PBXBuildFile",
      fileRef: fileReferenceUuid,
      fileRef_comment: RENDER_ENRICHMENT_FILENAME,
    };
    buildFiles[`${buildFileUuid}_comment`] =
      `${RENDER_ENRICHMENT_FILENAME} in Sources`;

    sourcesPhase.files = sourcesPhase.files || [];
    sourcesPhase.files.push({
      value: buildFileUuid,
      comment: `${RENDER_ENRICHMENT_FILENAME} in Sources`,
    });
};

const withAppGroupsEntitlements: ConfigPlugin = (config) => {
  return withEntitlementsPlist(config, (config) => {
    const entitlements = config.modResults;
    
    // Add keychain access group entitlement
    entitlements["com.apple.security.application-groups"] = ["group.com.teamtailor.keys"];
    
    return config;
  });
};

const withEasAppExtensionConfig: ConfigPlugin<{
  bundleIdentifier: string;
  targetName: string;
}> = (config, { bundleIdentifier, targetName }) => {
  // Works without this in development, but might need it for eas build. -->
  config.extra = {
    ...config.extra,
    eas: {
      ...config.extra?.eas,
      build: {
        ...config.extra?.eas?.build,
        experimental: {
          ...config.extra?.eas?.build?.experimental,
          ios: {
            ...config.extra?.eas?.build?.experimental?.ios,
            appExtensions: [
              ...(config.extra?.eas?.build?.experimental?.ios?.appExtensions ??
                []),
              {
                bundleIdentifier,
                targetName,
                entitlements: {
                  "com.apple.security.application-groups": ["group.com.teamtailor.keys"]
                }
              },
            ],
          },
        },
      },
    },
  };
  // <--

  return config;
};

const withNotificationServiceTarget: ConfigPlugin<{
  bundleIdentifier: string;
  targetName: string;
  buildNumber: string;
  marketingVersion: string;
}> = (
  config,
  { bundleIdentifier, targetName, buildNumber, marketingVersion }
) => {
  return withXcodeProject(config, async (config) => {
    const iosRoot = path.resolve(__dirname, "../..", "ios");
    const infoPlistPath = path.join(iosRoot, "NotificationService-Info.plist");
    const swiftPath = path.join(iosRoot, "NotificationService.swift");
    const cryptoUtilsPath = path.join(iosRoot, "CryptoUtils.swift");
    const entitlementsPath = path.join(iosRoot, "NotificationService.entitlements");

    const xcodeProject = config.modResults;

    // Add files to project group
    const newGroup = xcodeProject.addPbxGroup(
      [infoPlistPath, swiftPath, cryptoUtilsPath, entitlementsPath],
      "NotificationService",
      iosRoot
    );

    // Add group to main group
    const groups = xcodeProject.hash.project.objects["PBXGroup"];
    Object.keys(groups).forEach(function (key) {
      if (
        typeof groups[key] !== "string" &&
        groups[key].name === undefined &&
        groups[key].path === undefined
      ) {
        xcodeProject.addToPbxGroup(newGroup.uuid, key);
      }
    });

    // Create the target
    const target = xcodeProject.addTarget(
      targetName,
      "app_extension",
      "NotificationService",
      bundleIdentifier
    );

    // Add source files to build phase
    xcodeProject.addBuildPhase(
      [swiftPath, cryptoUtilsPath],
      "PBXSourcesBuildPhase",
      "Sources",
      target.uuid
    );

    // Add entitlements file to resources build phase
    xcodeProject.addBuildPhase(
      [entitlementsPath],
      "PBXResourcesBuildPhase",
      "Resources",
      target.uuid
    );

    // Configure build settings
    const configurations = xcodeProject.pbxXCBuildConfigurationSection();
    for (const key in configurations) {
      const buildSettings = configurations[key].buildSettings;
      if (
        typeof buildSettings !== "undefined" &&
        buildSettings["PRODUCT_NAME"] === `"${targetName}"`
      ) {
        buildSettings["CLANG_ENABLE_MODULES"] = "YES";
        buildSettings["INFOPLIST_FILE"] = `"${infoPlistPath}"`;
        buildSettings["CODE_SIGN_ENTITLEMENTS"] = `"${entitlementsPath}"`;
        buildSettings["CODE_SIGN_STYLE"] = "Automatic";
        buildSettings["CURRENT_PROJECT_VERSION"] = `"${buildNumber}"`;
        buildSettings["GENERATE_INFOPLIST_FILE"] = "YES";
        buildSettings["MARKETING_VERSION"] = `"${marketingVersion}"`;
        buildSettings["SWIFT_EMIT_LOC_STRINGS"] = "YES";
        buildSettings["SWIFT_VERSION"] = "5.0";
        buildSettings["TARGETED_DEVICE_FAMILY"] = `"1,2"`;
        buildSettings["OTHER_CODE_SIGN_FLAGS"] = "--generate-entitlement-der";
        buildSettings["IPHONEOS_DEPLOYMENT_TARGET"] = `"15.0"`;
      }
    }

    return config;
  });
};

const withNotificationCommunicationsCapability: ConfigPlugin = (config) => {
  return withEntitlementsPlist(config, async (newConfig) => {
    const entitlements = newConfig.modResults;
    entitlements["com.apple.developer.usernotifications.communication"] = true;

    return newConfig;
  });
};

const withINSendMessageIntent: ConfigPlugin = (config) => {
  return withInfoPlist(config, async (newConfig) => {
    const infoPlist = newConfig.modResults;

    if (!infoPlist["NSUserActivityTypes"]) {
      infoPlist["NSUserActivityTypes"] = [];
    }

    let NSUserActivityTypes = infoPlist["NSUserActivityTypes"] as Array<String>;
    if (NSUserActivityTypes.indexOf("INSendMessageIntent") === -1) {
      NSUserActivityTypes.push("INSendMessageIntent");
    }

    return newConfig;
  });
};

export default withNotificationService;
