# micropython ESP32
# ZX spectrum RAM snapshot image loader

# AUTHOR=EMARD
# LICENSE=BSD

# this code is SPI master to FPGA SPI slave
# FPGA sends pulse to GPIO after BTN state is changed.
# on GPIO pin interrupt from FPGA:
# btn_state = SPI_read
# SPI_write(buffer)
# FPGA SPI slave will accept image and start it

#from machine import SPI, Pin, SDCard, Timer
#from micropython import const, alloc_emergency_exception_buf
#from uctypes import addressof
from struct import unpack
#from time import sleep_ms
#import os

#import ecp5
#import gc

class ld_zxspectrum:
  def __init__(self,spi,cs):
    self.spi=spi
    self.cs=cs
    self.cs.off()
    self.rom="/sd/zxspectrum/roms/opense.rom"

  # LOAD/SAVE and CPU control

  # read from file -> write to SPI RAM
  def load_stream(self, filedata, addr=0, maxlen=0x10000, blocksize=1024):
    block = bytearray(blocksize)
    # Request load
    self.cs.on()
    self.spi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
    bytes_loaded = 0
    while bytes_loaded < maxlen:
      if filedata.readinto(block):
        self.spi.write(block)
        bytes_loaded += blocksize
      else:
        break
    self.cs.off()

  # read from SPI RAM -> write to file
  def save_stream(self, filedata, addr=0, length=1024, blocksize=1024):
    bytes_saved = 0
    block = bytearray(blocksize)
    # Request save
    self.cs.on()
    self.spi.write(bytearray([1,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, 0]))
    while bytes_saved < length:
      self.spi.readinto(block)
      filedata.write(block)
      bytes_saved += len(block)
    self.cs.off()

  def ctrl(self,i):
    self.cs.on()
    self.spi.write(bytearray([0, 0xFF, 0xFF, 0xFF, 0xFF, i]))
    self.cs.off()

  def cpu_halt(self):
    self.ctrl(2)

  def cpu_continue(self):
    self.ctrl(0)

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
            self.spi.write(b)
        if s==1:
          if b[0]==escbyte[0]:
            nexts=2
          else:
            self.spi.write(escbyte)
            self.spi.write(b)
            nexts=0
        if s==2:
          repeat=b[0]
          if repeat==0:
            print("end")
            break
          nexts=3
        if s==3:
          self.spi.read(repeat,b[0])
          nexts=0
        s=nexts
        bytes_loaded += 1
      else:
        break
    print("bytes loaded %d" % bytes_loaded)

  def load_z80_v1_compressed_block(self, filedata):
    self.cs.on()
    self.spi.write(bytearray([0,0,0,0x40,0])) # from 0x4000
    self.load_z80_compressed_stream(filedata)
    self.cs.off()

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
    #print("addr=%04X compress=%d" % (addr,compress))
    if compress:
      # Request load
      self.cs.on()
      self.spi.write(bytearray([0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF]))
      self.load_z80_compressed_stream(filedata,length)
      self.cs.off()
    else:
      print("uncompressed v2/v3 may need FIXME")
      self.load_stream(filedata,addr,16384)
    return True
  
  def patch_rom(self,pc,header):
    # overwrite tape saving code in original ROM
    # with restore code and data from header
    code_addr = 0x4C2
    header_addr = 0x500
    self.cs.on()
    self.spi.write(bytearray([0, 0,0,0,0, 0xF3, 0xAF, 0x11, 0xFF, 0xFF, 0xC3, code_addr&0xFF, (code_addr>>8)&0xFF])) # overwrite start of ROM to JP 0x04C2
    self.cs.off()
    self.cs.on()
    self.spi.write(bytearray([0, 0,0,(code_addr>>8)&0xFF,code_addr&0xFF])) # overwrite 0x04C2
    # Z80 code that POPs REGs from header as stack data at 0x500
    # z80asm restore.z80asm; hexdump -v -e '/1 "0x%02X,"' a.bin
    # restores border color, registers I, AFBCDEHL' and AFBCDEHL
    self.spi.write(bytearray([0x31,(header_addr+9)&0xFF,((header_addr+9)>>8)&0xFF,0xF1,0xED,0x47,0xF1,0x1F,0xD3,0xFE,0xD1,0xD9,0xC1,0xD1,0xE1,0xD9,0xF1,0x08,0xFD,0xE1,0xDD,0xE1,0x21,0xE5,0xFF,0x39,0xF9,0xF1,0xC1,0xE1]));
    self.spi.write(bytearray([0x31])) # LD SP, ...
    self.spi.write(header[8:10])
    self.spi.write(bytearray([0xED])) # IM ...
    imarg = bytearray([0x46,0x56,0x5E,0x5E])
    self.spi.write(bytearray([imarg[header[29]&3]])) # IM mode
    if header[27]:
      self.spi.write(bytearray([0xFB])) # EI
    header[6]=pc&0xFF
    header[7]=(pc>>8)&0xFF
    self.spi.write(bytearray([0xC3])) # JP ...
    self.spi.write(header[6:8]) # PC address of final JP
    self.cs.off()
    self.cs.on()
    self.spi.write(bytearray([0, 0,0,(header_addr>>8)&0xFF,header_addr&0xFF])) # overwrite 0x0500 with header
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
    self.spi.write(header) # AF and AF' now POPable
    self.cs.off()

  def loadz80(self,filename):
    z=open(filename,"rb")
    header1 = bytearray(30)
    z.readinto(header1)
    pc=unpack("<H",header1[6:8])[0]
    self.cpu_halt()
    self.load_stream(open(self.rom, "rb"), addr=0)
    if pc: # V1 format
      print("Z80 v1")
      self.patch_rom(pc,header1)
      if header1[12] & 32:
        self.load_z80_v1_compressed_block(z)
      else:
        self.load_stream(z,0x4000)
    else: # V2 or V3 format
      word = bytearray(2)
      z.readinto(word)
      length2 = unpack("<H", word)[0]
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
      self.patch_rom(pc,header1)
      while self.load_z80_v23_block(z):
        pass
    z.close()
    self.ctrl(3) # reset and halt
    self.ctrl(1) # only reset
    self.cpu_continue()
    # restore original ROM after image starts
    self.cpu_halt()
    self.load_stream(open(self.rom, "rb"), addr=0)
    self.cpu_continue() # release reset

