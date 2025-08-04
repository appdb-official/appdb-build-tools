#!/bin/bash
# Installation

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}🔨 Building IPA${RESET}"
export OPENSSL_CONF=~/.appdb/engine.conf
SOURCE_DIR=$(dirname "$0")
LDID="$SOURCE_DIR/ldid"
P12="$SOURCE_DIR/dummy.p12"
PLISTBUDDY=/usr/libexec/PlistBuddy

ASK_FOR_HSM=1
USE_HSM=0
HSM_PASSWORD=""
HSM_KEY_URI=""
HSM_CERT_URI=""

if [[ $ASK_FOR_HSM ]]; then
  while true; do
    echo -e "${MAGENTA}🔐 Use signing with HSM or hardware key [y/n]${RESET}"
    read yn
    case $yn in
    [Yy]*)
      USE_HSM=1
      if [[ "$HSM_PASSWORD" == "" ]]; then
        echo -e "${YELLOW}🔑 Enter HSM password [0001password]:${RESET}"
        read HSM_PASSWORD
        if [[ "$HSM_PASSWORD" == "" ]]; then
          HSM_PASSWORD="0001password"
        fi
      fi
      if [[ "$HSM_KEY_URI" == "" ]]; then
        echo -e "${YELLOW}🗝️  Enter HSM private key URI (use ./get_pkcs11_uris.sh to get it):${RESET}"
        read HSM_KEY_URI
        if [[ "$HSM_KEY_URI" == "" ]]; then
          echo -e "${RED}❌ ERROR: HSM Key URI is required${RESET}"
          exit 1
        fi
      fi
      if [[ "$HSM_CERT_URI" == "" ]]; then
        echo -e "${YELLOW}📜 Enter HSM certificate URI (use ./get_pkcs11_uris.sh to get it):${RESET}"
        read HSM_CERT_URI
        if [[ "$HSM_CERT_URI" == "" ]]; then
          echo -e "${RED}❌ ERROR: HSM Certificate URI is required${RESET}"
          exit 1
        fi
      fi
      break
      ;;
    [Nn]*) break ;;
    *) echo -e "${RED}Please answer yes or no.${RESET}" ;;
    esac
  done
fi

function createmenu() {
  #echo "Size of entries: $#"
  #echo "$@"
  select option; do # in "$@" is the default
    if [ "$REPLY" -eq "$#" ]; then
      echo "Exiting..."
      break
    elif [ 1 -le "$REPLY" ] && [ "$REPLY" -le $(($# - 1)) ]; then
      echo "You selected $option which is option $REPLY"
      break
    else
      echo "Incorrect Input: Select a number 1-$#"
    fi
  done
}

function select_from_list() {
  local prompt="$1"
  shift
  local options=("$@")
  
  if [ ${#options[@]} -eq 0 ]; then
    echo -e "${RED}❌ ERROR: No options available for selection${RESET}" >&2
    return 1
  fi
  
  echo -e "${BOLD}${BLUE}$prompt${RESET}" >&2
  PS3="$(echo -e "${CYAN}Please select (1-${#options[@]}): ${RESET}")"
  select option in "${options[@]}"; do
    if [ -n "$option" ]; then
      echo "$option"
      return 0
    else
      echo -e "${RED}❌ Invalid selection. Please try again.${RESET}" >&2
    fi
  done
}

if ! [ -f "/usr/bin/xcodebuild" ]; then
  echo -e "${RED}❌ ERROR: Requirements not met. Please use install.sh to make your system ready${RESET}" >&2
  exit 1
fi

if [[ "$1" != *\.xcodeproj && "$1" != *\.xcodeworkspace ]]; then
  echo -e "${RED}❌ ERROR: Specify path to .xcodeproj or .xcodeworkspace file in argv[1]${RESET}" >&2
  exit 1
fi

XCODE_PROJECT_FILE=$1
BUILD_ROOT_PATH=$(dirname $1)
XCODE_BUILD_SCHEME=$2

echo -e "${BOLD}${YELLOW}📋 Getting schemes and configurations from project${RESET}"

# Get project info and parse it
PROJECT_INFO=$(xcodebuild -project "$XCODE_PROJECT_FILE" -list)
echo -e "${BLUE}$PROJECT_INFO${RESET}"

# Extract schemes
SCHEMES=($(echo "$PROJECT_INFO" | sed -n '/Schemes:/,/^$/p' | grep -v "Schemes:" | grep -v "^$" | sed 's/^[[:space:]]*//' | grep -v "^[[:space:]]*$"))

# Extract build configurations  
BUILD_CONFIGS=($(echo "$PROJECT_INFO" | sed -n '/Build Configurations:/,/^$/p' | grep -v "Build Configurations:" | grep -v "^$" | sed 's/^[[:space:]]*//' | grep -v "^[[:space:]]*$"))

# Function to get bundle identifier from Xcode project settings (not cached build output)
# This ensures we always get the latest bundle identifier from the project configuration
# instead of relying on potentially stale build output in derivedData or Info.plist
get_bundle_identifier_from_project() {
  local project_file="$1"
  local scheme="$2"
  local configuration="$3"
  
  # Get build settings from the project directly
  local build_settings
  local bundle_id=""
  
  echo -e "${CYAN}🔧 Extracting build settings from project...${RESET}" >&2
  
  if [[ "$project_file" == *.xcodeworkspace ]]; then
    build_settings=$(xcodebuild -workspace "$project_file" -scheme "$scheme" -configuration "$configuration" -showBuildSettings 2>/dev/null)
  else
    build_settings=$(xcodebuild -project "$project_file" -scheme "$scheme" -configuration "$configuration" -showBuildSettings 2>/dev/null)
  fi
  
  if [[ $? -eq 0 && -n "$build_settings" ]]; then
    # Extract PRODUCT_BUNDLE_IDENTIFIER from build settings
    bundle_id=$(echo "$build_settings" | grep "PRODUCT_BUNDLE_IDENTIFIER" | head -n 1 | sed 's/.*PRODUCT_BUNDLE_IDENTIFIER = //' | tr -d ' ')
    
    # Clean up the bundle identifier (remove quotes if present)
    bundle_id=$(echo "$bundle_id" | tr -d '"' | tr -d "'")
  fi
  
  # If we couldn't get it from build settings, try direct project file parsing
  if [[ -z "$bundle_id" ]]; then
    echo -e "${CYAN}🔧 Trying to extract from project file directly...${RESET}" >&2
    
    if [[ "$project_file" == *.xcodeworkspace ]]; then
      # For workspace, look for .xcodeproj files in the same directory
      local workspace_dir=$(dirname "$project_file")
      local xcodeproj_file=$(find "$workspace_dir" -name "*.xcodeproj" | head -n 1)
      
      if [[ -n "$xcodeproj_file" ]]; then
        local pbxproj_file="$xcodeproj_file/project.pbxproj"
        if [[ -f "$pbxproj_file" ]]; then
          bundle_id=$(grep -m1 "PRODUCT_BUNDLE_IDENTIFIER" "$pbxproj_file" | sed 's/.*PRODUCT_BUNDLE_IDENTIFIER = //' | sed 's/;//' | tr -d ' "')
        fi
      fi
    else
      local pbxproj_file="$project_file/project.pbxproj"
      if [[ -f "$pbxproj_file" ]]; then
        bundle_id=$(grep -m1 "PRODUCT_BUNDLE_IDENTIFIER" "$pbxproj_file" | sed 's/.*PRODUCT_BUNDLE_IDENTIFIER = //' | sed 's/;//' | tr -d ' "')
      fi
    fi
  fi
  
  echo "$bundle_id"
}

# Function to get bundle version from Xcode project settings (not cached build output)
# This ensures we always get the latest version numbers from the project configuration
# instead of relying on potentially stale build output in derivedData or Info.plist
get_bundle_version_from_project() {
  local project_file="$1"
  local scheme="$2"
  local configuration="$3"
  
  # Get build settings from the project directly
  local build_settings
  local marketing_version=""
  local current_project_version=""
  
  echo -e "${CYAN}🔧 Extracting version info from project...${RESET}" >&2
  
  if [[ "$project_file" == *.xcodeworkspace ]]; then
    build_settings=$(xcodebuild -workspace "$project_file" -scheme "$scheme" -configuration "$configuration" -showBuildSettings 2>/dev/null)
  else
    build_settings=$(xcodebuild -project "$project_file" -scheme "$scheme" -configuration "$configuration" -showBuildSettings 2>/dev/null)
  fi
  
  if [[ $? -eq 0 && -n "$build_settings" ]]; then
    # Extract MARKETING_VERSION (CFBundleShortVersionString) from build settings
    marketing_version=$(echo "$build_settings" | grep "MARKETING_VERSION" | head -n 1 | sed 's/.*MARKETING_VERSION = //' | tr -d ' ' | tr -d '"' | tr -d "'")
    
    # Extract CURRENT_PROJECT_VERSION (CFBundleVersion) from build settings
    current_project_version=$(echo "$build_settings" | grep "CURRENT_PROJECT_VERSION" | head -n 1 | sed 's/.*CURRENT_PROJECT_VERSION = //' | tr -d ' ' | tr -d '"' | tr -d "'")
  fi
  
  # If we couldn't get them from build settings, try direct project file parsing
  if [[ -z "$marketing_version" || -z "$current_project_version" ]]; then
    echo -e "${CYAN}🔧 Trying to extract version info from project file directly...${RESET}" >&2
    
    if [[ "$project_file" == *.xcodeworkspace ]]; then
      # For workspace, look for .xcodeproj files in the same directory
      local workspace_dir=$(dirname "$project_file")
      local xcodeproj_file=$(find "$workspace_dir" -name "*.xcodeproj" | head -n 1)
      
      if [[ -n "$xcodeproj_file" ]]; then
        local pbxproj_file="$xcodeproj_file/project.pbxproj"
        if [[ -f "$pbxproj_file" ]]; then
          if [[ -z "$marketing_version" ]]; then
            marketing_version=$(grep -m1 "MARKETING_VERSION" "$pbxproj_file" | sed 's/.*MARKETING_VERSION = //' | sed 's/;//' | tr -d ' "')
          fi
          if [[ -z "$current_project_version" ]]; then
            current_project_version=$(grep -m1 "CURRENT_PROJECT_VERSION" "$pbxproj_file" | sed 's/.*CURRENT_PROJECT_VERSION = //' | sed 's/;//' | tr -d ' "')
          fi
        fi
      fi
    else
      local pbxproj_file="$project_file/project.pbxproj"
      if [[ -f "$pbxproj_file" ]]; then
        if [[ -z "$marketing_version" ]]; then
          marketing_version=$(grep -m1 "MARKETING_VERSION" "$pbxproj_file" | sed 's/.*MARKETING_VERSION = //' | sed 's/;//' | tr -d ' "')
        fi
        if [[ -z "$current_project_version" ]]; then
          current_project_version=$(grep -m1 "CURRENT_PROJECT_VERSION" "$pbxproj_file" | sed 's/.*CURRENT_PROJECT_VERSION = //' | sed 's/;//' | tr -d ' "')
        fi
      fi
    fi
  fi
  
  # Return both values separated by a pipe character
  echo "${marketing_version}|${current_project_version}"
}

# Select scheme if not provided as argument
if [[ "$XCODE_BUILD_SCHEME" == "" ]]; then
  if [ ${#SCHEMES[@]} -eq 0 ]; then
    echo -e "${RED}❌ ERROR: No schemes found in project${RESET}" >&2
    exit 1
  fi
  
  XCODE_BUILD_SCHEME=$(select_from_list "🎯 Choose a build scheme:" "${SCHEMES[@]}")
  
  if [[ "$XCODE_BUILD_SCHEME" == "" ]]; then
    echo -e "${RED}❌ ERROR: no build scheme selected, exiting${RESET}" >&2
    exit 1
  fi
fi

# Select build configuration
if [ ${#BUILD_CONFIGS[@]} -eq 0 ]; then
  echo -e "${YELLOW}⚠️  WARNING: No build configurations found, using Debug${RESET}"
  XCODE_BUILD_CONFIGURATION="Debug"
else
  XCODE_BUILD_CONFIGURATION=$(select_from_list "⚙️  Choose a build configuration:" "${BUILD_CONFIGS[@]}")
  
  if [[ "$XCODE_BUILD_CONFIGURATION" == "" ]]; then
    echo -e "${YELLOW}Using default build configuration: Debug${RESET}"
    XCODE_BUILD_CONFIGURATION="Debug"
  fi
fi

echo -e "${GREEN}✅ Selected build scheme: ${BOLD}$XCODE_BUILD_SCHEME${RESET}"
echo -e "${GREEN}✅ Selected build configuration: ${BOLD}$XCODE_BUILD_CONFIGURATION${RESET}"

echo -e "${BOLD}${YELLOW}🔍 Getting bundle identifier from project settings${RESET}"
CURRENT_BUNDLE_IDENTIFIER=$(get_bundle_identifier_from_project "$XCODE_PROJECT_FILE" "$XCODE_BUILD_SCHEME" "$XCODE_BUILD_CONFIGURATION")

if [[ -z "$CURRENT_BUNDLE_IDENTIFIER" ]]; then
  echo -e "${YELLOW}⚠️  Could not extract bundle identifier from project settings${RESET}"
  CURRENT_BUNDLE_IDENTIFIER="(will be read from built Info.plist)"
else
  echo -e "${GREEN}✅ Bundle identifier from project settings: ${BOLD}$CURRENT_BUNDLE_IDENTIFIER${RESET}"
fi

echo -e "${BOLD}${YELLOW}🔢 Getting bundle version from project settings${RESET}"
BUNDLE_VERSION_INFO=$(get_bundle_version_from_project "$XCODE_PROJECT_FILE" "$XCODE_BUILD_SCHEME" "$XCODE_BUILD_CONFIGURATION")

# Parse the version info
IFS='|' read -r PROJECT_MARKETING_VERSION PROJECT_CURRENT_VERSION <<< "$BUNDLE_VERSION_INFO"

echo -e "${BLUE}📋 Project version information:${RESET}"
echo -e "${CYAN}  Bundle Identifier: ${BOLD}${CURRENT_BUNDLE_IDENTIFIER}${RESET}"
echo -e "${CYAN}  CFBundleShortVersionString (MARKETING_VERSION): ${BOLD}${PROJECT_MARKETING_VERSION:-'not set in project'}${RESET}"
echo -e "${CYAN}  CFBundleVersion (CURRENT_PROJECT_VERSION): ${BOLD}${PROJECT_CURRENT_VERSION:-'not set in project'}${RESET}"

while true; do
  echo -e "${MAGENTA}🤔 Do you want to proceed with building using these settings? [y/n]${RESET}"
  read -r yn
  case $yn in
    [Yy]*)
      echo -e "${GREEN}✅ Proceeding with build...${RESET}"
      break
      ;;
    [Nn]*)
      echo -e "${YELLOW}❌ Build cancelled. Please update your project settings and try again.${RESET}"
      exit 0
      ;;
    *)
      echo -e "${RED}Please answer yes or no.${RESET}"
      ;;
  esac
done

echo -e "${BOLD}${MAGENTA}🏗️  Building...${RESET}"

rm -Rf "$BUILD_ROOT_PATH/derivedData"

xcodebuild -scheme "$XCODE_BUILD_SCHEME" -project "$XCODE_PROJECT_FILE" -configuration "$XCODE_BUILD_CONFIGURATION" -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$BUILD_ROOT_PATH/derivedData" build CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS='' CODE_SIGNING_ALLOWED=NO

if [ $? -eq 0 ]; then
  echo -e "${BOLD}${GREEN}🎉 Build OK!${RESET}"
else
  echo -e "${RED}❌ ERROR: Build failed. Fix errors and try again${RESET}" >&2
  exit 1
fi

echo -e "${BOLD}${CYAN}🔐 Signing and packaging file${RESET}"

APP_NAME=$(ls "$BUILD_ROOT_PATH/derivedData/Build/Products/Debug-iphoneos" | grep "\.app$")

echo -e "${BLUE}📱 Got app name: ${BOLD}$APP_NAME${RESET}"

APP_PATH="$BUILD_ROOT_PATH/derivedData/Build/Products/Debug-iphoneos/$APP_NAME"

if [ ! -e "$APP_PATH/Info.plist" ]; then
  echo -e "${RED}❌ Expected file does not exist: '$APP_PATH/Info.plist'${RESET}" >&2
  exit 1
fi

APP_BINARY=$($PLISTBUDDY -c "Print :CFBundleExecutable" "$APP_PATH/Info.plist" | tr -d '"')

echo -e "${BLUE}📦 Got app binary: ${BOLD}$APP_BINARY${RESET}"

echo -e "${BOLD}${YELLOW}📜 Assigning entitlements${RESET}"

# Find available entitlements files
AVAILABLE_ENTITLEMENTS=()
if [ -d "$BUILD_ROOT_PATH" ]; then
  while IFS= read -r -d $'\0'; do
    AVAILABLE_ENTITLEMENTS+=("$REPLY")
  done < <(find "$BUILD_ROOT_PATH" -name "*.entitlements" -print0 2>/dev/null)
fi

echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>' >"$BUILD_ROOT_PATH/emptyEntitlements"

# Select entitlements file
if [ ${#AVAILABLE_ENTITLEMENTS[@]} -eq 0 ]; then
  echo -e "${YELLOW}⚠️  No entitlements files found, using empty entitlements${RESET}"
  ENTITLEMENTS_TO_BUNDLE=""
else
  # Add "None (use empty entitlements)" option
  ENTITLEMENTS_OPTIONS=("${AVAILABLE_ENTITLEMENTS[@]}" "None (use empty entitlements)")
  ENTITLEMENTS_TO_BUNDLE=$(select_from_list "📋 Choose an entitlements file for your app:" "${ENTITLEMENTS_OPTIONS[@]}")
  
  if [[ "$ENTITLEMENTS_TO_BUNDLE" == "None (use empty entitlements)" ]]; then
    ENTITLEMENTS_TO_BUNDLE=""
  fi
fi

echo -e "${GREEN}✅ Chosen entitlements file: ${BOLD}${ENTITLEMENTS_TO_BUNDLE:-'empty entitlements'}${RESET}"

if [[ "$ENTITLEMENTS_TO_BUNDLE" == "" ]]; then
  echo -e "${BLUE}📄 No entitlements defined, using empty${RESET}"
  cp "$BUILD_ROOT_PATH/emptyEntitlements" "$BUILD_ROOT_PATH/bundledEntitlements"
else
  echo -e "${BLUE}📄 Copying entitlements${RESET}"
  cp "$ENTITLEMENTS_TO_BUNDLE" "$BUILD_ROOT_PATH/bundledEntitlements"
fi

$PLISTBUDDY -c "Add :com.apple.developer.team-identifier string APPDBAPPDB" "$BUILD_ROOT_PATH/bundledEntitlements"

# Handle bundle identifier - use project settings if available, otherwise fallback to built Info.plist
if [[ "$CURRENT_BUNDLE_IDENTIFIER" == "(will be read from built Info.plist)" ]]; then
  echo -e "${YELLOW}🔍 Reading bundle identifier from built Info.plist${RESET}"
  CURRENT_BUNDLE_IDENTIFIER=$($PLISTBUDDY -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist" | tr -d '"')
  
  if [[ -z "$CURRENT_BUNDLE_IDENTIFIER" ]]; then
    echo -e "${RED}❌ ERROR: Could not determine bundle identifier from project or built app${RESET}" >&2
    exit 1
  fi
  echo -e "${BLUE}📱 Bundle identifier from built Info.plist: ${BOLD}$CURRENT_BUNDLE_IDENTIFIER${RESET}"
fi

# Update Info.plist with project version settings if they were found
if [[ -n "$PROJECT_MARKETING_VERSION" || -n "$PROJECT_CURRENT_VERSION" ]]; then
  echo -e "${BOLD}${YELLOW}🔄 Updating Info.plist with project version settings${RESET}"
  
  # Get current versions from built Info.plist for comparison
  BUILT_MARKETING_VERSION=$($PLISTBUDDY -c "Print :CFBundleShortVersionString" "$APP_PATH/Info.plist" 2>/dev/null | tr -d '"' || echo "")
  BUILT_CURRENT_VERSION=$($PLISTBUDDY -c "Print :CFBundleVersion" "$APP_PATH/Info.plist" 2>/dev/null | tr -d '"' || echo "")
  
  VERSIONS_UPDATED=false
  
  if [[ -n "$PROJECT_MARKETING_VERSION" && "$PROJECT_MARKETING_VERSION" != "$BUILT_MARKETING_VERSION" ]]; then
    echo -e "${CYAN}🔄 Updating CFBundleShortVersionString from ${BUILT_MARKETING_VERSION:-'unset'} to ${PROJECT_MARKETING_VERSION}${RESET}"
    if [[ -n "$BUILT_MARKETING_VERSION" ]]; then
      $PLISTBUDDY -c "Set :CFBundleShortVersionString $PROJECT_MARKETING_VERSION" "$APP_PATH/Info.plist"
    else
      $PLISTBUDDY -c "Add :CFBundleShortVersionString string $PROJECT_MARKETING_VERSION" "$APP_PATH/Info.plist"
    fi
    VERSIONS_UPDATED=true
  fi
  
  if [[ -n "$PROJECT_CURRENT_VERSION" && "$PROJECT_CURRENT_VERSION" != "$BUILT_CURRENT_VERSION" ]]; then
    echo -e "${CYAN}🔄 Updating CFBundleVersion from ${BUILT_CURRENT_VERSION:-'unset'} to ${PROJECT_CURRENT_VERSION}${RESET}"
    if [[ -n "$BUILT_CURRENT_VERSION" ]]; then
      $PLISTBUDDY -c "Set :CFBundleVersion $PROJECT_CURRENT_VERSION" "$APP_PATH/Info.plist"
    else
      $PLISTBUDDY -c "Add :CFBundleVersion string $PROJECT_CURRENT_VERSION" "$APP_PATH/Info.plist"
    fi
    VERSIONS_UPDATED=true
  fi
  
  if [[ "$VERSIONS_UPDATED" == "true" ]]; then
    echo -e "${GREEN}✅ Info.plist updated with latest project version settings${RESET}"
  else
    echo -e "${GREEN}✅ Bundle versions already match project settings${RESET}"
  fi
else
  echo -e "${BLUE}ℹ️  No version information found in project settings, keeping built Info.plist values${RESET}"
fi

$PLISTBUDDY -c "Add :application-identifier string APPDBAPPDB.$CURRENT_BUNDLE_IDENTIFIER" "$BUILD_ROOT_PATH/bundledEntitlements"

echo -e "${BOLD}${MAGENTA}🔏 Signing...${RESET}"

FRAMEWORKS_AND_DYLIBS=()
while IFS= read -r -d $'\0'; do
  FRAMEWORKS_AND_DYLIBS+=("$REPLY")
  #echo $REPLY
done < <(find "$APP_PATH" -name "*.dylib" -print0)

for file in "${FRAMEWORKS_AND_DYLIBS[@]}"; do
  echo -e "${CYAN}🔧 Removing entitlements from dylib${RESET}"
  $LDID -S "$file"
  echo -e "${CYAN}✍️  Signing dylib: ${BOLD}$file${RESET}"

  if [[ $USE_HSM == 1 ]]; then

    $LDID -w -S -K"$HSM_KEY_URI;pin-value=$HSM_PASSWORD" -X"$HSM_CERT_URI;pin-value=$HSM_PASSWORD" -XAppleWWDRCAG3.cer -XAppleIncRootCertificate.cer -M "$file"
  else
    $LDID -w -K"$P12" -S -M "$file"
  fi
done

FRAMEWORKS_AND_DYLIBS=()
while IFS= read -r -d $'\0'; do
  FRAMEWORKS_AND_DYLIBS+=("$REPLY")
  #echo $REPLY
done < <(find "$APP_PATH" -name "*.framework" -print0)

for file in "${FRAMEWORKS_AND_DYLIBS[@]}"; do
  echo -e "${CYAN}🛠️  Signing framework: ${BOLD}$file${RESET}"
  FRAMEWORK_APP_BINARY=$($PLISTBUDDY -c "Print :CFBundleExecutable" "$file/Info.plist" | tr -d '"')

  echo -e "${CYAN}🔧 Removing entitlements from binary${RESET}"
  $LDID -S "$file/$FRAMEWORK_APP_BINARY"
  echo -e "${CYAN}✍️  Signing${RESET}"

  if [[ $USE_HSM == 1 ]]; then

    $LDID -w -S -K"$HSM_KEY_URI;pin-value=$HSM_PASSWORD" -X"$HSM_CERT_URI;pin-value=$HSM_PASSWORD" -XAppleWWDRCAG3.cer -XAppleIncRootCertificate.cer -M "$file"
  else
    $LDID -w -K"$P12" -S -M "$file"
  fi
done

APP_EXTENSIONS=()
while IFS= read -r -d $'\0'; do
  APP_EXTENSIONS+=("$REPLY")
  #echo $REPLY
done < <(find "$APP_PATH" -name "*.app" -or -name "*.appex" -print0)

for file in "${APP_EXTENSIONS[@]}"; do
  echo -e "${CYAN}📱 Signing app extension: ${BOLD}$file${RESET}"
  if [[ $USE_HSM == 1 ]]; then

    $LDID -w -S -K"$HSM_KEY_URI;pin-value=$HSM_PASSWORD" -X"$HSM_CERT_URI;pin-value=$HSM_PASSWORD" -XAppleWWDRCAG3.cer -XAppleIncRootCertificate.cer -M "$file"
  else
    $LDID -w -K"$P12" -S -M "$file"
  fi
done

# Find and sign additional executable binaries in main app folder (one level deep)
ADDITIONAL_EXECUTABLES=()
while IFS= read -r -d $'\0'; do
  # Get the basename of the file to compare with APP_BINARY
  BASENAME_FILE=$(basename "$REPLY")
  # Skip if it's the main app binary (will be signed separately)
  if [[ "$BASENAME_FILE" != "$APP_BINARY" ]]; then
    ADDITIONAL_EXECUTABLES+=("$REPLY")
  fi
done < <(find "$APP_PATH" -maxdepth 1 -type f -perm +111 -print0 2>/dev/null)

for file in "${ADDITIONAL_EXECUTABLES[@]}"; do
  echo -e "${CYAN}⚙️  Signing additional executable: ${BOLD}$file${RESET}"
  
  echo -e "${CYAN}🔧 Removing entitlements from executable${RESET}"
  $LDID -S "$file"
  echo -e "${CYAN}✍️  Signing executable${RESET}"

  if [[ $USE_HSM == 1 ]]; then
    $LDID -w -S -K"$HSM_KEY_URI;pin-value=$HSM_PASSWORD" -X"$HSM_CERT_URI;pin-value=$HSM_PASSWORD" -XAppleWWDRCAG3.cer -XAppleIncRootCertificate.cer -M "$file"
  else
    $LDID -w -K"$P12" -S -M "$file"
  fi
done

if [[ $USE_HSM == 1 ]]; then

  $LDID -w -S"$BUILD_ROOT_PATH/bundledEntitlements" -K"$HSM_KEY_URI;pin-value=$HSM_PASSWORD" -X"$HSM_CERT_URI;pin-value=$HSM_PASSWORD" -XAppleWWDRCAG3.cer -XAppleIncRootCertificate.cer -M "$APP_PATH/$APP_BINARY"
else
  $LDID -w -K"$P12" -S"$BUILD_ROOT_PATH/bundledEntitlements" -M "$APP_PATH/$APP_BINARY"
fi

echo -e "${BOLD}${BLUE}📋 Resulted entitlements:${RESET}"

codesign -dvvv --entitlements - "$APP_PATH/$APP_BINARY"

# removing ldid dummy files
find "$APP_PATH" -type f -name "*.ldid*" -exec rm -rf {} +

echo -e "${BOLD}${YELLOW}📦 Packaging...${RESET}"

rm -Rf "$BUILD_ROOT_PATH/dist"
mkdir "$BUILD_ROOT_PATH/dist"
mkdir "$BUILD_ROOT_PATH/dist/ditto"
mkdir "$BUILD_ROOT_PATH/dist/ditto/Payload"
mv "$APP_PATH" "$BUILD_ROOT_PATH/dist/ditto/Payload/"
cd "$BUILD_ROOT_PATH/dist/ditto"
zip -3 -qr "../result.ipa" ./*
cd "$BUILD_ROOT_PATH/dist"
rm -Rf "$BUILD_ROOT_PATH/dist/ditto"
rm -f "$BUILD_ROOT_PATH/emptyEntitlements"
rm -f "$BUILD_ROOT_PATH/bundledEntitlements"

echo -e "${BOLD}${GREEN}🎉 Packaging completed! ${CYAN}$BUILD_ROOT_PATH/dist/result.ipa${RESET}"

exit 0
