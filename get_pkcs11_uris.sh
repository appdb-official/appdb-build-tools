#!/bin/bash
# Installation
echo "Getting PKCS11 URIs. Default password is 0001password"
export YUBIHSM_PKCS11_CONF=~/.appdb/yubihsm_pkcs11.conf
p11tool --provider=/usr/local/lib/yubihsm_pkcs11.dylib --list-all --login
