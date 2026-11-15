; SNES internal header (HiROM, 256KB). Checksum is written by tools/hirom_fix.py
              .section snesheaderextended, root
              .byte   0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
              .section snesheader, root
              .ascii  "NOLFIED              "   ; 21 bytes
              .byte   0x21                    ; HiROM, SlowROM
              .byte   0x00                    ; ROM only
              .byte   0x08                    ; 256KB
              .byte   0x00, 0x01, 0x00, 0x00  ; no SRAM, North America, dev, version
              .word   0xffff, 0x0000          ; checksum complement / checksum
