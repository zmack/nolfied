; SNES internal header for the HiROM benchmark ROM
              .section snesheaderextended, root
              .byte   0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
              .section snesheader, root
              .ascii  "NOLFIED C BENCH      "   ; 21 bytes
              .byte   0x21                    ; HiROM, SlowROM
              .byte   0x00                    ; ROM only
              .byte   0x06                    ; 64KB
              .byte   0x00, 0x01, 0x00, 0x00
              .word   0xffff, 0x0000          ; checksum fixed afterwards
