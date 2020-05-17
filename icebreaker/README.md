# ZX spectrum for the icebreaker

Verilog ZX Spectrum 48k core for the icebreaker board.

Supports DVI output using onebitsquered 12bit DVI PMOD.

Uses the SPI channel on the icebreaker's FTDI chip for keyboard input
and ROM/z80 snapshot loading

Does not support models other than the Spectrum 16k and 48k.

The open source ZX Spectrum Basic opense.rom is used. The original ZX Spectrum 48k rom (48.rom) also works and can be downloaded from [here](http://www.shadowmagic.org.uk/spectrum/roms.html).

To build and upload the bit file, do:


```sh
cd icebreaker
make prog
```

pyftdi python module is required for the host control code.

To load the opense rom do:

```
cd zx_control/
./zx_control.py --load-rom ../../roms/opense.rom
```

The ROM welcome screen should appear immediately.

If you can try loading the wow.z80 snapshot by:
```
./zx_control.py --load-z80 ../../snapshots/wow.z80
```

To listen for keyboard events and send them to the board do:

```python
./zx_control.py --keyboard /dev/input/eventXX
```

You may need to chmod the input device so the script can be run without sudo

For loading a z80 snapshot and then listen for keyboard events do:
```
./zx_control.py --load-z80 ../../snapshots/wow.z80 --keyboard /dev/input/eventXX
```
