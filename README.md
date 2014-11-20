VBA-M
==========

A [VBA-M](https://github.com/x3ro/VBA-M) fork with lua-scripting support

##How to install

To enable lua scripting support you have to compile it with the `ENABLE_LUACTRL` option.

```sh
cmake -DENABLE_LUACTRL=ON .
make
```

##How to run

To try the project you need to have a .gba rom file for the game you are going to test. For this example let's say you have the Pokemon FireRed rom.

```sh
./vbam -l PokemonFireRed.gba
```

Then press `F11` and you should see the emulator freezing and a lua prompt in your terminal.
If you want to try the firered.lua file included with this repository for exemple, go to the lua prompt and type :

```lua
require 'firered'
```

and then hit CTRL+D to exit the lua interpreter and resume the emulator. If everything worked correctly you should be able to move diagonally.
