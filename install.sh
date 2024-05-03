#!/bin/bash
# Installation
echo "Running installation"

function installYubiSDK() {
  if [[ "$(brew list --cask | grep yubihsm2-sdk)" == "" ]]; then
    echo "yubihsm2-sdk is not installed, installing..."
    brew install yubihsm2-sdk --cask
    echo "fixing dylib path"
    cp /usr/local/lib/pkcs11/yubihsm_pkcs11.dylib /usr/local/lib/yubihsm_pkcs11.dylib
    echo "done fixing path"
  else
    echo "yubihsm2-sdk is already installed"
  fi

  mkdir ~/.appdb
  cp -f engine.conf ~/.appdb/
  echo 'connector = http://127.0.0.1:12345' > ~/.appdb/yubihsm_pkcs11.conf

  echo "Yubico support has been installed. OpenSSL configuration file has been saved to ~/.appdb/engine.conf"

}

function installPKCS11Support() {
  if [[ "$(brew list | grep pkcs11-tools)" == "" ]]; then
    echo "pkcs11-tools is not installed, installing..."
    brew install pkcs11-tools
  else
    echo "pkcs11-tools is already installed"
  fi

  if [[ "$(brew list | grep libp11)" == "" ]]; then
    echo "libp11 is not installed, installing..."
    brew install libp11
  else
    echo "libp11 is already installed"
  fi

  echo "PKCS11 support has been installed"
}

echo "Checking requirements"

if ! [ -f "/opt/homebrew/bin/brew" ]; then

  echo "ERROR: homebrew is not installed. Please install it from https://brew.sh/" >&2
  exit 1
fi

if ! [ -f "/usr/bin/xcodebuild" ]; then

  echo "ERROR: xcodebuild is not installed. Install it with: xcode-select --install" >&2
  exit 1
fi

while true; do
  read -p "Do you want to install Hardware Security Module and Keys support for software signing (Yubico)? [y/n] " yn
  case $yn in
  [Yy]*)
    installYubiSDK
    break
    ;;
  [Nn]*) break ;;
  *) echo "Please answer yes or no." ;;
  esac
done

while true; do
  read -p "Do you want to install PKCS11 library support for software signing with PKCS11-compatible hardware keys? [y/n] " yn
  case $yn in
  [Yy]*)
    installPKCS11Support
    break
    ;;
  [Nn]*) break ;;
  *) echo "Please answer yes or no." ;;
  esac
done

echo "Installation has been completed. Now you can use build.sh to build your IPA files. If you are using HSM from Yubico, make sure to start yubihsm-connector prior to signing"
