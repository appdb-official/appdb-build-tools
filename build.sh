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

CURRENT_BUNDLE_IDENTIFIER=$($PLISTBUDDY -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist" | tr -d '"')

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
