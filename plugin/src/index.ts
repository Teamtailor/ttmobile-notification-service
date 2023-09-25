import {
  ConfigPlugin,
  IOSConfig,
  withPlugins,
  withXcodeProject,
  withEntitlementsPlist,
  withInfoPlist,
} from "@expo/config-plugins";
import path from "node:path";

const withNotificationService: ConfigPlugin = (config) => {
  const sanitizedName = IOSConfig.XcodeUtils.sanitizedName(config.name);

  const props = {
    bundleIdentifier: `${config.ios?.bundleIdentifier}.NotificationService`,
    targetName: `${sanitizedName}NotificationService`,
    buildNumber: config.ios!.buildNumber || "1",
    marketingVersion: config.version!,
  };

  config = withPlugins(config, [
    [withEasAppExtensionConfig, props],
    [withNotificationServiceTarget, props],
    [withNotificationCommunicationsCapability, props],
    [withINSendMessageIntent, props],
  ]);

  return config;
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

    const xcodeProject = config.modResults;

    // Don't really think this is necessary, but it does add the references to xcode browser so nice to have -->
    const newGroup = xcodeProject.addPbxGroup(
      [infoPlistPath, swiftPath],
      "NotificationService",
      iosRoot
    );

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
    // <--

    const target = xcodeProject.addTarget(
      targetName,
      "app_extension",
      "NotificationService",
      bundleIdentifier
    );

    xcodeProject.addBuildPhase(
      [swiftPath],
      "PBXSourcesBuildPhase",
      "Sources",
      target.uuid
    );

    const configurations = xcodeProject.pbxXCBuildConfigurationSection();
    for (const key in configurations) {
      if (typeof configurations[key].buildSettings !== "undefined") {
        const buildSettingsObj = configurations[key].buildSettings;
        if (
          typeof buildSettingsObj["PRODUCT_NAME"] !== "undefined" &&
          buildSettingsObj["PRODUCT_NAME"] === `"${targetName}"`
        ) {
          buildSettingsObj["CLANG_ENABLE_MODULES"] = "YES";
          buildSettingsObj["INFOPLIST_FILE"] = `"${infoPlistPath}"`;
          buildSettingsObj["CODE_SIGN_STYLE"] = "Automatic";
          buildSettingsObj["CURRENT_PROJECT_VERSION"] = `"${buildNumber}"`;
          buildSettingsObj["GENERATE_INFOPLIST_FILE"] = "YES";
          buildSettingsObj["MARKETING_VERSION"] = `"${marketingVersion}"`;
          buildSettingsObj["SWIFT_EMIT_LOC_STRINGS"] = "YES";
          buildSettingsObj["SWIFT_VERSION"] = "5.0";
          buildSettingsObj["TARGETED_DEVICE_FAMILY"] = `"1,2"`;
          buildSettingsObj["IPHONEOS_DEPLOYMENT_TARGET"] = `"15.0"`;
        }
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


    if(!infoPlist["NSUserActivityTypes"]) {
      infoPlist["NSUserActivityTypes"] = []
    }

    let NSUserActivityTypes = infoPlist["NSUserActivityTypes"] as Array<String>
    if(NSUserActivityTypes.indexOf("INSendMessageIntent") === -1) {
      NSUserActivityTypes.push("INSendMessageIntent");
    }

    return newConfig;
  });
};

export default withNotificationService;
