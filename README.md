# appdb IPA build and sign tools (HSM supported)

This set of tools allows you to build IPA packages that is ready to be submitted to [appdb Publisher Area](https://publisher.appdb.to/apps/binary-packages)


## Installation

Run installer (by dropping it on your terminal) and follow instructions

```
./install.sh
```

## Building of an IPA

1. Open Terminal, drag & drop build.sh
2. Drag & drop your .xcodeproject or .xcodeworkspace file

It should look like this (for example):

```./build.sh /Users/apppdb/Downloads/testappdb/TestAppdb.xcodeproj```

3. Follow instructions. Resulted IPA will be in ```dist/``` folder of your project.
4. This IPA then can be uploaded to [IPA Packages area](https://publisher.appdb.to/apps/binary-packages) or distributed elsewhere.

## Using Hardware Security Modules and hardware keys

We have bundled [ProcursusTeam's ldid](https://github.com/ProcursusTeam/ldid) in binary form with support of usage of PKCS11
interface to sign IPA packages with Hardware Security Modules or Keys. You can build it manually if you want to.

This functionality has been tested with:

1. [FIPS 140-2 validated security keys from Yubico](https://www.yubico.com/products/yubikey-fips/).
2. [FIPS 140-2 validated HSM](https://www.yubico.com/products/hardware-security-module/).

**Usage of such Hardware Encryption brings the highest level of security and trust between developer and end user without any intermediates.**

# How can you contribute

We encourage everyone:

1. To join our movement to force Apple to act fair and allow every developer to sign apps with their own certificate and HSMs issued by any globally trusted CA without any additional requirements (e.g. usage of their app store for distribution).
2. To make this set of tools fancier with unicode support and emojis :)
3. To extend this set of tools in order to add automatic uploading to Publisher Area. [API documentation is here](https://api.dbservices.to/v1.7/spec/).
4. Create pull requests and issues, so this code will be improved in time.

Thank you!





