# GitHubSyncExample

This directory contains a minimal SwiftUI reference app for iOS 17 or later.

## Run the sample

1. Open `GitHubSyncExample.xcodeproj`.
2. Set your Development Team on the `GitHubSyncExample` target.
3. Change `PRODUCT_BUNDLE_IDENTIFIER` in `Config.xcconfig` to a value unique to your Apple Developer account, for example:

       com.example.yourname.GitHubSyncKitExample

4. Replace `YOUR_GITHUB_OAUTH_CLIENT_ID` in `Config.xcconfig`.
5. Enable Device Flow in the GitHub OAuth App settings.
6. Build and run.

The checked-in Bundle ID is a neutral sample identifier:

    io.github.oqzl.GitHubSyncKitExample

It is not intended for App Store distribution and may already be registered by another developer. Changing the Bundle ID does not require changing the sample's OAuth callback scheme.

## OAuth callback scheme

The sample deliberately keeps the callback scheme independent from the Bundle ID:

    io.github.oqzl.githubsynckit.example

The corresponding callback URL is:

    io.github.oqzl.githubsynckit.example://oauth/callback

Device Flow does not use this callback URL. It is included so the same sample can be adapted to Web Flow without deriving OAuth behavior from `Bundle.main.bundleIdentifier`.

For a production app, replace the scheme with a reverse-DNS value you control and register the matching callback URL in the GitHub OAuth App settings. Custom URL schemes can collide with other installed apps; use a universal link when stronger callback ownership is required.
