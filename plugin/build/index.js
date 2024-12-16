"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const config_plugins_1 = require("@expo/config-plugins");
const node_path_1 = __importDefault(require("node:path"));
const promises_1 = __importDefault(require("node:fs/promises"));
const withNotificationService = (config) => {
    config = (0, config_plugins_1.withPlugins)(config, [
        withIosNotificationService,
        withFirebaseMessagingService,
    ]);
    return config;
};
// Android implementation
const withFirebaseMessagingService = (config) => {
    const packageName = config.android?.package || "com.teamtailor.app";
    const props = {
        packageName,
    };
    return (0, config_plugins_1.withPlugins)(config, [
        [copyFirebaseMessagingService, props],
        [modifyAndroidManifest, props],
    ]);
};
const copyFirebaseMessagingService = (config, { packageName }) => {
    return (0, config_plugins_1.withDangerousMod)(config, [
        "android",
        async (config) => {
            const packagePath = packageName.replace(/\./g, node_path_1.default.sep);
            const projectRoot = config.modRequest.projectRoot;
            const srcDir = node_path_1.default.resolve(__dirname, "../../android");
            const destDir = node_path_1.default.join(projectRoot, "android", "app", "src", "main", "java", packagePath);
            // Ensure the destination directory exists
            await promises_1.default.mkdir(destDir, { recursive: true });
            await promises_1.default.copyFile(node_path_1.default.join(srcDir, "TTFirebaseMessagingService.kt"), node_path_1.default.join(destDir, "TTFirebaseMessagingService.kt"));
            return config;
        },
    ]);
};
const modifyAndroidManifest = (config, { packageName }) => {
    return (0, config_plugins_1.withAndroidManifest)(config, async (config) => {
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
        const serviceExists = application.service.some((service) => service.$["android:name"] ===
            `${packageName}.TTFirebaseMessagingService`);
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
const withIosNotificationService = (config) => {
    const sanitizedName = config_plugins_1.IOSConfig.XcodeUtils.sanitizedName(config.name);
    const props = {
        bundleIdentifier: `${config.ios?.bundleIdentifier}.NotificationService`,
        targetName: `${sanitizedName}NotificationService`,
        buildNumber: config.ios.buildNumber || "1",
        marketingVersion: config.version,
    };
    config = (0, config_plugins_1.withPlugins)(config, [
        withAppGroupsEntitlements,
        [withEasAppExtensionConfig, props],
        [withNotificationServiceTarget, props],
        [withNotificationCommunicationsCapability, props],
        [withINSendMessageIntent, props],
    ]);
    return config;
};
const withAppGroupsEntitlements = (config) => {
    return (0, config_plugins_1.withEntitlementsPlist)(config, (config) => {
        const entitlements = config.modResults;
        // Add keychain access group entitlement
        entitlements["com.apple.security.application-groups"] = ["group.com.teamtailor.keys"];
        return config;
    });
};
const withEasAppExtensionConfig = (config, { bundleIdentifier, targetName }) => {
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
const withNotificationServiceTarget = (config, { bundleIdentifier, targetName, buildNumber, marketingVersion }) => {
    return (0, config_plugins_1.withXcodeProject)(config, async (config) => {
        const iosRoot = node_path_1.default.resolve(__dirname, "../..", "ios");
        const infoPlistPath = node_path_1.default.join(iosRoot, "NotificationService-Info.plist");
        const swiftPath = node_path_1.default.join(iosRoot, "NotificationService.swift");
        const cryptoUtilsPath = node_path_1.default.join(iosRoot, "CryptoUtils.swift");
        const entitlementsPath = node_path_1.default.join(iosRoot, "NotificationService.entitlements");
        const xcodeProject = config.modResults;
        // Add files to project group
        const newGroup = xcodeProject.addPbxGroup([infoPlistPath, swiftPath, cryptoUtilsPath, entitlementsPath], "NotificationService", iosRoot);
        // Add group to main group
        const groups = xcodeProject.hash.project.objects["PBXGroup"];
        Object.keys(groups).forEach(function (key) {
            if (typeof groups[key] !== "string" &&
                groups[key].name === undefined &&
                groups[key].path === undefined) {
                xcodeProject.addToPbxGroup(newGroup.uuid, key);
            }
        });
        // Create the target
        const target = xcodeProject.addTarget(targetName, "app_extension", "NotificationService", bundleIdentifier);
        // Add source files to build phase
        xcodeProject.addBuildPhase([swiftPath, cryptoUtilsPath], "PBXSourcesBuildPhase", "Sources", target.uuid);
        // Add entitlements file to resources build phase
        xcodeProject.addBuildPhase([entitlementsPath], "PBXResourcesBuildPhase", "Resources", target.uuid);
        // Configure build settings
        const configurations = xcodeProject.pbxXCBuildConfigurationSection();
        for (const key in configurations) {
            const buildSettings = configurations[key].buildSettings;
            if (typeof buildSettings !== "undefined" &&
                buildSettings["PRODUCT_NAME"] === `"${targetName}"`) {
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
const withNotificationCommunicationsCapability = (config) => {
    return (0, config_plugins_1.withEntitlementsPlist)(config, async (newConfig) => {
        const entitlements = newConfig.modResults;
        entitlements["com.apple.developer.usernotifications.communication"] = true;
        return newConfig;
    });
};
const withINSendMessageIntent = (config) => {
    return (0, config_plugins_1.withInfoPlist)(config, async (newConfig) => {
        const infoPlist = newConfig.modResults;
        if (!infoPlist["NSUserActivityTypes"]) {
            infoPlist["NSUserActivityTypes"] = [];
        }
        let NSUserActivityTypes = infoPlist["NSUserActivityTypes"];
        if (NSUserActivityTypes.indexOf("INSendMessageIntent") === -1) {
            NSUserActivityTypes.push("INSendMessageIntent");
        }
        return newConfig;
    });
};
exports.default = withNotificationService;
