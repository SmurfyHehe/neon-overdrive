"""No magenta or cyan anywhere (Roy, 2026-10-05). Flags any colour whose hue
sits in the cyan (165-200 deg) or magenta (285-335 deg) band with real
saturation."""
import colorsys

import cars
import options  # noqa: F401
import render


def hue_sat(hx):
    r, g, b = (c / 255 for c in render.hexc(hx))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return h * 360, s, v


def check():
    seen = {}
    for k, v in render.BASE_MATS.items():
        if v:
            seen[f'material {k}'] = v
    for D in cars.FLEET:
        p = D['paint']
        if 'hero' in p:
            seen[f"{D['id']} hero"] = p['hero'][1]
            for n, h in p['alts']:
                seen[f"{D['id']} {n}"] = h
        if 'livery' in p:
            for k, h in p['livery'].items():
                seen[f"{D['id']} livery {k}"] = h
    for n, h, _ in cars.TRAFFIC_PAINTS:
        seen[f'traffic {n}'] = h
    bad = []
    for name, hx in seen.items():
        h, s, v = hue_sat(hx)
        if s > 0.25 and v > 0.2 and (165 <= h <= 200 or 285 <= h <= 335):
            bad.append((name, hx, round(h)))
    return seen, bad


if __name__ == '__main__':
    seen, bad = check()
    print(f'{len(seen)} colours checked; flagged: {bad or "none"}')
    h, s, v = hue_sat('#2E4FD8')
    print(f'police blue #2E4FD8: hue {h:.0f} deg (blue, not cyan), saturation {s:.2f}')
