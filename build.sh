#!/bin/bash
# Installation
echo "Building IPA"
export OPENSSL_CONF=~/.appdb/engine.conf
LDID=./ldid
PLISTBUDDY=/usr/libexec/PlistBuddy

ASK_FOR_HSM=1
USE_HSM=0
HSM_PASSWORD=""
HSM_KEY_URI=""
HSM_CERT_URI=""

if [[ $ASK_FOR_HSM ]]; then
  while true; do
    read -p "Use signing with HSM or hardware key [y/n] " yn
    case $yn in
    [Yy]*)
      USE_HSM=1
      if [[ "$HSM_PASSWORD" == "" ]]; then
        read -p "Enter HSM password [0001password]: " HSM_PASSWORD
        if [[ "$HSM_PASSWORD" == "" ]]; then
          HSM_PASSWORD="0001password"
        fi
      fi
      if [[ "$HSM_KEY_URI" == "" ]]; then
        read -p "Enter HSM private key URI (use ./get_pkcs11_uris.sh to get it): " HSM_KEY_URI
        if [[ "$HSM_KEY_URI" == "" ]]; then
          echo "ERROR: HSM Key URI is required"
          exit 1
        fi
      fi
      if [[ "$HSM_CERT_URI" == "" ]]; then
        read -p "Enter HSM certificate URI (use ./get_pkcs11_uris.sh to get it): " HSM_CERT_URI
        if [[ "$HSM_CERT_URI" == "" ]]; then
          echo "ERROR: HSM Certificate URI is required"
          exit 1
        fi
      fi
      break
      ;;
    [Nn]*) break ;;
    *) echo "Please answer yes or no." ;;
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

if ! [ -f "/usr/bin/xcodebuild" ]; then

  echo "ERROR: Requirements not met. Please use install.sh to make your system ready" >&2
  exit 1
fi

if [[ "$1" != *\.xcodeproj && "$1" != *\.xcodeworkspace ]]; then
  echo "ERROR: Specify path to .xcodeproj or .xcodeworkspace file in argv[1]" >&2
  exit 1
fi

XCODE_PROJECT_FILE=$1
BUILD_ROOT_PATH=$(dirname $1)
XCODE_BUILD_SCHEME=$2

echo "Getting schemes from project"

xcodebuild -project "$XCODE_PROJECT_FILE" -list

if [[ "$XCODE_BUILD_SCHEME" == "" ]]; then
  read -p "Enter scheme to build: " XCODE_BUILD_SCHEME
fi

read -p "Enter build configuration to use [Debug]: " XCODE_BUILD_CONFIGURATION

if [[ "$XCODE_BUILD_SCHEME" == "" ]]; then
  echo "ERROR: no build scheme defined, exiting" >&2
  exit 1
fi

if [[ "$XCODE_BUILD_CONFIGURATION" == "" ]]; then
  XCODE_BUILD_CONFIGURATION="Debug"
fi

echo "Selected build scheme: $XCODE_BUILD_SCHEME"
echo "Selected build configuration: $XCODE_BUILD_CONFIGURATION"

echo "Building..."

rm -Rf "$BUILD_ROOT_PATH/derivedData"

xcodebuild -scheme "$XCODE_BUILD_SCHEME" -project "$XCODE_PROJECT_FILE" -configuration "$XCODE_BUILD_CONFIGURATION" -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$BUILD_ROOT_PATH/derivedData" build CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS='' CODE_SIGNING_ALLOWED=NO

if [ $? -eq 0 ]; then
  echo "Build OK!"
else
  echo "ERROR: Build failed. Fix errors and try again" >&2
  exit 1
fi

echo "Signing and packaging file"

APP_NAME=$(ls "$BUILD_ROOT_PATH/derivedData/Build/Products/Debug-iphoneos" | grep "\.app$")

echo "Got app name $APP_NAME"

APP_PATH="$BUILD_ROOT_PATH/derivedData/Build/Products/Debug-iphoneos/$APP_NAME"

if [ ! -e "$APP_PATH/Info.plist" ]; then
  echo "Expected file does not exist: '$APP_PATH/Info.plist'" >&2
  exit 1
fi

APP_BINARY=$($PLISTBUDDY -c "Print :CFBundleExecutable" "$APP_PATH/Info.plist" | tr -d '"')

echo "Got app binary $APP_BINARY"

echo "Assigning entitlements"

i=0
while read line; do
  AVAILABLE_ENTITLEMENTS[$i]="$line"
  ((i++))
done < <(ls "$BUILD_ROOT_PATH/$XCODE_BUILD_SCHEME/"*.entitlements)

echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>' >"$BUILD_ROOT_PATH/emptyEntitlements"

echo "Choose an entitlements file for your app:"

createmenu "${AVAILABLE_ENTITLEMENTS[@]}"
REPLY=$(expr $REPLY-1)
ENTITLEMENTS_TO_BUNDLE=${AVAILABLE_ENTITLEMENTS["$REPLY"]}
echo "Chosen entitlements file $ENTITLEMENTS_TO_BUNDLE"

if [[ "$ENTITLEMENTS_TO_BUNDLE" == "" ]]; then
  echo "No entitlements defined, using empty"
  cp "$BUILD_ROOT_PATH/emptyEntitlements" "$BUILD_ROOT_PATH/bundledEntitlements"
else
  echo "Copying entitlements"
  cp "$ENTITLEMENTS_TO_BUNDLE" "$BUILD_ROOT_PATH/bundledEntitlements"
fi

$PLISTBUDDY -c "Add :com.apple.developer.team-identifier string APPDBAPPDB" "$BUILD_ROOT_PATH/bundledEntitlements"

CURRENT_BUNDLE_IDENTIFIER=$($PLISTBUDDY -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist" | tr -d '"')

$PLISTBUDDY -c "Add :application-identifier string APPDBAPPDB.$CURRENT_BUNDLE_IDENTIFIER" "$BUILD_ROOT_PATH/bundledEntitlements"

echo "Signing..."

FRAMEWORKS_AND_DYLIBS=()
while IFS= read -r -d $'\0'; do
  FRAMEWORKS_AND_DYLIBS+=("$REPLY")
  #echo $REPLY
done < <(find "$APP_PATH" -name "*.dylib" -print0)

for file in "${FRAMEWORKS_AND_DYLIBS[@]}"; do
  echo "removing entitlements from dylib"
  $LDID -S "$file"
  echo "signing dylib $file"

  if [[ $USE_HSM ]]; then

    $LDID -w -S -K"$HSM_KEY_URI;pin-value=$HSM_PASSWORD" -X"$HSM_CERT_URI;pin-value=$HSM_PASSWORD" -XAppleWWDRCAG3.cer -XAppleIncRootCertificate.cer -M "$file"
  else
    $LDID -w -S -M "$file"
  fi
done

FRAMEWORKS_AND_DYLIBS=()
while IFS= read -r -d $'\0'; do
  FRAMEWORKS_AND_DYLIBS+=("$REPLY")
  #echo $REPLY
done < <(find "$APP_PATH" -name "*.framework" -print0)

for file in "${FRAMEWORKS_AND_DYLIBS[@]}"; do
  echo "signing framework $file"
  FRAMEWORK_APP_BINARY=$($PLISTBUDDY -c "Print :CFBundleExecutable" "$file/Info.plist" | tr -d '"')

  echo "removing entitlements from binary"
  $LDID -S "$file/$FRAMEWORK_APP_BINARY"
  echo "signing"

  if [[ $USE_HSM ]]; then

    $LDID -w -S -K"$HSM_KEY_URI;pin-value=$HSM_PASSWORD" -X"$HSM_CERT_URI;pin-value=$HSM_PASSWORD" -XAppleWWDRCAG3.cer -XAppleIncRootCertificate.cer -M "$file"
  else
    $LDID -w -S -M "$file"
  fi
done

APP_EXTENSIONS=()
while IFS= read -r -d $'\0'; do
  APP_EXTENSIONS+=("$REPLY")
  #echo $REPLY
done < <(find "$APP_PATH" -name "*.app" -or -name "*.appex" -print0)

for file in "${APP_EXTENSIONS[@]}"; do
  echo "signing app extension $file"
  if [[ $USE_HSM ]]; then

    $LDID -w -S -K"$HSM_KEY_URI;pin-value=$HSM_PASSWORD" -X"$HSM_CERT_URI;pin-value=$HSM_PASSWORD" -XAppleWWDRCAG3.cer -XAppleIncRootCertificate.cer -M "$file"
  else
    $LDID -w -S -M "$file"
  fi
done

if [[ $USE_HSM ]]; then

  $LDID -w -S"$BUILD_ROOT_PATH/bundledEntitlements" -K"$HSM_KEY_URI;pin-value=$HSM_PASSWORD" -X"$HSM_CERT_URI;pin-value=$HSM_PASSWORD" -XAppleWWDRCAG3.cer -XAppleIncRootCertificate.cer -M "$APP_PATH/$APP_BINARY"
else
  $LDID -w -S"$BUILD_ROOT_PATH/bundledEntitlements" -M "$file"
fi

echo "Resulted entitlements:"

codesign -dvvv --entitlements - "$APP_PATH/$APP_BINARY"

# removing ldid dummy files
find "$APP_PATH" -type f -name "*.ldid*" -exec rm -rf {} +

echo "Packaging..."

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

echo "Packaging completed. $BUILD_ROOT_PATH/dist/result.ipa"

exit 0
