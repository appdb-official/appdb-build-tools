#!/bin/bash
# Installation
echo "Running removal"

brew remove yubihsm2-sdk
brew remove pkcs11-tools
brew remove libp11
rm -f /usr/local/lib/yubihsm_pkcs11.dylib
rm -Rf ~/.appdb

echo "removal has been completed"
exit 0
