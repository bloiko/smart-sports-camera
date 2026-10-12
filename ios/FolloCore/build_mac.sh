#!/bin/sh
# Build follosim on the Mac with the Command Line Tools only (no Xcode): swiftc directly, without SwiftPM.
# Works around a stale /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap (CLT 16.2) that
# breaks every Swift build ("redefinition of module 'SwiftBridging'"): a VFS overlay shows it to clang as empty.
# Usage: ios/FolloCore/build_mac.sh  →  ios/FolloCore/.build-mac/follosim; also type-checks the app files that
# do not need UIKit or HaishinKit (ios/Follo/Follo/LiveCameraRunner.swift) against the FolloCore module.
set -e
cd "$(dirname "$0")"
mkdir -p .build-mac
: > .build-mac/empty.modulemap
cat > .build-mac/overlay.yaml <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [ { "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap", "type": "file", "external-contents": "$PWD/.build-mac/empty.modulemap" } ] }
YAML
FLAGS="${OPT:--O} -Xcc -ivfsoverlay -Xcc .build-mac/overlay.yaml -vfsoverlay .build-mac/overlay.yaml"
swiftc $FLAGS -module-name FolloCore -emit-module -emit-module-path .build-mac/FolloCore.swiftmodule -emit-library -Xlinker -install_name -Xlinker "$PWD/.build-mac/libFolloCore.dylib" -o .build-mac/libFolloCore.dylib Sources/FolloCore/*.swift
swiftc $FLAGS -I .build-mac -L .build-mac -lFolloCore -Xlinker -rpath -Xlinker "$PWD/.build-mac" Sources/follosim/main.swift -o .build-mac/follosim
swiftc $FLAGS -I .build-mac -typecheck ../Follo/Follo/LiveCameraRunner.swift ../Follo/Follo/HighlightsRunner.swift
echo "built .build-mac/follosim (and type-checked LiveCameraRunner.swift, HighlightsRunner.swift)"
