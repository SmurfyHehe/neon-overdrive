"""P1, the sports coupe: what it adds to the common parts recipe.

The coupe was the pilot and is otherwise the common recipe. Its four round
tail lamps are running lamps only (glow_tail), so the lamps the game lights
one by one are added here: a white reversing lamp each side, inboard of the
round lamps on the black tail panel, and a high brake lamp at the top of the
rear glass, above the hoop wing (2026-10-11: the pilot had neither, so the
car showed no brake or reverse light from behind).

Kept in its own file like the other kits; kits.KITS imports KIT from here.
"""
import kits as K

REVERSE = (0.30, 0.635, 0.38, 0.685)   # right reversing lamp (rear view), on the tail panel inboard of the round lamps
BRAKE_C = (-0.12, 1.195, 0.12, 1.215)  # the high brake lamp at the top of the rear glass, above the wing, 0.24 x 0.02


def _fittings(ctx):
    part = ctx.part
    # both sides, so parts.symmetrize() pairs them and writes the left as the right's mirror
    x0, y0, x1, y1 = REVERSE
    for sx, nm in ((1, 'r'), (-1, 'l')):
        xa, xb = sorted((sx * x0, sx * x1))
        K.lay(ctx, part('reverse_' + nm, bevel=0), 'rear', K.rect2(xa, y0, xb, y1), 'glow_reverse', 0.006)
    cx0, cy0, cx1, cy1 = BRAKE_C
    hb = part('brake_c', bevel=0)
    K.lay(ctx, hb, 'rear', K.rect2(cx0 - 0.01, cy0 - 0.008, cx1 + 0.01, cy1 + 0.008), 'plastic', 0.004)
    K.lay(ctx, hb, 'rear', K.rect2(cx0, cy0, cx1, cy1), 'glow_brake', 0.006)


KIT = {'fittings': _fittings}
