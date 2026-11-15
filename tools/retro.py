#!/usr/bin/env python3
"""Minimal headless libretro host used to play-test the ROM from scripts.

    from retro import Emu
    emu = Emu("build/nolfied.sfc")
    emu.run(60)                       # 60 frames, no input
    emu.run(10, "start")              # hold START for 10 frames
    emu.shot("out.png")
    ram = emu.wram()                  # 128KB work RAM as bytes
"""
import ctypes as C
import os
import struct
import wave

CORE = "/usr/lib/x86_64-linux-gnu/libretro/bsnes_mercury_accuracy_libretro.so"

BUTTONS = {"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5,
           "left": 6, "right": 7, "a": 8, "x": 9, "l": 10, "r": 11}


class GameInfo(C.Structure):
    _fields_ = [("path", C.c_char_p), ("data", C.c_void_p),
                ("size", C.c_size_t), ("meta", C.c_char_p)]


ENV_CB = C.CFUNCTYPE(C.c_bool, C.c_uint, C.c_void_p)
VIDEO_CB = C.CFUNCTYPE(None, C.c_void_p, C.c_uint, C.c_uint, C.c_size_t)
AUDIO_CB = C.CFUNCTYPE(None, C.c_int16, C.c_int16)
AUDIOB_CB = C.CFUNCTYPE(C.c_size_t, C.POINTER(C.c_int16), C.c_size_t)
POLL_CB = C.CFUNCTYPE(None)
STATE_CB = C.CFUNCTYPE(C.c_int16, C.c_uint, C.c_uint, C.c_uint, C.c_uint)


class Emu:
    def __init__(self, rom, core=CORE):
        self.lib = C.CDLL(core)
        self.fmt = 0
        self.frame = None
        self.size = (0, 0)
        self.pressed = set()
        self.audio = bytearray()
        self.frames = 0
        self._sysdir = C.c_char_p(os.path.abspath(os.path.dirname(rom)).encode())

        def env(cmd, data):
            cmd &= 0xFFFF
            if cmd == 10:  # SET_PIXEL_FORMAT
                self.fmt = C.cast(data, C.POINTER(C.c_int))[0]
                return True
            if cmd == 3:  # GET_CAN_DUPE
                C.cast(data, C.POINTER(C.c_bool))[0] = True
                return True
            if cmd in (9, 31):  # system / save directory
                C.cast(data, C.POINTER(C.c_char_p))[0] = self._sysdir.value
                return True
            return False

        def video(data, w, h, pitch):
            if data:
                self.size = (w, h)
                self.frame = (C.string_at(data, pitch * h), w, h, pitch)

        def audio(l, r):
            self.audio += struct.pack("<hh", l, r)

        def audiob(ptr, n):
            self.audio += C.string_at(ptr, n * 4)
            return n

        def poll():
            pass

        def state(port, device, index, bid):
            if port == 0 and device == 1:
                return 1 if bid in self.pressed else 0
            return 0

        self._cbs = [ENV_CB(env), VIDEO_CB(video), AUDIO_CB(audio),
                     AUDIOB_CB(audiob), POLL_CB(poll), STATE_CB(state)]
        L = self.lib
        L.retro_set_environment(self._cbs[0])
        L.retro_set_video_refresh(self._cbs[1])
        L.retro_set_audio_sample(self._cbs[2])
        L.retro_set_audio_sample_batch(self._cbs[3])
        L.retro_set_input_poll(self._cbs[4])
        L.retro_set_input_state(self._cbs[5])
        L.retro_init()
        data = open(rom, "rb").read()
        self._rom = C.create_string_buffer(data, len(data))
        info = GameInfo(os.path.abspath(rom).encode(), C.cast(self._rom, C.c_void_p), len(data), None)
        L.retro_get_memory_data.restype = C.c_void_p
        L.retro_get_memory_size.restype = C.c_size_t
        if not L.retro_load_game(C.byref(info)):
            raise RuntimeError("core refused ROM")

    def run(self, n=1, *buttons):
        self.pressed = {BUTTONS[b] for b in buttons}
        for _ in range(n):
            self.lib.retro_run()
            self.frames += 1
        self.pressed = set()

    def wram(self):
        p = self.lib.retro_get_memory_data(2)
        n = self.lib.retro_get_memory_size(2)
        return C.string_at(p, n)

    def image(self):
        from PIL import Image
        raw, w, h, pitch = self.frame
        if self.fmt == 1 or pitch >= w * 4:
            im = Image.frombuffer("RGBX", (w, h), raw, "raw", "BGRX", pitch, 1).convert("RGB")
        elif self.fmt == 2:
            im = Image.frombuffer("RGB", (w, h), raw, "raw", "BGR;16", pitch, 1)
        else:
            im = Image.frombuffer("RGB", (w, h), raw, "raw", "BGR;15", pitch, 1)
        # hires/interlaced output: scale back to 256x224
        im = im.resize((w // 2 if w > 300 else w, h // 2 if h > 300 else h))
        return im

    def shot(self, path, scale=2):
        im = self.image()
        if scale != 1:
            im = im.resize((im.width * scale, im.height * scale), 0)
        im.save(path)

    def save_wav(self, path):
        with wave.open(path, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(32040)
            w.writeframes(bytes(self.audio))


def _poke(self, addr, data):
    p = self.lib.retro_get_memory_data(2)
    C.memmove(p + addr, bytes(data), len(data))


Emu.poke = _poke
