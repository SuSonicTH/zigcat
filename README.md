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

see [src/LICENSE.txt](https://github.com/SuSonicTH/zigcat/blob/master/src/LICENSE.txt)

## Build requirements
To build zigcat you just need the zig compiler, which can be downloaded from [https://ziglang.org/download/](https://ziglang.org/download/)

There is no installation needed, just download the package for your operating system an extract the archive and add it to your `PATH`

### Windows example
execute following commands in a windows Command Prompt (cmd.exe)
```cmd
curl https://ziglang.org/builds/zig-windows-x86_64-0.11.0-dev.3777+64f0059cd.zip --output zig.zip
tar -xf zig.zip
del zig.zip
move zig-windows-x86_64* zig
set PATH=%cd%\zig;%PATH%
```

### Linux example
execute following commands in a shell
```bash
curl https://ziglang.org/builds/zig-linux-x86_64-0.11.0-dev.3777+64f0059cd.tar.xz --output zig.tar.xz
tar -xf zig.tar.xz
rm zig.tar.xz
mv zig-linux-x86_64* zig
export PATH=$(pwd)/zig:$PATH
```

## Build
If you have zig installed and on your `PATH` just cd into the directory and execute `zig build`

The first build takes a while and when it's finished you'll find the executeable (zigcat or zigcat.exe) in zig-out/bin/

You can run the built-in uinit tests with `zig build test` If everything is ok you will see no output.

Or you can run `zig test src/main.zig` that should give you the output "All 9 tests passed." if everything is OK.

