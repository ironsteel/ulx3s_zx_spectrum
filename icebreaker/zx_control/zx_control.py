#!/usr/bin/env python3

from struct import unpack
import argparse
import time
import struct
from PIL import Image
import evdev

import control

# Shameless copy from emard's esp32 and ps2 code
# and tnt's ftdi control code
class ZXSpectrumControl(control.BoardControlBase):

  def __init__(self, **kwargs):
    # Super call
    super().__init__(**kwargs)
    self.rom="../../roms/opense.rom"

  def write(self, data):
    self.slave.write(data, False, False)

  def cson(self):
    self.slave.force_select(False)

  def csoff(self):
    self.slave.force_select(True)

  def ctrl(self, i):
    self.slave.force_select(False)
    self.write(bytearray([0x00, 0xFF, 0xFF, 0xFF, 0xFF, i]))
    self.slave.force_select(True)

  def key_press(self, i):
    self.slave.force_select(False)
    self.write(bytearray([0x00, 0xF1, 0xFF, 0xFF, 0xF0, i]))
    self.slave.force_select(True)
    time.sleep(0.03);
    self.slave.force_select(False)
    self.write(bytearray([0x00, 0xF3, 0xFF, 0xFF, 0xF0, i]))
    self.slave.force_select(True)

  def key_release(self, i):
    self.slave.force_select(False)
    self.write(bytearray([0x00, 0xF2, 0xFF, 0xFF, 0xF0, i]))
    self.slave.force_select(True)
    time.sleep(0.03);
    self.slave.force_select(False)
    self.write(bytearray([0x00, 0xF4, 0xFF, 0xFF, 0xF0, i]))
    self.slave.force_select(True)

  def cpu_halt(self):
    self.ctrl(2)

  def cpu_continue(self):
    self.ctrl(0)

  # read from file -> write to SPI RAM
  def load_stream(self, filedata, addr=0, maxlen=0x10000, blocksize=8):
    block = bytearray(blocksize)
    self.slave.force_select(False)
    # Request load
    self.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
    bytes_loaded = 0
    while bytes_loaded < maxlen:
      if filedata.readinto(block):
        self.write(block)
        bytes_loaded += blocksize
      else:
        break
    self.slave.force_select(True)

  def load_z80_compressed_stream(self, filedata, length=0xFFFF):
    b=bytearray(1)
    escbyte=bytearray([0xED])
    s=0
    repeat=0
    bytes_loaded=0
    while bytes_loaded < length:
      if filedata.readinto(b):
        nexts=s
        if s==0:
          if b[0]==escbyte[0]:
            nexts=1
          else:
            self.write(b)
        if s==1:
          if b[0]==escbyte[0]:
            nexts=2
          else:
            self.write(escbyte)
            self.write(b)
            nexts=0
        if s==2:
          repeat=b[0]
          if repeat==0:
            print("end")
            break
          nexts=3
        if s==3:
          self.slave.exchange(bytearray([b[0]] * repeat), 0, False, False)
          nexts=0
        s=nexts
        bytes_loaded += 1
      else:
        break
    print("bytes loaded %d" % bytes_loaded)

  def load_z80_v1_compressed_block(self, filedata):
    self.cson()
    self.write(bytearray([0,0,0,0x40,0])) # from 0x4000
    self.load_z80_compressed_stream(filedata)
    self.csoff()

  def load_z80_v23_block(self, filedata):
    header = bytearray(3)
    if filedata.readinto(header):
      length,page = unpack("<HB",header)
      print("load z80 block: length=%d, page=%d" % (length,page))
    else:
      return False
    addr = -1
    if page==4:
      addr=0x8000
    if page==5:
      addr=0xC000
    if page==8:
      addr=0x4000
    if addr < 0:
      print("unsupported page ignored")
      filedata.seek(length,1)
      return True
    if length==0xFFFF:
      compress=0
      length=0x4000
    else:
      compress=1
    print("addr=%04X compress=%d" % (addr,compress))
    if compress:
      # Request load
      self.cson()
      self.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
      self.load_z80_compressed_stream(filedata,length)
      self.csoff()
    else:
      print("uncompressed v2/v3 may need FIXME")
      self.load_stream(filedata,addr,16384)
    return True
  
  def patch_rom(self,pc,header):
    # overwrite tape saving code in original ROM
    # with restore code and data from header
    code_addr = 0x4C2
    header_addr = 0x500
    self.cson()
    self.write(bytearray([0, 0,0,0,0, 0xF3, 0xAF, 0x11, 0xFF, 0xFF, 0xC3, code_addr&0xFF, (code_addr>>8)&0xFF])) # overwrite start of ROM to JP 0x04C2
    self.csoff()
    self.cson()
    self.write(bytearray([0, 0,0,(code_addr>>8)&0xFF,code_addr&0xFF])) # overwrite 0x04C2
    # Z80 code that POPs REGs from header as stack data at 0x500
    # z80asm restore.z80asm; hexdump -v -e '/1 "0x%02X,"' a.bin
    # restores border color, registers I, AFBCDEHL' and AFBCDEHL
    self.write(bytearray([0x31,(header_addr+9)&0xFF,((header_addr+9)>>8)&0xFF,0xF1,0xED,0x47,0xF1,0x1F,0xD3,0xFE,0xD1,0xD9,0xC1,0xD1,0xE1,0xD9,0xF1,0x08,0xFD,0xE1,0xDD,0xE1,0x21,0xE5,0xFF,0x39,0xF9,0xF1,0xC1,0xE1]));
    self.write(bytearray([0x31])) # LD SP, ...
    self.write(header[8:10])
    self.write(bytearray([0xED])) # IM ...
    imarg = bytearray([0x46,0x56,0x5E,0x5E])
    self.write(bytearray([imarg[header[29]&3]])) # IM mode
    if header[27]:
      self.write(bytearray([0xFB])) # EI
    header[6]=pc&0xFF
    header[7]=(pc>>8)&0xFF
    self.write(bytearray([0xC3])) # JP ...
    self.write(header[6:8]) # PC address of final JP
    self.csoff()
    self.cson()
    self.write(bytearray([0, 0,0,(header_addr>>8)&0xFF,header_addr&0xFF])) # overwrite 0x0500 with header
    # header fix: exchange A and F, A' and F' to become POPable
    x=header[0]
    header[0]=header[1]
    header[1]=x
    x=header[21]
    header[21]=header[22]
    header[22]=x
    if header[12]==255:
      header[12]=1
    #header[12] ^= 7<<1 # FIXME border color
    self.write(header) # AF and AF' now POPable
    self.csoff()

  def loadz80(self,filename):
    z=open(filename,"rb")
    header1 = bytearray(30)
    z.readinto(header1)
    pc=unpack("<H",header1[6:8])[0]
    self.cpu_halt()
    self.load_stream(open(self.rom, "rb"), addr=0)
    print("pc=%04X pc=%d" % (pc,pc))
    if pc: # V1 format
      print("Z80 v1")
      self.patch_rom(pc,header1)
      if header1[12] & 32:
        print("Z80 v1 loading compressed")
        self.load_z80_v1_compressed_block(z)
      else:
        print("Z80 v1 loading")
        self.load_stream(z,0x4000)
    else: # V2 or V3 format
      word = bytearray(2)
      z.readinto(word)
      length2 = unpack("<H", word)[0]
      print("length2=%04X length2=%d" % (length2,length2))
      if length2 == 23:
        print("Z80 v2")
      else:
        if length2 == 54 or length2 == 55:
          print("Z80 v3")
        else:
          print("unsupported header2 length %d" % length2)
          return
      header2 = bytearray(length2)
      z.readinto(header2)
      pc=unpack("<H",header2[0:2])[0]
      print("pc=%04X pc=%d" % (pc,pc))
      self.patch_rom(pc,header1)
      while self.load_z80_v23_block(z):
        pass
    z.close()
    self.ctrl(3) # reset and halt
    self.ctrl(1) # only reset
    self.cpu_continue()
    self.cpu_halt()
    self.cpu_continue() # release reset


def load_z80(zx, z80_filename):
  zx.key_press(0x5A);
  zx.key_release(0x5A);
  zx.loadz80(z80_filename)

def load_rom(zx, rom_filename):
  zx.ctrl(3);
  zx.load_stream(open(rom_filename, "rb"), addr=0)
  zx.ctrl(0);

def keyboard(zx):
    # from http://www.vetra.com/scancodes.html
    keymap_ps2_scan2 = {
      'KEY_GRAVE'     : 0x0E,
      'KEY_1'         : 0x16,
      'KEY_2'         : 0x1E,
      'KEY_3'         : 0x26,
      'KEY_4'         : 0x25,
      'KEY_5'         : 0x2E,
      'KEY_6'         : 0x36,
      'KEY_7'         : 0x3D,
      'KEY_8'         : 0x3E,
      'KEY_9'         : 0x46,
      'KEY_0'         : 0x45,
      'KEY_MINUS'     : 0x4E,
      'KEY_EQUAL'     : 0x55,
      'KEY_BACKSPACE' : 0x66,
      'KEY_TAB'       : 0x0D,
      'KEY_Q'         : 0x15,
      'KEY_W'         : 0x1D,
      'KEY_E'         : 0x24,
      'KEY_R'         : 0x2D,
      'KEY_T'         : 0x2C,
      'KEY_Y'         : 0x35,
      'KEY_U'         : 0x3C,
      'KEY_I'         : 0x43,
      'KEY_O'         : 0x44,
      'KEY_P'         : 0x4D,
      'KEY_LEFTBRACE' : 0x54,
      'KEY_RIGHTBRACE': 0x5B,
      'KEY_CAPSLOCK'  : 0x58,
      'KEY_A'         : 0x1C,
      'KEY_S'         : 0x1B,
      'KEY_D'         : 0x23,
      'KEY_F'         : 0x2B,
      'KEY_G'         : 0x34,
      'KEY_H'         : 0x33,
      'KEY_J'         : 0x3B,
      'KEY_K'         : 0x42,
      'KEY_L'         : 0x4B,
      'KEY_SEMICOLON' : 0x4C,
      'KEY_APOSTROPHE': 0x52,
      'KEY_ENTER'     : 0x5A,
      'KEY_LEFTSHIFT' : 0x12,
      'KEY_Z'         : 0x1A,
      'KEY_X'         : 0x22,
      'KEY_C'         : 0x21,
      'KEY_V'         : 0x2A,
      'KEY_B'         : 0x32,
      'KEY_N'         : 0x31,
      'KEY_M'         : 0x3A,
      'KEY_COMMA'     : 0x41,
      'KEY_DOT'       : 0x49,
      'KEY_SLASH'     : 0x4A,
      'KEY_RIGHTSHIFT': 0x59,
      'KEY_LEFTCTRL'  : 0x14,
      'KEY_LEFTALT'   : 0x11,
      'KEY_SPACE'     : 0x29,
      'KEY_RIGHTALT'  :(0x11 | 0x80),
      'KEY_RIGHTCTRL' :(0x14 | 0x80),
      'KEY_INSERT'    :(0x70 | 0x80),
      'KEY_DELETE'    :(0x71 | 0x80),
      'KEY_HOME'      :(0x6C | 0x80),
      'KEY_END'       :(0x69 | 0x80),
      'KEY_PAGEUP'    :(0x7D | 0x80),
      'KEY_PAGEDOWN'  :(0x7A | 0x80),
      'KEY_UP'        :(0x75 | 0x80),
      'KEY_DOWN'      :(0x72 | 0x80),
      'KEY_LEFT'      :(0x6B | 0x80),
      'KEY_RIGHT'     :(0x74 | 0x80),
      'KEY_NUMLOCK'   :(0x77 | 0x80),
      'KEY_KP7'       : 0x6C,
      'KEY_KP4'       : 0x6B,
      'KEY_KP1'       : 0x69,
      'KEY_KPSLASH'   :(0x4A | 0x80),
      'KEY_KP8'       : 0x75,
      'KEY_KP5'       : 0x73,
      'KEY_KP2'       : 0x72,
      'KEY_KP0'       : 0x70,
      'KEY_KPASTERISK': 0x7C,
      'KEY_KP9'       : 0x7D,
      'KEY_KP6'       : 0x74,
      'KEY_KP3'       : 0x7A,
      'KEY_KPPLUS'    : 0x79,
      'KEY_KPENTER'   :(0x5A | 0x80),
      'KEY_ESC'       : 0x76,
      'KEY_F1'        : 0x05,
      'KEY_F2'        : 0x06,
      'KEY_F3'        : 0x04,
      'KEY_F4'        : 0x0C,
      'KEY_F5'        : 0x03,
      'KEY_F6'        : 0x0B,
      'KEY_F7'        : 0x83,
      'KEY_F8'        : 0x0A,
      'KEY_F9'        : 0x01,
      'KEY_F10'       : 0x09,
      'KEY_F11'       : 0x78,
      'KEY_F12'       : 0x07,
      'KEY_SCROLLLOCK': 0x7E,
      'KEY_BACKSLASH' : 0x5D,
    }
    # convert keys to input events evdev.ecodes.ecodes[key]
    event2ps2 = { }
    for key in keymap_ps2_scan2:
      event2ps2[evdev.ecodes.ecodes[key]] = keymap_ps2_scan2[key]
    DEVICE = None

    DEVICES = [evdev.InputDevice(fn) for fn in evdev.list_devices()]

    device = "/dev/input/event3"
    for d in DEVICES:
          if d.path == device:
            print('Found %s at %s...' % (d.name, d.path))
            DEVICE = d

    for event in DEVICE.read_loop():
        if event.type == evdev.ecodes.EV_KEY:
            if event.code in event2ps2:
                code = event2ps2[event.code]
                if event.value == 1: # key press
                  zx.key_press(code);
                if event.value == 0: # key release
                  zx.key_release(code);

def main():
  # Parse options
  parser = argparse.ArgumentParser(
    formatter_class=argparse.ArgumentDefaultsHelpFormatter
  )
  g_zx  = parser.add_argument_group('zx',  'ZX Spectrum Control options')
  g_brd   = parser.add_argument_group('board', 'Board configuration options')

  g_zx.add_argument('--load-rom', type=str, help='Load and execute rom file')
  g_zx.add_argument('--load-z80', type=str, help='Load and execute z80 snapshot')
  g_zx.add_argument('--keyboard', help='Load and execute z80 snapshot', action="store_true", default=False)

  control.arg_group_setup(g_brd)

  args = parser.parse_args()

  # Build control object with those params
  kwargs = control.arg_to_kwargs(args)

  zx = ZXSpectrumControl(**kwargs)

  if args.load_rom != None:
    load_rom(zx, args.load_rom)

  if args.load_z80 != None:
    load_z80(zx, args.load_z80)

  if args.keyboard:
    keyboard(zx)



if __name__ == '__main__':
  main()
