# ghidra_app
[![Build badge](https://github.com/stevecheckoway/ghidra_app/actions/workflows/ci.yml/badge.svg)](https://github.com/stevecheckoway/ghidra_app/actions/workflows/ci.yml)

Build a working Ghidra application for macOS with a bundled Java JDK.

The build script does _not_ compile Ghidra. Instead, it downloads the binary
release of Ghidra and the required Java JDK and packages them as a
double-clickable Mac application.

This works with both Intel x86-64 and Apple arm64 Macs.

Currently, the claim about not compiling Ghidra is a partial lie. If you are
building `Ghidra.app` for arm64, then the arm64 native executables Ghidra uses
will be built by default. This is because the Ghidra distribution contains
prebuilt binaries for x86-64 macOS, but not for arm64 macOS. The `-b` flag can
be used to build native executables, regardless of the architecture.
Similarly, the `-B` flag can be used to not build native executables (i.e.,
use the prebuilt binaries instead).

Hopefully, arm64 native executables will start being included and this script
will return to simply assembling the macOS application wrapper.

## Usage
Clone the repository and run the `build.bash` script.
```
$ git clone https://github.com/stevecheckoway/ghidra_app.git
$ cd ghidra_app
$ ./build.bash
```

At this point, you should have `Ghidra.app` in the `ghidra_app` directory.

The script will download Ghidra (currently version 11.0 which is the most
recent at time of writing, 2024-01-09) and OpenJDK 17. Together, these take
more than 450 MB.

The downloads will be cached for future use in the `cache` directory. You may
delete this directory after building if you wish.

### Options
There are a few options. You probably want the defaults.

```
Usage: ./build.bash [OPTION...]

Options:
  -a arch build Ghidra.app for x86-64 or arm64 [default: detect]
  -b      build native executables [default for arm64]
  -B      use prebuilt native executables [default for x86-64]
  -f      force building Ghidra.app even if it already exists
  -h      show this help
  -n      use the latest Ghidra version
  -o app  use 'app' as the output name instead of Ghidra.app

```

## Credits

This build script was heavily based on [Yifan
Lu's](https://twitter.com/yifanlu) [Ghidra OSX Launch
Script](https://gist.github.com/yifanlu/e9965cdb148b550335e57899f790cad2). The
Ghidra icon file was taken directly from Lu's GitHub Gist.

The approach for cross compiling the native executables came from [Robin
Lambertz](https://github.com/roblabla/ghidra-ci). The `init.gradle` file is a
modified version of their
[`mac_arm_64.init.gradle`](https://github.com/roblabla/ghidra-ci/blob/7819b5feffdc27214cc133fdab64bb260c22a285/mac_arm_64.init.gradle) file.
