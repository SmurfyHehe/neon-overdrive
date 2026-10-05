"""Swappable parts (stage B1 design). Each option is a list of edits to the
car definition: add/remove parts and decals, reshape a curve, change wheels,
exhaust tips or ride height. Every option changes the visible shape, the
wheels or the paint, as Roy asked (2026-10-05). Physics effects belong to the
stage E mod trees, not here."""
import math

from geom import pl


def _deck(D, s):
    return pl(D['top'], s)


def _floor(D, s):
    return pl(D['floor'], s)


def _arch_r(D):
    w = D['wheel']
    return w['r'] + w.get('arch_gap', 0.03)


# ---------------------------------------------------------------- bumpers
def lip(D):
    return {'label': 'Lip splitter', 'ops': [
        {'op': 'add', 'part': {'type': 'splitter', 's0': -0.05, 's1': 0.30, 'y': _floor(D, 0.12) - 0.005, 'w': D['W'] * 0.84}}]}


def race_front(D):
    """Deeper race bumper: lower nose line, protruding splitter, canards,
    bigger intake."""
    f0 = _floor(D, 0.0)
    f1 = _floor(D, 0.30)
    hw = D['W'] / 2
    return {'label': 'Race bumper', 'ops': [
        {'op': 'curve', 'curve': 'floor', 'keys': [(0.0, f0 - 0.06), (0.30, f1 - 0.025)]},
        {'op': 'add', 'part': {'type': 'splitter', 's0': -0.09, 's1': 0.32, 'y': f1 - 0.03, 'w': D['W'] * 0.90}},
        {'op': 'add', 'part': {'type': 'box', 's': 0.10, 'xy': (hw * 0.86, f0 + 0.06), 'size': (0.16, 0.012, 0.10), 'mat': 'trim'}},
        {'op': 'add', 'part': {'type': 'box', 's': 0.10, 'xy': (-hw * 0.86, f0 + 0.06), 'size': (0.16, 0.012, 0.10), 'mat': 'trim'}},
        {'op': 'remove_decals', 'tag': 'fbumper'},
        {'op': 'decal', 'decal': {'view': 'front', 'rect': (-hw * 0.62, f0 - 0.03, hw * 0.62, f0 + 0.14), 'mat': 'grille', 'tag': 'fbumper'}},
    ]}


def diffuser(D):
    L = D['L']
    return {'label': 'Diffuser', 'ops': [
        {'op': 'add', 'part': {'type': 'diffuser', 'y': _floor(D, L - 0.15) + 0.005, 'w': D['W'] * 0.62, 'd': 0.32, 'fins': 4}}]}


# ---------------------------------------------------------------- hood
def vented_hood(D, s0, s1):
    """Twin vents and a raised centre bulge (the bulge shows in the outline)."""
    a, b = s0 + (s1 - s0) * 0.25, s0 + (s1 - s0) * 0.75
    return {'label': 'Vented hood', 'ops': [
        {'op': 'curve', 'curve': 'top', 'keys': [(a, _deck(D, a) + 0.025), (b, _deck(D, b) + 0.025)]},
        {'op': 'decal', 'decal': {'view': 'top', 'rect': (0.12, a, 0.36, a + 0.30), 'mat': 'grille', 'mirror': True}},
    ]}


def scoop(D, s0, s1, w=0.5, h=0.08, label='Hood scoop'):
    return {'label': label, 'ops': [
        {'op': 'remove', 'tag': 'hood'},
        {'op': 'add', 'part': {'type': 'scoop', 'tag': 'hood', 's0': s0, 's1': s1, 'w': w, 'h': h}}]}


def flat_hood(label='Flat hood (sleeper)'):
    return {'label': label, 'ops': [{'op': 'remove', 'tag': 'hood'}]}


# ---------------------------------------------------------------- sides
def skirts(D):
    Ra = _arch_r(D)
    s0 = D['OHf'] + Ra + 0.04
    s1 = D['OHf'] + D['WB'] - Ra - 0.04
    return {'label': 'Side skirts', 'ops': [
        {'op': 'add', 'part': {'type': 'skirts', 's0': s0, 's1': s1}}]}


def widebody(D, add_track=0.08):
    Ra = _arch_r(D)
    s0 = D['OHf'] + Ra + 0.12
    s1 = D['OHf'] + D['WB'] - Ra - 0.12
    w = D['wheel']
    return {'label': 'Wide-body overfenders', 'ops': [
        {'op': 'add', 'part': {'type': 'flares', 'band': 0.11, 'proud': 0.055, 'tag': 'widebody'}},
        {'op': 'add', 'part': {'type': 'skirts', 's0': s0, 's1': s1}},
        {'op': 'set', 'path': 'wheel.track', 'value': round(w['track'] + add_track, 3)},
        {'op': 'set', 'path': 'wheel.w', 'value': round(w['w'] + 0.02, 3)},
    ]}


# ---------------------------------------------------------------- aero
def ducktail(D, h=0.04, label='Ducktail'):
    L = D['L']
    keys = [(s, v) for s, v in D['top'] if L - 0.45 <= s <= L - 0.02]
    s_last, y_last = max(keys)
    return {'label': label, 'ops': [
        {'op': 'remove', 'tag': 'spoiler'},
        {'op': 'curve', 'curve': 'top', 'keys': [(s_last - 0.10, _deck(D, s_last - 0.10) + h * 0.5), (s_last, y_last + h)]}]}


def gt_wing(D, height=0.26, span=None, chord=0.30, label='GT wing'):
    L = D['L']
    s1 = L - 0.06
    s0 = s1 - chord
    y = _deck(D, 0.5 * (s0 + s1)) + height
    return {'label': label, 'ops': [
        {'op': 'remove', 'tag': 'spoiler'},
        {'op': 'add', 'part': {'type': 'wing', 'tag': 'spoiler', 's0': s0, 's1': s1, 'y': y,
                               'span': span or round(D['W'] * 0.86, 2), 'uprights': [round(D['W'] * 0.22, 2)], 'kick': 0.04}}]}


def no_spoiler(label='No spoiler'):
    return {'label': label, 'ops': [{'op': 'remove', 'tag': 'spoiler'}]}


# ---------------------------------------------------------------- wheels
def wheels(style, label, rim_ratio=None, mat=None, add_r=0.0):
    ops = [{'op': 'set', 'path': 'wheel.rim', 'value': style}]
    if rim_ratio:
        ops.append({'op': 'set', 'path': 'wheel.rim_ratio', 'value': rim_ratio})
    ops.append({'op': 'set', 'path': 'wheel.rim_mat', 'value': mat or 'rim'})
    return {'label': label, 'ops': ops}


# ---------------------------------------------------------------- exhaust
def exhaust(D, kind, r=0.045):
    """Tip layouts. Positions are written into fleet.json for B4's flames."""
    hw = D['W'] / 2
    y = round(_floor(D, D['L'] - 0.1) + 0.10, 3)
    if kind == 'dual':
        tips = [{'x': round(hw * 0.62, 3), 'y': y, 'r': r}, {'x': -round(hw * 0.62, 3), 'y': y, 'r': r}]
        label = 'Dual (split)'
    elif kind == 'dual_left':
        tips = [{'x': -round(hw * 0.50, 3), 'y': y, 'r': r}, {'x': -round(hw * 0.50 - 2.3 * r, 3), 'y': y, 'r': r}]
        label = 'Dual (one side)'
    elif kind == 'quad':
        tips = [{'x': sx * round(hw * f, 3), 'y': y, 'r': r * 0.9} for sx in (1, -1) for f in (0.56, 0.72)]
        label = 'Quad'
    elif kind == 'center':
        tips = [{'x': 0.0, 'y': y + 0.02, 'r': r * 1.45}]
        label = 'Centre single (big bore)'
    elif kind == 'single':
        tips = [{'x': -round(hw * 0.58, 3), 'y': y, 'r': r * 1.2}]
        label = 'Single (big bore)'
    elif kind == 'side':
        s = D['OHf'] + D['WB'] - _arch_r(D) - 0.16
        ys = round(_floor(D, s) + 0.07, 3)
        tips = [{'dir': 'side', 'side': 'right', 's': round(s, 3), 'y': ys, 'r': r},
                {'dir': 'side', 'side': 'left', 's': round(s, 3), 'y': ys, 'r': r}]
        label = 'Side exit'
    elif kind == 'oval':
        tips = [{'x': sx * round(hw * 0.62, 3), 'y': y, 'r': r * 1.5, 'squash': 0.6} for sx in (1, -1)]
        label = 'Oval twins'
    else:
        raise ValueError(kind)
    return {'label': label, 'ops': [{'op': 'exhaust', 'tips': tips}]}


# ---------------------------------------------------------------- stance
def stance(drop, label):
    return {'label': label, 'ops': [{'op': 'drop', 'value': drop}]}
