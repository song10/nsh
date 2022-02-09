# Package

version       = "0.1.0"
author        = "Rex Zhuo"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["nsh"]


# Dependencies

requires "nim >= 1.6.2"
requires "cligen >= 1.5.19"
