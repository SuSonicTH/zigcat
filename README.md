# zigcat

As a lerning exercise to get to know zig I build a small command line tool that works like cat.
Most GNU cat commandline options are implemented.

### Missing options (all depend on --show-nonprinting)
* -A, --show-all
* -e
* -t
* -v, --show-nonprinting

Feedback from more experienced zig developers is verry welcome.
If you find any bug or you see some non-idiomatic costructs please let me know.

## Usage
see [src/USAGE.txt](https://github.com/SuSonicTH/zigcat/blob/master/src/USAGE.txt)

## Licence
zigcat is licenced under the MIT licence

see [LICENSE.txt](https://github.com/SuSonicTH/zigcat/blob/master/LICENSE.txt)

## Build requirements
To build zigcat you just need the zig compiler, which can be downloaded from [https://ziglang.org/download/](https://ziglang.org/download/)
Currently this builds with zig 0.15.1, I will update the project for future versions.
There is no installation needed, just download the package for your operating system an extract the archive and add it to your `PATH`

## Build
If you have zig installed and on your `PATH` just cd into the directory and execute `zig build`

The first build takes a while and when it's finished you'll find the executeable (zigcat or zigcat.exe) in zig-out/bin/

You can run the built-in uinit tests with `zig build test` If everything is ok you will see no output.

Or you can run `zig test src/main.zig` that should give you the output "All 10 tests passed." if everything is OK.

To create an optimized release build run `zig build -Doptimize=ReleaseFast`
