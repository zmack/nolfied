"""Symbol addresses of the built ROM, for the test tools.

    from syms import S
    S.state, S.grid, S.e_x ...        WRAM offsets (bank $7E/$7F folded in)

Reads build/nolfied.lbl (written by tools/calypsi_lbl.py at link time), so
tests refer to game variables by their C names instead of raw addresses.
Array element sizes: e_x e_y e_vx e_vy e_spd e_half are words; e_type
e_timer i_x i_y i_on x_x x_y x_t are bytes. run_perks: stacks[16] at +0,
total at +16 (see src/perks.h).
"""
import os

_LBL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "nolfied.lbl")


class _Syms:
    def __init__(self, path=_LBL):
        self._a = {}
        for line in open(path):
            _, adr, name = line.split()
            a = int(adr, 16)
            if a >> 16 in (0x7E, 0x7F):
                a &= 0x1FFFF          # high WRAM: offset into the 128KB dump
            self._a[name[1:]] = a

    def __getattr__(self, name):
        try:
            return self._a[name]
        except KeyError:
            raise AttributeError(f"no symbol '{name}' in {_LBL}") from None

    def __getitem__(self, name):
        return self._a[name]

    def get(self, name, default=None):
        return self._a.get(name, default)


S = _Syms()
