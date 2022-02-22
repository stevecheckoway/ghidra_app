# ghidra_app
![Build badge](https://github.com/stevecheckoway/ghidra_app/actions/workflows/ci.yml/badge.svg)

Build a working Ghidra application for macOS with a bundled Java JDK.

The build script does _not_ compile Ghidra. Instead, it downloads the binary
release of Ghidra and the required Java JDK and packages them as a
double-clickable Mac application.

This works with both Intel x86-64 and Apple M1 Macs.

This was heavily based on [Yifan Lu's](https://twitter.com/yifanlu) [Ghidra OSX Launch
Script](https://gist.github.com/yifanlu/e9965cdb148b550335e57899f790cad2). The
Ghidra icon file was taken directly from Lu's GitHub Gist.

# Usage
Clone the repository and run the `build.bash` script.
```
$ git clone https://github.com/stevecheckoway/ghidra_app.git
$ cd ghidra_app
$ ./build.bash
```

At this point, you should have `Ghidra.app` in the `ghidra_app` directory.

The script will download Ghidra (currently version 10.1.2 which is the most
recent at time of writing, 2022-02-22) and OpenJDK 11. Together, these take
more than 450~MB.

The downloads will be cached for future use in the `cache` directory. You may
delete this directory after building if you wish.

## Options
There are a few options, they're likely not useful to anyone else.

```
Usage: ./build.bash [OPTION...]

Options:
  -a arch Include the JDK for x86-64 or arm64 [default: detect]
  -f      force building Ghidra.app even if it already exists
  -h      show this help
  -o app  use 'app' as the output name
```
