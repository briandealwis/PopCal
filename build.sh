#!/usr/bin/env bash
#
# Build script for PopCal.
#
# Usage: ./build.sh [command]
#
# Commands:
#   build     Build a Release PopCal.app into build/ (default)
#   debug     Build a Debug PopCal.app into build/
#   test      Run the unit tests
#   run       Build (Debug) and launch the app
#   install   Build (Release) and copy PopCal.app to ~/Applications
#   dist      Build (Release) and package build/PopCal-<version>.zip
#   clean     Remove build output
#
# Signing:
#   By default the app is ad-hoc signed ("-"), which is fine for running
#   locally. To sign with your Apple Developer identity, set:
#     DEVELOPMENT_TEAM=ABCDE12345 ./build.sh build
#   Optionally also set CODE_SIGN_IDENTITY (defaults to "Apple Development").

set -euo pipefail

cd "$(dirname "$0")"

PROJECT="PopCal.xcodeproj"
SCHEME="PopCal"
APP_NAME="PopCal"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/DerivedData"

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    SIGNING_ARGS=(
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
        CODE_SIGN_STYLE=Automatic
        CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}"
    )
else
    SIGNING_ARGS=(
        DEVELOPMENT_TEAM=""
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="-"
    )
fi

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

check_xcode() {
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "error: xcodebuild not found; install Xcode 15 or later." >&2
        exit 1
    fi
    if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        echo "error: Xcode needs to finish first-launch setup. Run:" >&2
        echo "    sudo xcodebuild -runFirstLaunch" >&2
        exit 1
    fi
}

xcbuild() {
    check_xcode
    local formatter=(cat)
    if command -v xcbeautify >/dev/null 2>&1; then
        formatter=(xcbeautify)
    fi
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "platform=macOS" \
        -derivedDataPath "$DERIVED_DATA" \
        "${SIGNING_ARGS[@]}" \
        "$@" | "${formatter[@]}"
}

# Builds the given configuration and copies the .app to build/.
build_app() {
    local config="$1"
    log "Building $APP_NAME ($config)"
    xcbuild -configuration "$config" build
    rm -rf "$BUILD_DIR/$APP_NAME.app"
    cp -R "$DERIVED_DATA/Build/Products/$config/$APP_NAME.app" "$BUILD_DIR/"
    log "Built $BUILD_DIR/$APP_NAME.app"
}

app_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist"
}

quit_running_app() {
    if pgrep -x "$APP_NAME" >/dev/null; then
        log "Quitting running $APP_NAME"
        osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || pkill -x "$APP_NAME" || true
        sleep 1
    fi
}

cmd="${1:-build}"
case "$cmd" in
    build)
        build_app Release
        ;;
    debug)
        build_app Debug
        ;;
    test)
        log "Running tests"
        xcbuild -configuration Debug test
        ;;
    run)
        build_app Debug
        quit_running_app
        log "Launching $APP_NAME"
        open "$BUILD_DIR/$APP_NAME.app"
        ;;
    install)
        build_app Release
        quit_running_app
        dest="$HOME/Applications"
        mkdir -p "$dest"
        rm -rf "${dest:?}/$APP_NAME.app"
        cp -R "$BUILD_DIR/$APP_NAME.app" "$dest/"
        log "Installed to $dest/$APP_NAME.app"
        ;;
    dist)
        build_app Release
        zip="$BUILD_DIR/$APP_NAME-$(app_version).zip"
        rm -f "$zip"
        ditto -c -k --keepParent "$BUILD_DIR/$APP_NAME.app" "$zip"
        log "Packaged $zip"
        ;;
    clean)
        log "Removing $BUILD_DIR/"
        rm -rf "$BUILD_DIR"
        ;;
    -h|--help|help)
        sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        echo "Unknown command: $cmd" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
esac
