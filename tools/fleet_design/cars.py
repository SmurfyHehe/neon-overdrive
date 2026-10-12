"""The 12 fleet designs (stage B1). Original designs; the reference cars are
only where the proportions come from.

Units are metres. s runs from the front tip (0) to the rear tip (L). Curves
are (s, value) keys, piecewise linear:
  top    centreline top line (nose, hood, windshield, roof, backlight, deck)
  floor  underbody line          hw     half width at the widest point
  waist  height of widest point   belt   beltline (window sill / hood edge)
cabin: A windshield base, W windshield top, R roof end, C backlight base,
D end of the side glass, pillars = (s0, s1) bands, roof_w = half width.
Decals are drawn on a view's plane and projected onto the body:
  front/rear: (x, y)   left: (s, y), mirrored to the right   top: (x, s)
"""

MIRRORS = {'type': 'mirrors'}

# ----------------------------------------------------------------------------
# PLAYER FLEET: low, wide, wheels fill the arches; one hero shape cue each
# ----------------------------------------------------------------------------
P1 = {
    'id': 'p1_coupe', 'role': 'player', 'label': 'Sports coupe',
    'tree': 'p1_coupe',
    'tree_parts': {'grip': ['spoiler.gt', 'front_bumper.lip'], 'slide': ['spoiler.ducktail'], 'lamps_fixed': ['lamps.fixed']},
    'refs': 'Supra A80, Silvia S13, RX-7 FD3S',
    'rule': 'Long hood, cabin pushed back, fastback roof, hoop wing; pop-up lamps stand up at night.',
    'L': 4.42, 'WB': 2.52, 'OHf': 0.98, 'W': 1.80,
    'wheel': {'r': 0.32, 'w': 0.245, 'w_rear': 0.265, 'track': 1.53, 'arch_gap': 0.025, 'rim': '5spoke', 'rim_ratio': 0.70},
    'top': [(0.0, 0.44), (0.05, 0.55), (0.30, 0.64), (1.00, 0.74), (1.55, 0.80), (2.20, 1.22), (2.95, 1.24),
            (3.30, 1.17), (3.85, 0.97), (4.22, 0.94), (4.34, 0.92), (4.40, 0.84), (4.42, 0.72)],
    'floor': [(0, 0.30), (0.25, 0.13), (4.05, 0.14), (4.28, 0.20), (4.42, 0.36)],
    'hw': [(0, 0.60), (0.10, 0.78), (0.40, 0.88), (0.98, 0.90), (2.20, 0.885), (3.50, 0.90), (4.10, 0.875), (4.30, 0.83), (4.42, 0.74)],
    'waist': [(0, 0.38), (0.45, 0.54), (3.6, 0.58), (4.42, 0.55)],
    'belt': [(0.0, 0.44), (0.40, 0.61), (1.55, 0.77), (2.70, 0.82), (3.85, 0.89), (4.42, 0.82)],
    'tumble': 0.07, 'sill_in': 0.035, 'rocker_h': 0.30,
    'cabin': {'A': 1.55, 'W': 2.20, 'R': 2.95, 'C': 3.85, 'D': 3.35,
              'roof_w': [(2.20, 0.60), (2.95, 0.57), (3.85, 0.66)], 'roof_drop': 0.035, 'pillars': [(2.66, 2.72)]},
    'decals': [
        {'view': 'front', 'rect': (-0.48, 0.21, 0.48, 0.33), 'mat': 'grille', 'tag': 'fbumper'},
        {'view': 'front', 'rect': (0.50, 0.33, 0.74, 0.39), 'mat': 'turn', 'mirror': True},
        {'view': 'rear', 'rect': (-0.78, 0.58, 0.78, 0.74), 'mat': 'trim', 'cell': 0.2},
        {'view': 'rear', 'circle': (0.63, 0.66, 0.06, 12), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'circle': (0.47, 0.66, 0.06, 12), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.66, 0.22, 0.66, 0.31), 'mat': 'trim', 'tag': 'rbumper'},
    ],
    'parts': [
        MIRRORS,
        {'type': 'hoop', 'tag': 'spoiler', 's0': 4.02, 's1': 4.28, 'span': 1.52, 'y_end': 1.03, 'y_mid': 1.13, 'thick': 0.035},
        {'type': 'popups', 's0': 0.26, 's1': 0.50, 'x0': 0.36, 'x1': 0.70, 'h': 0.12},
    ],
    'exhaust': [{'x': 0.55, 'y': 0.25, 'r': 0.045}, {'x': -0.55, 'y': 0.25, 'r': 0.045}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.70, 0.40, 2.55, 0.64), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.55, 0.30, 1.25)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.42, 0.38, 0.42, 0.54), 'note': 'tail panel'},
    ],
    'paint': {'hero': ('Sodium', '#FF8A1F'), 'alts': [('Silver', '#C9CED6'), ('Midnight', '#1B2A4A'), ('Signal red', '#B3191E'), ('Pearl', '#E9E6DF')],
              'trim': '#1A1D24', 'rim': '#C9CED6'},
    'options': {},
}

def _fender(s_ax, lo=0.40, hi=0.78, half=0.50, r=0.365, yc=0.30):
    """The pontoon fender over one arch as a side-view polygon (s, y): the
    panel from the rocker to the belt, cut out around the wheel arch."""
    import math
    pts = [(s_ax - half, lo), (s_ax - half, hi), (s_ax + half, hi), (s_ax + half, lo)]
    for k in range(9):
        a = math.pi * k / 8
        pts.append((s_ax + r * math.cos(a), yc + r * math.sin(a)))
    return pts


P0_AXLES = (0.85, 3.40)
P0 = {
    'id': 'p0_beater', 'role': 'player', 'label': 'Rear-engine beater',
    'refs': 'the rear-engine, air-cooled economy cars of the 1960s (category only; no brand)',
    'rule': 'One dome from nose to tail, pontoon fenders bulging at each wheel, round lamps up on the front fenders, louvred engine lid at the back; wheels fill the arches, bare steel rims.',
    'tier': 'T0 beater: the prologue car, 2026-10-09; rebuilt from the decided sheet 2026-10-10 '
            '(stretched, primer fenders with rust and bondo, four bits missing, air-cooled vents)',
    # Stretched from 4.05 x 1.58 (the cabin audit: belt 0.15-0.25 m too narrow
    # for adult shoulders, 1.1 m glass to glass, rear roof 0.73 m over the floor).
    'L': 4.30, 'WB': 2.55, 'OHf': 0.85, 'W': 1.72,
    # Wheels fill the arches (arch_gap like the other player cars), wider
    # tyres, bare steel rims: the hubcaps are the first of the missing bits.
    'wheel': {'r': 0.30, 'w': 0.175, 'w_rear': 0.185, 'track': 1.44, 'arch_gap': 0.025, 'rim': 'steel_bare', 'rim_ratio': 0.56},
    'top': [(0.0, 0.60), (0.05, 0.74), (0.32, 0.86), (0.90, 0.99), (1.40, 1.07), (1.74, 1.56), (2.00, 1.61), (2.35, 1.61),
            (2.62, 1.57), (2.95, 1.44), (3.32, 1.23), (3.65, 1.04), (3.95, 0.88), (4.15, 0.76), (4.27, 0.66), (4.30, 0.56)],
    'floor': [(0, 0.30), (0.24, 0.17), (4.08, 0.17), (4.30, 0.30)],
    'hw': [(0, 0.42), (0.10, 0.58), (0.42, 0.76), (0.85, 0.86), (1.32, 0.80), (1.65, 0.76), (2.60, 0.76), (2.98, 0.80),
           (3.40, 0.86), (3.82, 0.80), (4.17, 0.64), (4.30, 0.48)],
    'waist': [(0, 0.46), (0.85, 0.56), (1.70, 0.60), (2.55, 0.60), (3.40, 0.56), (4.30, 0.48)],
    'belt': [(0, 0.60), (0.37, 0.80), (1.40, 0.96), (2.35, 0.97), (3.20, 0.95), (3.82, 0.86), (4.30, 0.70)],
    'tumble': 0.08, 'sill_in': 0.03, 'rocker_h': 0.36, 'rocker_trim': True,
    'cabin': {'A': 1.40, 'W': 1.74, 'R': 2.62, 'C': 3.32, 'D': 3.05,
              'roof_w': [(1.74, 0.64), (2.62, 0.62), (3.32, 0.50)], 'roof_drop': 0.02, 'pillars': [(2.15, 2.22)]},
    'decals': [
        # Decal order matters: each decal sits 1.5 mm further off the skin than
        # the one before, so the nose and tail (the length the tests measure)
        # come first and the side panels last; nose and tail decals also pin their
        # own offset, so the car measures its sheet length.
        # engine lid: six louvre slots, licence recess, blade bumper, one tailpipe.
        # One tail lamp (left) works; the right lens is gone (missing bit 4):
        # a dark socket with a rust ring.
        {'view': 'rear', 'rect': (-0.28, 0.90, 0.28, 0.925), 'mat': 'grille', 'offset': 0.004},
        {'view': 'rear', 'rect': (-0.28, 0.85, 0.28, 0.875), 'mat': 'grille', 'offset': 0.004},
        {'view': 'rear', 'rect': (-0.28, 0.80, 0.28, 0.825), 'mat': 'grille', 'offset': 0.004},
        {'view': 'rear', 'rect': (-0.28, 0.75, 0.28, 0.775), 'mat': 'grille', 'offset': 0.004},
        {'view': 'rear', 'rect': (-0.28, 0.70, 0.28, 0.725), 'mat': 'grille', 'offset': 0.004},
        {'view': 'rear', 'rect': (-0.28, 0.65, 0.28, 0.675), 'mat': 'grille', 'offset': 0.004},
        {'view': 'rear', 'ellipse': (-0.56, 0.80, 0.065, 0.085, 12), 'mat': 'tail', 'offset': 0.004},
        {'view': 'rear', 'ellipse': (0.56, 0.80, 0.075, 0.095, 12), 'mat': 'rust', 'offset': 0.004},
        {'view': 'rear', 'ellipse': (0.56, 0.80, 0.055, 0.075, 12), 'mat': 'exh_hole', 'offset': 0.006},
        {'view': 'rear', 'rect': (-0.16, 0.46, 0.16, 0.56), 'mat': 'trim', 'offset': 0.004},
        {'view': 'rear', 'rect': (-0.66, 0.30, 0.66, 0.36), 'mat': 'chrome', 'tag': 'rbumper', 'offset': 0.004},
        # round lamps standing on the fender crowns, a thin chrome blade on the nose.
        # No front bumper (missing bit 2): two rusty brackets are left, see parts.
        {'view': 'front', 'circle': (0.54, 0.84, 0.095, 14), 'mat': 'head', 'mirror': True, 'offset': 0.004},
        {'view': 'front', 'rect': (-0.16, 0.62, 0.16, 0.66), 'mat': 'trim', 'offset': 0.004},
        # the primer front lid: one panel that never got painted (paint2)
        {'view': 'top', 'rect': (-0.36, 0.32, 0.36, 1.22), 'mat': 'paint2', 'tag': 'hood'},
        # primer, rust and bondo on the pontoon fenders (Roy, 2026-10-09: "primer
        # grey with rust and unfinished bondo work like body work"): a primer
        # panel cut round the arch, rust blooms on the arch lips, bondo patches
        # sanded flat. One fender in primer, the rear left (with the primer front
        # lid that is two primer panels): the sheet body is also the AI car,
        # which must stay within the 4,000-triangle traffic budget
        # (tests/traffic/npc_cars.gd), and each primer fender costs 208
        # triangles at this cell size. All four had primer up to 2026-10-12
        # (4,572 triangles); every rust bloom and bondo patch stays.
        {'view': 'left', 'poly': _fender(P0_AXLES[1]), 'mat': 'primer', 'cell': 0.16, 'tag': 'fender'},
        {'view': 'left', 'ellipse': (0.57, 0.46, 0.10, 0.045, 10), 'mat': 'rust', 'mirror': True, 'cell': 0.12},
        {'view': 'left', 'ellipse': (1.14, 0.50, 0.09, 0.05, 10), 'mat': 'rust', 'mirror': True, 'cell': 0.12},
        {'view': 'left', 'ellipse': (3.12, 0.47, 0.11, 0.05, 10), 'mat': 'rust', 'mirror': True, 'cell': 0.12},
        {'view': 'left', 'ellipse': (3.72, 0.52, 0.08, 0.05, 10), 'mat': 'rust', 'mirror': True, 'cell': 0.12},
        {'view': 'left', 'poly': [(0.46, 0.58), (0.72, 0.56), (0.76, 0.72), (0.50, 0.74)], 'mat': 'bondo', 'mirror': True, 'cell': 0.12},
        {'view': 'left', 'poly': [(3.44, 0.60), (3.78, 0.58), (3.82, 0.74), (3.50, 0.76)], 'mat': 'bondo', 'mirror': True, 'cell': 0.12},
        # air-cooled: intake slots in the rear quarters feed the engine bay
        {'view': 'left', 'rect': (3.12, 0.74, 3.15, 0.88), 'mat': 'grille', 'mirror': True},
        {'view': 'left', 'rect': (3.19, 0.74, 3.22, 0.88), 'mat': 'grille', 'mirror': True},
        {'view': 'left', 'rect': (3.26, 0.74, 3.29, 0.88), 'mat': 'grille', 'mirror': True},
    ],
    'parts': [
        # driver's mirror only: the passenger one is gone (missing bit 3), a rust stub stays
        {'type': 'mirrors', 's': 1.46, 'sides': [-1], 'stub_mat': 'rust'},
        # front bumper brackets, bumper gone (missing bit 2)
        {'type': 'box', 's': 0.06, 'xy': (0.42, 0.33), 'size': (0.05, 0.08, 0.10), 'mat': 'rust'},
        {'type': 'box', 's': 0.06, 'xy': (-0.42, 0.33), 'size': (0.05, 0.08, 0.10), 'mat': 'rust'},
    ],
    'exhaust': [{'x': 0.32, 'y': 0.24, 'r': 0.03, 'out': 0.01}],   # a stub of pipe, not a tip
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.50, 0.50, 2.12, 0.74), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.26, 0.44, 0.26, 1.08)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.26, 0.52, 0.26, 0.63), 'note': 'engine lid'},
    ],
    'paint': {'hero': ('Faded sage', '#8C9B88'), 'alts': [('Primer grey', '#6E6B68'), ('Dust beige', '#B9AE98'), ('Faded red', '#8E2A28'), ('Oxide brown', '#6B4A33')],
              'trim': '#2A2C30', 'rim': '#8D939C',
              'extra': {'paint2': '#5F5B58', 'chrome': '#9FA4AA', 'primer': '#5F5B58', 'rust': '#6B4A33', 'bondo': '#B9AE98'}},
    'options': {},
}

P2 = {
    'id': 'p2_hothatch', 'role': 'player', 'label': 'Hot hatch',
    'refs': 'Civic Si/EK, Golf GTI Mk2, 205 GTI',
    'rule': 'Short brick on wheels pushed to the corners: narrow upright cabin on wide bolted-on box blisters, '
            'near-vertical hatch under an overhanging roof spoiler.',
    'tier': 'T1 hot hatch (Juno), sheet p2_hothatch (Roy 291-294), rebuilt from parts 2026-10-11. The nose is 8 cm '
            'shorter than the B1 sheet (front overhang 0.82 to 0.74, shape research 2026-10-11): every s below is the '
            'old one minus 0.08, so nothing behind the front bumper moved in car space. The body is 0.85 wide all '
            'along (no waist pinch); the four box blisters carry it out to 0.915. Belt straight at 0.90 (the hard 80s '
            'shoulder), roof 10 cm longer so the hatch glass stands at 71 degrees.',
    'L': 3.97, 'WB': 2.56, 'OHf': 0.74, 'W': 1.83,
    'wheel': {'r': 0.315, 'w': 0.225, 'track': 1.58, 'arch_gap': 0.02, 'rim': '6spoke', 'rim_ratio': 0.68},
    'top': [(0.0, 0.60), (0.05, 0.69), (0.20, 0.78), (1.12, 0.92), (1.76, 1.31), (3.62, 1.33), (3.64, 1.31),
            (3.76, 0.95), (3.88, 0.93), (3.97, 0.62)],
    'floor': [(0, 0.27), (0.20, 0.12), (3.67, 0.12), (3.97, 0.28)],
    'hw': [(0, 0.70), (0.07, 0.82), (0.26, 0.85), (3.82, 0.85), (3.97, 0.82)],
    'waist': [(0, 0.48), (0.32, 0.58), (3.72, 0.60), (3.97, 0.58)],
    'belt': [(0, 0.58), (0.20, 0.76), (1.12, 0.90), (3.76, 0.90), (3.97, 0.88)],
    'tumble': 0.06, 'sill_in': 0.03, 'rocker_h': 0.28, 'rocker_trim': True,
    'cabin': {'A': 1.12, 'W': 1.76, 'R': 3.62, 'C': 3.76, 'D': 3.28,
              'roof_w': [(1.78, 0.58), (3.60, 0.57)], 'roof_drop': 0.03, 'pillars': [(2.52, 2.60)]},
    'decals': [
        # nose and tail decals pin their own offset (as on the Bug), so the car measures its sheet length
        # slim_bar front: two slim lenses with an amber corner, a black slot between them,
        # the lower mouth in the bumper with two round fogs (Roy 293)
        {'view': 'front', 'rect': (-0.40, 0.52, 0.40, 0.59), 'mat': 'grille', 'offset': 0.004},
        {'view': 'front', 'rect': (0.42, 0.50, 0.64, 0.59), 'mat': 'head', 'mirror': True, 'offset': 0.006},
        {'view': 'front', 'rect': (0.64, 0.50, 0.70, 0.59), 'mat': 'turn', 'mirror': True, 'offset': 0.006},
        {'view': 'front', 'rect': (-0.50, 0.28, 0.50, 0.38), 'mat': 'grille', 'tag': 'fbumper', 'offset': 0.004},
        {'view': 'front', 'circle': (0.60, 0.33, 0.04, 10), 'mat': 'head', 'mirror': True, 'tag': 'fog', 'offset': 0.006},
        {'view': 'front', 'rect': (-0.66, 0.385, 0.66, 0.415), 'mat': 'trim', 'tag': 'fstrip', 'cell': 0.4, 'offset': 0.004},
        # tall_blocks rear: three cells a side (tail, brake, reverse) and an amber edge
        {'view': 'rear', 'rect': (0.56, 0.785, 0.685, 0.89), 'mat': 'tail', 'mirror': True, 'tag': 'tail', 'offset': 0.006},
        {'view': 'rear', 'rect': (0.56, 0.67, 0.685, 0.775), 'mat': 'tail_off', 'mirror': True, 'tag': 'brake', 'offset': 0.006},
        {'view': 'rear', 'rect': (0.56, 0.56, 0.685, 0.66), 'mat': 'head_off', 'mirror': True, 'tag': 'reverse', 'offset': 0.006},
        {'view': 'rear', 'rect': (0.69, 0.56, 0.72, 0.89), 'mat': 'turn', 'mirror': True, 'tag': 'turn_r', 'offset': 0.006},
        {'view': 'rear', 'rect': (-0.27, 0.635, 0.27, 0.745), 'mat': 'trim', 'tag': 'plate_recess', 'offset': 0.004},
        {'view': 'rear', 'rect': (-0.65, 0.22, 0.65, 0.32), 'mat': 'trim', 'tag': 'rbumper', 'offset': 0.004},
        # the 40 mm black rub strip at y 0.60, between the blisters
        {'view': 'left', 'rect': (1.165, 0.58, 2.875, 0.62), 'mat': 'trim', 'mirror': True, 'cell': 0.5, 'tag': 'rub'},
    ],
    'parts': [
        MIRRORS,
        # four riveted box blisters, 6.5 cm proud of the doors (Roy 291)
        {'type': 'flares', 'tag': 'flares', 'band': 0.10, 'proud': 0.065, 'lip_mat': 'trim', 'rivets': True},
        # the roof spoiler overhangs the hatch by 0.20 m and stands above the roof line; the third brake lamp is under its edge
        {'type': 'roof_spoiler', 'tag': 'spoiler', 's0': 3.42, 's1': 3.84, 'y0': 1.30, 'y1': 1.335, 'span': 1.22, 'thick': 0.05, 'brake_light': True},
    ],
    'exhaust': [{'x': -0.42, 'y': 0.24, 'r': 0.04}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.47, 0.63, 2.37, 0.87), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.27, 0.30, 0.97)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.50, 0.76, 0.50, 0.88), 'note': 'tailgate panel'},
    ],
    'paint': {'hero': ('Rally red', '#C41E24'), 'alts': [('Pearl', '#E9E6DF'), ('Gunmetal', '#4A505B'), ('Sodium', '#FF8A1F'), ('Black', '#15171C')],
              'trim': '#1A1D24', 'rim': '#C9CED6'},
    'options': {},
}

P3 = {
    'id': 'p3_tuner', 'role': 'player', 'label': 'Tuner sedan',
    'refs': 'Skyline R32-R34, AE86, Lancer Evo',
    'rule': 'Square-cut four-door with boxed overfenders and a tall pedestal wing; four round tail lamps.',
    'L': 4.48, 'WB': 2.62, 'OHf': 0.95, 'W': 1.78,
    'wheel': {'r': 0.32, 'w': 0.245, 'track': 1.52, 'arch_gap': 0.028, 'rim': '10spoke', 'rim_ratio': 0.70, 'rim_mat': 'rim_bronze'},
    'top': [(0.0, 0.56), (0.04, 0.66), (0.18, 0.74), (1.45, 0.86), (2.02, 1.33), (3.00, 1.36), (3.55, 1.02),
            (4.34, 1.00), (4.45, 0.97), (4.48, 0.72)],
    'floor': [(0, 0.27), (0.20, 0.12), (4.20, 0.12), (4.48, 0.29)],
    'hw': [(0, 0.70), (0.08, 0.84), (0.40, 0.86), (0.55, 0.89), (1.36, 0.89), (1.46, 0.86), (3.07, 0.86), (3.17, 0.89),
           (3.98, 0.89), (4.10, 0.86), (4.38, 0.85), (4.48, 0.80)],
    'waist': [(0, 0.48), (0.40, 0.60), (4.48, 0.62)],
    'belt': [(0, 0.56), (0.25, 0.74), (1.45, 0.84), (3.55, 0.91), (4.48, 0.88)],
    'tumble': 0.035, 'sill_in': 0.03, 'rocker_h': 0.28,
    'cabin': {'A': 1.45, 'W': 2.02, 'R': 3.00, 'C': 3.55, 'D': 3.38,
              'roof_w': [(2.02, 0.61), (3.00, 0.59), (3.55, 0.66)], 'roof_drop': 0.03, 'pillars': [(2.50, 2.58)]},
    'decals': [
        {'view': 'front', 'rect': (0.46, 0.56, 0.80, 0.68), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.42, 0.56, 0.42, 0.66), 'mat': 'grille'},
        {'view': 'front', 'rect': (-0.56, 0.24, 0.56, 0.42), 'mat': 'grille', 'tag': 'fbumper'},
        {'view': 'rear', 'circle': (0.66, 0.84, 0.072, 12), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'circle': (0.46, 0.84, 0.072, 12), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.25, 0.48, 0.25, 0.62), 'mat': 'trim'},
        {'view': 'rear', 'rect': (-0.70, 0.22, 0.70, 0.33), 'mat': 'trim', 'tag': 'rbumper'},
    ],
    'parts': [
        MIRRORS,
        {'type': 'wing', 'tag': 'spoiler', 's0': 4.12, 's1': 4.42, 'y': 1.18, 'span': 1.42, 'uprights': [0.42], 'kick': 0.03},
    ],
    'exhaust': [{'x': -0.50, 'y': 0.25, 'r': 0.05}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.55, 0.42, 3.05, 0.62), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.30, 0.30, 1.10)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.36, 0.78, 0.36, 0.92), 'note': 'tail panel'},
    ],
    'paint': {'hero': ('Pearl white', '#E9E6DF'), 'alts': [('Gunmetal', '#4A505B'), ('Silver', '#C9CED6'), ('Sodium', '#FF8A1F'), ('Black', '#15171C')],
              'trim': '#1A1D24', 'rim': '#9C6B3A'},
    'options': {},
}

P4 = {
    'id': 'p4_kei', 'role': 'player', 'label': 'Kei roadster',
    'refs': 'Honda Beat, Suzuki Cappuccino, Autozam AZ-1',
    'rule': 'Tiny open two-seater with the wheels at the very corners, a low screen and two headrest humps '
            'that run back into the engine lid.',
    'tier': 'T1 kei roadster (Pilar), sheet p4_kei (Roy 317-320), rebuilt from parts 2026-10-11: the screen top is down '
            'from 1.13 to 1.05, two smooth humps instead of the hoops, kei-sized pop-ups, a real side intake, thinner '
            'sidewalls (rim ratio 0.70) and arch lips. The cockpit opening ends at 2.18 (was 2.32), just behind the '
            "cabin's rear bulkhead, so the humps stand on the deck.",
    'L': 3.30, 'WB': 2.27, 'OHf': 0.55, 'W': 1.40,
    'wheel': {'r': 0.28, 'w': 0.165, 'w_rear': 0.175, 'track': 1.23, 'arch_gap': 0.025, 'rim': '5spoke', 'rim_ratio': 0.70},
    'top': [(0.0, 0.48), (0.05, 0.57), (0.22, 0.63), (0.92, 0.74), (1.30, 1.04), (1.36, 1.05), (1.42, 0.80),
            (2.32, 0.80), (3.05, 0.82), (3.22, 0.79), (3.30, 0.62)],
    'floor': [(0, 0.24), (0.16, 0.12), (3.10, 0.12), (3.30, 0.28)],
    # pinched 1 cm at the doors: 0.69 there, 0.70 over the arches
    'hw': [(0, 0.52), (0.08, 0.63), (0.30, 0.70), (0.86, 0.70), (0.96, 0.69), (2.40, 0.69), (2.50, 0.70), (3.00, 0.70),
           (3.20, 0.66), (3.30, 0.60)],
    'waist': [(0, 0.36), (0.30, 0.46), (3.30, 0.48)],
    'belt': [(0, 0.46), (0.30, 0.60), (0.92, 0.71), (2.32, 0.77), (3.30, 0.74)],
    'tumble': 0.05, 'sill_in': 0.03, 'rocker_h': 0.26,
    'cabin': {'A': 0.92, 'W': 1.30, 'R': 1.36, 'C': 1.42, 'D': 1.40,
              'roof_w': 0.54, 'roof_drop': 0.02, 'pillars': [], 'roof_h': 1.05},
    'open': [{'s0': 1.42, 's1': 2.18, 'floor': 0.40, 'wall': 0.06, 'mat': 'interior'}],
    'decals': [
        # nose and tail decals pin their own offset, so the car measures its sheet length
        # a single slot grille in the bumper with an amber turn lamp at each end (the lamps are pop-ups: parts)
        {'view': 'front', 'rect': (-0.25, 0.28, 0.25, 0.36), 'mat': 'grille', 'tag': 'fbumper', 'offset': 0.004},
        {'view': 'front', 'rect': (0.26, 0.29, 0.33, 0.35), 'mat': 'turn', 'mirror': True, 'offset': 0.006},
        # round_twin rear: two ovals, a small amber lamp under each, one reversing lamp in the bumper centre (era)
        {'view': 'rear', 'ellipse': (0.48, 0.66, 0.09, 0.05, 12), 'mat': 'tail', 'mirror': True, 'offset': 0.006},
        {'view': 'rear', 'rect': (0.42, 0.54, 0.54, 0.585), 'mat': 'turn', 'mirror': True, 'tag': 'turn_r', 'offset': 0.006},
        {'view': 'rear', 'circle': (0.0, 0.40, 0.03, 10), 'mat': 'head_off', 'tag': 'reverse', 'offset': 0.006},
        {'view': 'rear', 'rect': (-0.27, 0.605, 0.27, 0.715), 'mat': 'trim', 'tag': 'plate_recess', 'offset': 0.004},
        {'view': 'rear', 'rect': (-0.50, 0.29, 0.50, 0.35), 'mat': 'trim', 'tag': 'rbumper', 'offset': 0.004},
        # the side intake behind each door (Roy 319: a real scooped-in intake; the parts build cuts it in)
        {'view': 'left', 'rect': (2.20, 0.49, 2.44, 0.63), 'mat': 'grille', 'mirror': True, 'tag': 'intake'},
    ],
    'parts': [
        {'type': 'mirrors', 's': 1.10},
        # two smooth headrest fairings (Roy 317), no hoop: 0.26 wide, up to 1.00, tapering back into the engine lid
        {'type': 'rollhoops', 's': 2.00, 'h': 1.00, 'x': 0.30, 'w': 0.26, 's0': 1.95, 's1': 2.40},
        # kei-sized pop-ups (Roy 320); the sheet draws them up
        {'type': 'popups', 's0': 0.30, 's1': 0.56, 'x0': 0.31, 'x1': 0.57, 'h': 0.08},
        # arch lips, so the wheels read as fitted
        {'type': 'flares', 'tag': 'lips', 'band': 0.035, 'proud': 0.01},
    ],
    'exhaust': [{'x': 0.0, 'y': 0.24, 'r': 0.035}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.30, 0.40, 2.05, 0.60), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.25, 0.15, 0.25, 0.80)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.34, 0.45, 0.34, 0.59), 'note': 'tail panel'},
    ],
    'paint': {'hero': ('Signal yellow', '#F2B53A'), 'alts': [('Signal red', '#B3191E'), ('Cream', '#E8DCC0'), ('Racing green', '#1F4D3A'), ('Silver', '#C9CED6')],
              'trim': '#1A1D24', 'rim': '#C9CED6'},
    'options': {},
}

P5 = {
    'id': 'p5_muscle', 'role': 'player', 'label': 'Muscle hardtop',
    'refs': 'Chevelle SS (1970), Charger R/T (1968), Torino GT (1970)',
    'rule': 'Two-door 68-72 muscle hardtop: long hood, short deck, coke-bottle hips, tunnel-back roof with buttresses, full-width tail bar.',
    # Rebuilt 2026-10-11 (Roy 191-192, 1218): 5.00 x 1.93 x 1.33, wheelbase 2.84, overhangs 0.90 / 1.26.
    # The physics has one wheel radius and one track per car, so the 0.72 m rear wheel and the wider
    # rear track of the decision are not here: 0.70 m all round, the fat rear tyre flush with its arch.
    'L': 5.00, 'WB': 2.84, 'OHf': 0.90, 'W': 1.93,
    'wheel': {'r': 0.35, 'w': 0.255, 'w_rear': 0.32, 'track': 1.60, 'arch_gap': 0.02, 'rim': 'dish', 'rim_ratio': 0.68},
    # long flat roof (2.12 to 3.30), fast backlight, a deck that stays high to a square tail
    'top': [(0.0, 0.79), (0.05, 0.84), (0.30, 0.862), (1.45, 0.90), (2.12, 1.305), (2.50, 1.33), (3.00, 1.33), (3.30, 1.31),
            (3.80, 0.965), (4.90, 0.935), (4.97, 0.925), (5.00, 0.90)],
    'floor': [(0, 0.30), (0.25, 0.16), (4.70, 0.16), (4.88, 0.22), (5.00, 0.37)],
    # coke bottle: 0.965 over both arches, 0.90 at the doors (7% a side)
    'hw': [(0, 0.87), (0.08, 0.93), (0.40, 0.955), (0.90, 0.965), (1.25, 0.965), (1.90, 0.90), (2.90, 0.90),
           (3.45, 0.965), (4.10, 0.965), (4.60, 0.95), (4.90, 0.925), (5.00, 0.90)],
    # the shoulder crease: the widest point of the section, 0.78 up, nose to tail
    'waist': [(0, 0.70), (0.30, 0.78), (5.00, 0.78)],
    'belt': [(0, 0.76), (0.30, 0.84), (1.45, 0.86), (3.80, 0.87), (5.00, 0.87)],
    'tumble': [(0, 0.07), (4.60, 0.07), (5.00, 0.03)], 'sill_in': 0.04, 'rocker_h': 0.36,
    # hardtop: no B-pillar, the side glass runs from the A-pillar to the sail panel
    'cabin': {'A': 1.45, 'W': 2.12, 'R': 3.30, 'C': 3.80, 'D': 3.42,
              'roof_w': [(2.12, 0.64), (3.30, 0.62), (3.80, 0.70)], 'roof_drop': 0.035, 'pillars': []},
    'decals': [
        {'view': 'front', 'rect': (-0.80, 0.50, 0.80, 0.66), 'mat': 'grille'},
        {'view': 'front', 'circle': (0.66, 0.58, 0.075, 12), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.84, 0.36, 0.84, 0.44), 'mat': 'chrome', 'tag': 'fbumper', 'cell': 0.3},
        {'view': 'front', 'rect': (0.50, 0.375, 0.66, 0.425), 'mat': 'turn', 'mirror': True},
        {'view': 'rear', 'rect': (-0.85, 0.73, 0.85, 0.83), 'mat': 'tail', 'cell': 0.3},
        {'view': 'rear', 'rect': (-0.84, 0.39, 0.84, 0.55), 'mat': 'chrome', 'tag': 'rbumper', 'cell': 0.3},
    ],
    'parts': [
        MIRRORS,
    ],
    'exhaust': [{'x': 0.66, 'y': 0.26, 'r': 0.05}, {'x': -0.66, 'y': 0.26, 'r': 0.05}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.62, 0.42, 2.62, 0.66), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.32, 0.40, 0.32, 1.30)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.55, 0.58, 0.55, 0.71), 'note': 'tail panel'},
    ],
    'paint': {'hero': ('Cherry', '#6A1620'), 'alts': [('Hugger orange', '#D9541E'), ('Fathom green', '#1F4D3A'), ('Black', '#15171C'), ('Silver', '#C9CED6')],
              'trim': '#1A1D24', 'rim': '#C9CED6'},
    # T3: clean, polished, chrome bright (Roy 1212). Read by the paint work when wear lands.
    'condition': 0.1,
    'options': {},
}

P6 = {
    'id': 'p6_crossover', 'role': 'player', 'label': 'Performance crossover',
    'refs': 'Crosstrek/XV, A6 Allroad, Delta Integrale',
    'rule': 'Lifted rally hatch: black-clad box flares, roof rack, high ground clearance.',
    'L': 4.35, 'WB': 2.62, 'OHf': 0.92, 'W': 1.84,
    'wheel': {'r': 0.345, 'w': 0.235, 'track': 1.56, 'arch_gap': 0.045, 'rim': '5spoke', 'rim_ratio': 0.64},
    'top': [(0.0, 0.72), (0.06, 0.84), (0.28, 0.94), (1.25, 1.06), (1.92, 1.50), (3.82, 1.53), (4.18, 1.16),
            (4.30, 1.12), (4.35, 0.78)],
    'floor': [(0, 0.42), (0.32, 0.22), (4.02, 0.22), (4.35, 0.44)],
    'hw': [(0, 0.70), (0.12, 0.85), (0.40, 0.885), (0.50, 0.915), (1.36, 0.915), (1.46, 0.885), (3.08, 0.885),
           (3.18, 0.915), (3.94, 0.915), (4.04, 0.89), (4.35, 0.82)],
    'waist': [(0, 0.62), (0.40, 0.72), (4.35, 0.74)],
    'belt': [(0, 0.72), (0.30, 0.90), (1.25, 1.02), (3.90, 1.08), (4.35, 1.02)],
    'tumble': 0.05, 'sill_in': 0.03, 'rocker_h': 0.48, 'rocker_trim': True,
    'cabin': {'A': 1.25, 'W': 1.92, 'R': 3.82, 'C': 4.18, 'D': 3.72,
              'roof_w': [(1.92, 0.66), (3.82, 0.64)], 'roof_drop': 0.03, 'pillars': [(2.68, 2.76)]},
    'decals': [
        {'view': 'front', 'rect': (0.40, 0.80, 0.58, 0.90), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (0.60, 0.80, 0.80, 0.90), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.38, 0.78, 0.38, 0.92), 'mat': 'grille'},
        {'view': 'front', 'rect': (-0.55, 0.50, 0.55, 0.62), 'mat': 'grille', 'tag': 'fbumper'},
        {'view': 'front', 'rect': (-0.45, 0.40, 0.45, 0.48), 'mat': 'chrome'},
        {'view': 'rear', 'rect': (0.60, 0.86, 0.88, 0.96), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (0.80, 0.96, 0.88, 1.10), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.45, 0.44, 0.45, 0.52), 'mat': 'chrome', 'tag': 'rbumper'},
        {'view': 'rear', 'rect': (-0.25, 0.62, 0.25, 0.76), 'mat': 'trim'},
    ],
    'parts': [
        MIRRORS,
        {'type': 'flares', 'mat': 'trim', 'band': 0.085, 'proud': 0.025, 'tag': 'cladding'},
        {'type': 'roof_rails', 's0': 2.05, 's1': 3.75, 'x': 0.60, 'h': 0.09, 'bars': [2.45, 3.40], 'bar_over': 0.14, 'bar_h': 0.035},
        {'type': 'roof_spoiler', 'tag': 'spoiler', 's0': 3.76, 's1': 3.96, 'y0': 1.53, 'y1': 1.49, 'span': 1.26},
    ],
    'exhaust': [{'x': 0.24, 'y': 0.38, 'r': 0.045}, {'x': -0.24, 'y': 0.38, 'r': 0.045}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.55, 0.62, 2.90, 0.85), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.30, 0.30, 1.10)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.54, 0.86, 0.54, 1.06), 'note': 'tailgate panel'},
    ],
    'paint': {'hero': ('Sand', '#B8A27A'), 'alts': [('Silver', '#C9CED6'), ('Rally red', '#C41E24'), ('Black', '#15171C'), ('Racing green', '#1F4D3A')],
              'trim': '#1A1D24', 'rim': '#2A2D33'},
    'options': {},
}

P17 = {
    'id': 'p17_work_pickup', 'role': 'player', 'label': 'Work pickup',
    'refs': 'the mid-size 4-door work pickups of the late 1990s (category only; no brand): a 4.0 V6, rear drive, a long bed',
    'rule': 'Low flat hood under a tall upright double cab, a short open bed behind it on flared box sides, '
            'a chrome step bumper, a side stripe the length of the body, steel wheels in big arches, a single tailpipe out the rear corner.',
    'tier': 'T2 work pickup (Camel), bought from Walt after act 1; spec notes/car-sheets/p17_work_pickup-2026-10-10',
    'L': 4.95, 'WB': 3.18, 'OHf': 0.90, 'W': 1.80,
    # arch gap 5.5 cm: big for a player car, still under every traffic car's
    # (the design check's player/traffic rule: traffic arches are the biggest)
    'wheel': {'r': 0.37, 'w': 0.245, 'track': 1.55, 'arch_gap': 0.055, 'arch_lift': 0.02, 'rim': 'steel', 'rim_ratio': 0.58},
    # lower and rounder-nosed than the traffic pickup (N3): hood 14 cm lower,
    # roof 10 cm lower, bed rail 8 cm lower, 10 cm more wheelbase. Build 4 (Roy
    # 1475 "differ"): the bed is 30 cm shorter (4.95 long, the sheet's stubby
    # "all cab" proportion) and a chrome step bumper stands out behind the
    # tailgate, so the outline test no longer finds N3's twin from the high views
    'top': [(0.0, 0.86), (0.04, 0.96), (0.20, 1.02), (1.30, 1.09), (1.95, 1.70), (3.25, 1.74), (3.32, 1.16),
            (4.92, 1.14), (4.95, 1.08)],
    'floor': [(0, 0.46), (0.30, 0.28), (4.52, 0.28), (4.95, 0.50)],
    # the bed sides flare 4 cm proud of the cab: an old-style flared box
    'hw': [(0, 0.76), (0.08, 0.86), (0.30, 0.90), (3.32, 0.90), (3.55, 0.90), (3.75, 0.94), (4.65, 0.94), (4.82, 0.90), (4.95, 0.88)],
    'waist': [(0, 0.76), (0.40, 0.88), (4.95, 0.88)],
    'belt': [(0, 0.86), (0.20, 0.98), (1.30, 1.06), (3.32, 1.12), (4.95, 1.12)],
    'tumble': 0.035, 'sill_in': 0.03, 'rocker_h': 0.50,
    'cabin': {'A': 1.30, 'W': 1.95, 'R': 3.25, 'C': 3.32, 'D': 3.18,
              'roof_w': [(1.95, 0.70), (3.25, 0.70)], 'roof_drop': 0.03, 'pillars': [(2.52, 2.60)]},
    'open': [{'s0': 3.40, 's1': 4.92, 'floor': 0.84, 'wall': 0.05, 'mat': 'bed'}],
    'decals': [
        # wide low grille between rectangular lamps, a chrome blade bumper under it
        {'view': 'front', 'rect': (-0.50, 0.70, 0.50, 0.90), 'mat': 'grille', 'cell': 0.16},
        {'view': 'front', 'rect': (0.54, 0.74, 0.82, 0.88), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.84, 0.48, 0.84, 0.60), 'mat': 'chrome', 'tag': 'fbumper'},
        # the side stripe: a sodium band with a dark pinline under it, nose to tailgate
        {'view': 'left', 'rect': (0.40, 0.74, 4.75, 0.82), 'mat': 'paint2', 'mirror': True},
        {'view': 'left', 'rect': (0.40, 0.715, 4.75, 0.735), 'mat': 'trim', 'mirror': True},
        # tall tail lamps either side of the tailgate, chrome rear bumper
        {'view': 'rear', 'rect': (0.78, 0.72, 0.90, 1.06), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.84, 0.50, 0.84, 0.62), 'mat': 'chrome', 'cell': 0.25, 'tag': 'rbumper'},
    ],
    'parts': [
        {'type': 'mirrors', 'out': 0.11, 'up': 0.09},
        {'type': 'step', 's0': 1.45, 's1': 3.20, 'y': 0.40},
        {'type': 'box', 's': 5.02, 'xy': (0.0, 0.56), 'size': (1.66, 0.13, 0.16), 'mat': 'chrome', 'tag': 'step_bumper'},
    ],
    # one pipe out the rear corner (right side), no headache rack
    'exhaust': [{'x': 0.68, 'y': 0.40, 'r': 0.04}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.45, 0.86, 3.10, 1.06), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.32, 0.30, 0.32, 1.10)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.45, 0.88, 0.45, 1.08), 'note': 'tailgate'},
    ],
    'paint': {'hero': ('Camel', '#C4A264'), 'alts': [('Work white', '#E9E6DF'), ('Midnight', '#1B2A4A'), ('Forest', '#2B4A3A'), ('Oxide red', '#8E2A28')],
              'trim': '#1A1D24', 'rim': '#A9AEB6', 'extra': {'paint2': '#FF8A1F', 'chrome': '#C9CED6'}},
    'options': {},
}

P10 = {
    'id': 'p10_truck', 'role': 'player', 'label': 'Street truck',
    'refs': 'the lowered regular-cab short-bed sport trucks of 1993-99 (category only; no brand): a pushrod V8, rear drive, '
            'a covered bed, a roll-pan tail',
    'rule': 'A workbench with a V8 bolted on, dropped two inches: a single upright cab, ONE level line from the cab back '
            'to the tailgate top (hard cover flush with the rails), 2 cm arches, a roll-pan tail with tall corner lamps.',
    'tier': 'T2 street truck (Harlan Drover), Diesel Row crew truck, for sale after act 2 (you pay); MC2 brief 2026-10-11',
    'L': 5.05, 'WB': 2.95, 'OHf': 0.90, 'W': 1.92,
    # 0.72 m tyres, 255 front / 285 rear, 2 cm arch gaps (the brief): the lowered one, not the Camel
    'wheel': {'r': 0.36, 'w': 0.255, 'w_rear': 0.285, 'track': 1.62, 'track_rear': 1.64, 'arch_gap': 0.02,
              'rim': '5spoke', 'rim_ratio': 0.70},
    # low hood to a cowl at 1.02, screen raked 38 deg to a flat roof at 1.62, a 12 deg backlight down to the
    # bed rail at 1.08, then one level line to the tailgate (the cover sits flush with the rails)
    'top': [(0.0, 0.76), (0.05, 0.84), (0.30, 0.88), (1.25, 1.02), (1.68, 1.59), (1.78, 1.62), (2.52, 1.62), (2.60, 1.60),
            (2.71, 1.10), (2.72, 1.08), (2.725, 1.02), (2.775, 1.02), (2.78, 1.08), (5.00, 1.08), (5.05, 1.02)],
    # the belly at 0.20; the frame rails hang to the 0.14 ground clearance (kit)
    'floor': [(0, 0.42), (0.22, 0.20), (4.80, 0.20), (5.05, 0.34)],
    # flat bed sides, half width 0.96, the nose a little narrower
    # a real 60 mm cab-to-bed gap in the loft: the sides and the top step in 60 mm between 2.72 and 2.78
    'hw': [(0, 0.82), (0.06, 0.90), (0.30, 0.94), (0.70, 0.96), (2.72, 0.96), (2.725, 0.90), (2.775, 0.90), (2.78, 0.96),
           (4.95, 0.96), (5.05, 0.95)],
    # the shoulder crease at 0.82 nose to tail: the highlight line and the paint split (Bone over Black)
    'waist': [(0, 0.72), (0.30, 0.82), (5.05, 0.82)],
    # belt line 1.08 on the cab; behind it the bed side runs just under the rail top
    'belt': [(0, 0.84), (0.30, 0.92), (1.25, 1.02), (1.45, 1.08), (2.74, 1.08), (5.05, 1.06)],
    'tumble': 0.03, 'sill_in': 0.04, 'rocker_h': 0.30,
    # regular cab: screen base 1.25, roof 1.68-2.60, a near-vertical back wall at 2.71; no pillar inside the glass
    'cabin': {'A': 1.25, 'W': 1.68, 'R': 2.60, 'C': 2.71, 'D': 2.72,
              'roof_w': [(1.68, 0.78), (2.60, 0.78)], 'roof_drop': 0.03, 'pillars': []},
    'decals': [
        # twin wide rectangles flush in a full-width black mesh grille, a thin amber marker line under each
        {'view': 'front', 'rect': (-0.78, 0.70, 0.78, 0.92), 'mat': 'grille', 'cell': 0.2},
        {'view': 'front', 'rect': (0.33, 0.74, 0.75, 0.88), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (0.33, 0.705, 0.75, 0.725), 'mat': 'turn', 'mirror': True},
        # tall red blocks at the roll-pan corners, 1.76 m apart centre to centre
        {'view': 'rear', 'rect': (0.79, 0.58, 0.91, 1.04), 'mat': 'tail', 'mirror': True},
    ],
    'parts': [
        MIRRORS,
    ],
    # one oval tip out the right rear corner, through the roll pan (the design check wants 0.6 m clear behind a tip)
    'exhaust': [{'x': 0.68, 'y': 0.30, 'r': 0.05, 'squash': 0.6}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.32, 0.58, 2.42, 0.86), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.40, 0.14, 0.40, 1.12)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.65, 0.65, 0.65, 0.91), 'note': 'tailgate centre, between the lamp blocks'},
    ],
    'paint': {'hero': ('Bone', '#E7E1D3'), 'alts': [('Oxide', '#7A3A24'), ('Gunmetal', '#4A4F58'), ('Forest', '#1F4D3A'), ('Sodium', '#FF8A1F')],
              'trim': '#15171C', 'rim': '#22252C'},
    # T2, a working truck: bed rail and bumper scratches (the brief: 0.3)
    'condition': 0.3,
    'options': {},
}

P7 = {
    'id': 'p7_wagon', 'role': 'player', 'label': 'Shop wagon',
    'refs': 'the boxy front-drive estate cars of the late 1980s (category only; no brand): a small four, an automatic, barn doors',
    'rule': 'A shoebox on small wheels: snub nose, short flat bonnet, then ONE flat roof line from the top of the windscreen '
            'to a square tail; glass all round, three side windows, two barn doors, tall lamp columns at the rear corners.',
    'tier': 'T1 shop wagon (Bramley 240 Estate, placeholder name), free; sheet notes/car-sheets/p7_wagon, added 2026-10-11. '
            'Stand-ins, not in the sheet: bonnet height (0.86 nose to 0.96 at the screen), nose and tail plan curves. '
            'The sheet asks for square arches and a 34 degree screen; the loft draws round arches, and A-pillar base '
            's=1.05 with screen top s=1.55 over this bonnet gives 40 degrees.',
    'L': 4.30, 'WB': 2.60, 'OHf': 0.72, 'W': 1.74,
    'wheel': {'r': 0.305, 'w': 0.185, 'track': 1.46, 'arch_gap': 0.05, 'rim': 'steel', 'rim_ratio': 0.60},
    'top': [(0.0, 0.66), (0.04, 0.80), (0.14, 0.86), (1.05, 0.96), (1.55, 1.55), (4.22, 1.55), (4.27, 0.88), (4.30, 0.56)],
    'floor': [(0, 0.34), (0.20, 0.16), (3.95, 0.16), (4.30, 0.30)],
    # pinched 2 cm at the doors: 0.85 there, 0.87 over the arches
    'hw': [(0, 0.74), (0.06, 0.83), (0.20, 0.87), (1.10, 0.87), (1.25, 0.85), (2.80, 0.85), (2.95, 0.87), (3.75, 0.87),
           (4.24, 0.86), (4.30, 0.82)],
    'waist': [(0, 0.56), (0.20, 0.60), (4.30, 0.60)],
    # the belt is one straight line at 0.86, no sweep
    'belt': [(0, 0.60), (0.05, 0.76), (0.14, 0.83), (1.05, 0.86), (4.30, 0.86)],
    'tumble': 0.04, 'sill_in': 0.03, 'rocker_h': 0.30, 'rocker_trim': True,
    'cabin': {'A': 1.05, 'W': 1.55, 'R': 4.22, 'C': 4.27, 'D': 4.22,
              'roof_w': [(1.55, 0.72), (4.22, 0.74)], 'roof_drop': 0.02, 'pillars': [(2.10, 2.17), (3.15, 3.22)]},
    'decals': [
        # slot grille 0.90 x 0.06 between single square flush lamps 0.18 x 0.16
        {'view': 'front', 'rect': (-0.45, 0.70, 0.45, 0.76), 'mat': 'grille'},
        {'view': 'front', 'rect': (0.50, 0.66, 0.68, 0.82), 'mat': 'head', 'mirror': True},
        # black plastic bumpers, an amber indicator in the front one
        {'view': 'front', 'rect': (-0.84, 0.36, 0.84, 0.54), 'mat': 'trim', 'cell': 0.3, 'tag': 'fbumper'},
        {'view': 'front', 'rect': (0.52, 0.42, 0.66, 0.48), 'mat': 'turn', 'mirror': True},
        # tall lamp columns at the rear corners, bumper top to the gutter:
        # amber bottom third, red above; a brake lamp on the roof edge
        {'view': 'rear', 'rect': (0.70, 0.56, 0.82, 0.875), 'mat': 'turn', 'mirror': True},
        {'view': 'rear', 'rect': (0.70, 0.875, 0.82, 1.51), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.15, 1.495, 0.15, 1.535), 'mat': 'tail', 'tag': 'roof_brake'},
        {'view': 'rear', 'rect': (-0.84, 0.36, 0.84, 0.54), 'mat': 'trim', 'cell': 0.3, 'tag': 'rbumper'},
        # the 40 mm black rub strip along the waist
        {'view': 'left', 'rect': (0.22, 0.58, 4.20, 0.62), 'mat': 'trim', 'mirror': True, 'cell': 0.5, 'tag': 'rub'},
    ],
    'parts': [MIRRORS],
    'exhaust': [{'x': -0.45, 'y': 0.26, 'r': 0.035}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.55, 0.545, 2.65, 0.895), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.30, 0.30, 0.85)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.62, 0.575, -0.07, 1.025), 'note': 'left barn door'},
    ],
    'paint': {'hero': ('Shop white', '#E4DDD0'),
              'alts': [('Primer grey', '#7E7F82'), ('Fleet tan', '#B89B6E'), ('Sodium', '#FF8A1F'), ('Dusk navy', '#1B2A4A')],
              'trim': '#1A1D24', 'rim': '#B9BEC6', 'extra': {'chrome': '#C9CED6'}},
    'options': {},
}

# ----------------------------------------------------------------------------
# NPC FLEET: taller, softer, small wheels in big arch gaps, tyres tucked in,
# no aero, plain paints. They recede so the player's car always pops.
# ----------------------------------------------------------------------------
P8 = {
    'id': 'p8_driftcoupe', 'role': 'player', 'label': 'Drift coupe',
    'refs': 'the 1983-91 rear-drive box coupes (category only; no brand): a 1.6 twin-cam notchback',
    'rule': 'A low flat-sided box with a wedge nose, thin pillars and a long flat trunk, on bolt-on arches '
            'with no air. "Sideways is where it is comfortable."',
    'tier': "T2 drift coupe (Ashida Levant, placeholder name; Kasumi Run's car, for sale once you beat Kasumi Run), "
            'sheet notes/car-sheets/p8_driftcoupe, built from parts 2026-10-11 (tools/car_pipeline/kit_p8_driftcoupe.py). '
            'Flat slab flanks (no shoulder crease, belt a dead-straight hard fold at 0.80), a 52 degree screen, a 48 '
            'degree backlight onto a flat trunk (notchback, not a hatch), slim pop-ups in a flat wedge, four bolt-on '
            'riveted arches 6 cm proud of the 1.68 body (1.80 over them), three-bar tail clusters, one primer front-left '
            'fender. Differs from P1: no fastback, no hoop wing, upright glass, bolt-ons, flat trunk.',
    'L': 4.30, 'WB': 2.64, 'OHf': 0.78, 'W': 1.68,
    # 15 x 8 deep dish on 205/50 front, 195/50 rear (0.60 m), arch gap 1 cm, the bronze face with a polished lip
    'wheel': {'r': 0.30, 'w': 0.205, 'w_rear': 0.195, 'track': 1.50, 'arch_gap': 0.01, 'rim': 'dish', 'rim_ratio': 0.72},
    # wedge nose with a chin lip, flat hood (10 mm crown), screen 1.45-2.05, roof flat 2.05-3.05, backlight to the
    # C-pillar foot at 3.45, then a flat trunk to 4.22 and a square tail edge
    'top': [(0.0, 0.50), (0.04, 0.60), (0.22, 0.66), (0.78, 0.74), (1.45, 0.84), (2.05, 1.31), (2.20, 1.34), (2.90, 1.34),
            (3.05, 1.32), (3.45, 0.98), (4.20, 0.965), (4.26, 0.945), (4.30, 0.88)],
    'floor': [(0, 0.30), (0.18, 0.10), (4.12, 0.10), (4.30, 0.30)],
    # the body is 0.84 half wide the whole way (flat slab flanks); the bolt-on arches carry it out to 0.90
    'hw': [(0, 0.64), (0.06, 0.76), (0.28, 0.84), (4.10, 0.84), (4.24, 0.80), (4.30, 0.76)],
    'waist': [(0, 0.40), (0.28, 0.50), (4.30, 0.52)],
    # the belt: 0.80 dead straight from the A-pillar back; it drops with the wedge ahead of it
    'belt': [(0, 0.44), (0.06, 0.56), (0.28, 0.64), (0.78, 0.70), (1.45, 0.80), (4.30, 0.80)],
    'tumble': 0.03, 'sill_in': 0.03, 'rocker_h': 0.24,
    # front, rear and top decals land as exact mirror pairs (car._project_tris): the tail panel's corners
    # landed 2 mm apart left and right, so the trim was never mirrored and the full build lit unevenly
    'sym_decals': True,
    # thin pillars, a 6 cm blacked B-pillar, the roof 0.60 to 0.59 half wide
    'cabin': {'A': 1.45, 'W': 2.05, 'R': 3.05, 'C': 3.45, 'D': 3.35,
              'roof_w': [(2.05, 0.60), (3.05, 0.59)], 'roof_drop': 0.03, 'pillars': [(2.52, 2.58)]},
    'decals': [
        # nose and tail decals pin their own offset, so the car measures its sheet length.
        # nose: a slot grille in the wedge, amber corner markers fixed in the nose corners, a black strip
        # under the chin; the head lamps are slim pop-ups (parts)
        {'view': 'front', 'rect': (-0.36, 0.43, 0.36, 0.49), 'mat': 'grille', 'tag': 'fbumper', 'offset': 0.004},
        {'view': 'front', 'rect': (0.58, 0.42, 0.70, 0.50), 'mat': 'turn', 'mirror': True, 'offset': 0.006},
        {'view': 'front', 'rect': (-0.70, 0.355, 0.70, 0.395), 'mat': 'trim', 'tag': 'fstrip', 'cell': 0.4, 'offset': 0.004},
        # tail: a dark satin panel with a three-bar cluster a side (0.30 x 0.22), the plate between them, no high
        # brake lamp (era); the parts build cuts the bars into tail / brake / blinker / reverse parts
        {'view': 'rear', 'rect': (-0.74, 0.56, 0.74, 0.82), 'mat': 'trim', 'tag': 'tail_panel', 'cell': 0.2, 'offset': 0.004},
        {'view': 'rear', 'rect': (0.40, 0.58, 0.70, 0.80), 'mat': 'tail', 'mirror': True, 'tag': 'cluster', 'offset': 0.006},
        {'view': 'rear', 'rect': (-0.27, 0.59, 0.27, 0.72), 'mat': 'trim', 'tag': 'plate_recess', 'offset': 0.005},
        {'view': 'rear', 'rect': (-0.68, 0.34, 0.68, 0.44), 'mat': 'trim', 'tag': 'rbumper', 'offset': 0.004},
    ],
    'parts': [
        # small black door mirrors
        {'type': 'mirrors', 's': 1.60, 'mat': 'trim'},
        # slim pop-ups: a 0.36 x 0.09 face when up; the parts build hangs each on its own hinge, modelled down
        {'type': 'popups', 'tag': 'popups', 's0': 0.32, 's1': 0.58, 'x0': 0.31, 'x1': 0.67, 'h': 0.09},
        # four bolt-on riveted arches, 6 cm proud, a polished rolled lip (the highlight line), 14 rivets each
        {'type': 'flares', 'tag': 'bolt_on', 'band': 0.09, 'proud': 0.06, 'lip_mat': 'chrome', 'rivets': 14},
    ],
    # one big oval tip on the right, behind the axle (0.09 x 0.06)
    'exhaust': [{'x': 0.42, 'y': 0.26, 'r': 0.045, 'squash': 0.67}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.80, 0.44, 2.70, 0.72), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.25, 0.42, 0.25, 1.12)},
        # the rear slot: a bumper sticker on the tail face between the bumper band and the tail panel (the trunk
        # stays clear; the fleet check wants the rear slot on the upright tail, so the sheet's quarter-panel spot
        # cannot be it)
        {'id': 'rear', 'view': 'rear', 'rect': (-0.30, 0.455, 0.30, 0.555), 'note': 'tail face, under the tail panel'},
    ],
    'paint': {'hero': ('Dusty silver', '#AAB0B8'),
              'alts': [('Chalk', '#E6E2D6'), ('Sodium', '#FF8A1F'), ('Dusk navy', '#1B2A4A'), ('Primer grey', '#6E6B68')],
              'trim': '#1A1D24', 'rim': '#9C6B3A', 'extra': {'primer': '#5F5B58', 'chrome': '#C9CED6'}},
    # T2 (0.2-0.35): a used drift car, one primer fender, scuffed rear bumper corners. Read by the paint work when wear lands.
    'condition': 0.3,
    'options': {},
}

N1 = {
    'id': 'n1_commuter', 'role': 'npc', 'label': 'Commuter sedan',
    'refs': 'Camry, Accord, Sentra',
    'rule': 'Soft, tall-cabin modern sedan: short hood, high short deck, small wheels in big arch gaps.',
    'L': 4.80, 'WB': 2.80, 'OHf': 0.98, 'W': 1.82,
    'wheel': {'r': 0.31, 'w': 0.205, 'track': 1.56, 'arch_gap': 0.075, 'rim': 'turbofan', 'rim_ratio': 0.66},
    'top': [(0.0, 0.70), (0.07, 0.81), (0.30, 0.90), (1.30, 1.02), (2.10, 1.49), (3.10, 1.51), (3.94, 1.14),
            (4.62, 1.12), (4.74, 1.06), (4.80, 0.86)],
    'floor': [(0, 0.30), (0.30, 0.16), (4.50, 0.16), (4.68, 0.22), (4.80, 0.36)],
    'hw': [(0, 0.70), (0.20, 0.86), (0.60, 0.905), (4.20, 0.91), (4.60, 0.88), (4.80, 0.82)],
    'waist': [(0, 0.52), (0.40, 0.64), (4.80, 0.66)],
    'belt': [(0, 0.70), (0.30, 0.88), (1.30, 1.01), (3.94, 1.10), (4.80, 1.04)],
    'tumble': 0.08, 'sill_in': 0.035, 'rocker_h': 0.32,
    'cabin': {'A': 1.30, 'W': 2.10, 'R': 3.10, 'C': 3.94, 'D': 3.72,
              'roof_w': [(2.10, 0.71), (3.10, 0.69), (3.94, 0.73)], 'roof_drop': 0.06, 'pillars': [(2.70, 2.80)]},
    'decals': [
        {'view': 'front', 'rect': (0.48, 0.70, 0.86, 0.80), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.40, 0.60, 0.40, 0.74), 'mat': 'grille'},
        {'view': 'front', 'rect': (-0.45, 0.28, 0.45, 0.40), 'mat': 'grille'},
        {'view': 'rear', 'rect': (0.52, 0.90, 0.88, 1.02), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.25, 0.56, 0.25, 0.70), 'mat': 'trim'},
    ],
    'parts': [MIRRORS],
    'exhaust': [{'x': -0.55, 'y': 0.28, 'r': 0.03}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.90, 0.50, 3.40, 0.72), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.40, 0.30, 1.15)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.46, 0.90, 0.46, 1.02), 'note': 'tail panel'},
    ],
    'paint': {'traffic': True},
    'options': {},
}

N2 = {
    'id': 'n2_cityhatch', 'role': 'npc', 'label': 'City hatchback',
    'refs': 'Yaris, Fit, Swift',
    'rule': 'Tall cab-forward egg: stubby nose, long raked windshield, high flat roof, tall tail lamps up the pillars.',
    'L': 3.95, 'WB': 2.53, 'OHf': 0.80, 'W': 1.69,
    'wheel': {'r': 0.295, 'w': 0.185, 'track': 1.46, 'arch_gap': 0.065, 'rim': 'steel', 'rim_ratio': 0.66},
    'top': [(0.0, 0.60), (0.06, 0.72), (0.25, 0.82), (0.80, 0.96), (1.78, 1.50), (3.70, 1.53), (3.84, 1.14),
            (3.91, 1.08), (3.95, 0.66)],
    'floor': [(0, 0.27), (0.25, 0.15), (3.70, 0.15), (3.95, 0.29)],
    'hw': [(0, 0.66), (0.15, 0.79), (0.45, 0.84), (3.55, 0.845), (3.85, 0.82), (3.95, 0.78)],
    'waist': [(0, 0.50), (0.40, 0.62), (3.95, 0.64)],
    'belt': [(0, 0.62), (0.30, 0.80), (0.80, 0.92), (3.70, 1.02), (3.95, 0.97)],
    'tumble': 0.07, 'sill_in': 0.035, 'rocker_h': 0.30,
    'cabin': {'A': 0.80, 'W': 1.78, 'R': 3.70, 'C': 3.84, 'D': 3.48,
              'roof_w': [(1.78, 0.66), (3.70, 0.65)], 'roof_drop': 0.03, 'pillars': [(2.22, 2.30)]},
    'decals': [
        {'view': 'front', 'rect': (0.46, 0.72, 0.80, 0.82), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.30, 0.66, 0.30, 0.74), 'mat': 'grille'},
        {'view': 'front', 'rect': (-0.40, 0.28, 0.40, 0.38), 'mat': 'grille'},
        {'view': 'rear', 'rect': (0.64, 0.82, 0.78, 1.30), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.24, 0.52, 0.24, 0.64), 'mat': 'trim'},
    ],
    'parts': [MIRRORS],
    'exhaust': [{'x': -0.45, 'y': 0.26, 'r': 0.028}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.30, 0.50, 2.90, 0.75), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.28, 0.20, 0.28, 0.72)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.35, 0.82, 0.35, 0.98), 'note': 'tailgate'},
    ],
    'paint': {'traffic': True},
    'options': {},
}

N3 = {
    'id': 'n3_pickup', 'role': 'npc', 'label': 'Pickup',
    'refs': 'Hilux, F-150, Land Cruiser',
    'rule': 'Tall double-cab with an open bed behind it: flat slab sides, big tyres, high ground clearance.',
    'L': 5.30, 'WB': 3.08, 'OHf': 0.92, 'W': 1.86,
    'wheel': {'r': 0.39, 'w': 0.265, 'track': 1.58, 'arch_gap': 0.07, 'arch_lift': 0.02, 'rim': '6spoke', 'rim_ratio': 0.62},
    'top': [(0.0, 1.02), (0.04, 1.12), (0.20, 1.18), (1.25, 1.24), (1.92, 1.82), (3.20, 1.86), (3.28, 1.32),
            (5.27, 1.24), (5.30, 1.20)],
    'floor': [(0, 0.50), (0.32, 0.30), (4.40, 0.30), (5.30, 0.56)],
    'hw': [(0, 0.82), (0.08, 0.90), (0.30, 0.93), (5.20, 0.93), (5.30, 0.92)],
    'waist': [(0, 0.82), (0.40, 0.95), (5.30, 0.95)],
    'belt': [(0, 1.02), (0.20, 1.14), (1.25, 1.21), (3.28, 1.25), (5.30, 1.25)],
    'tumble': 0.035, 'sill_in': 0.03, 'rocker_h': 0.52,
    'cabin': {'A': 1.25, 'W': 1.92, 'R': 3.20, 'C': 3.28, 'D': 3.15,
              'roof_w': [(1.92, 0.73), (3.20, 0.73)], 'roof_drop': 0.03, 'pillars': [(2.50, 2.60)]},
    'open': [{'s0': 3.34, 's1': 5.27, 'floor': 0.92, 'wall': 0.05, 'mat': 'bed'}],
    'decals': [
        {'view': 'front', 'rect': (-0.55, 0.76, 0.55, 1.04), 'mat': 'grille', 'cell': 0.2},
        {'view': 'front', 'rect': (0.58, 0.90, 0.86, 1.02), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.88, 0.50, 0.88, 0.66), 'mat': 'trim', 'cell': 0.25},
        {'view': 'rear', 'rect': (0.80, 0.84, 0.92, 1.18), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.88, 0.54, 0.88, 0.66), 'mat': 'chrome', 'cell': 0.25},
    ],
    'parts': [
        {'type': 'mirrors', 'out': 0.11, 'up': 0.10},
        {'type': 'step', 's0': 1.40, 's1': 3.10, 'y': 0.42},
    ],
    'exhaust': [{'x': 0.55, 'y': 0.42, 'r': 0.045}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.40, 0.78, 3.05, 1.08), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.32, 0.30, 0.32, 1.10)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.45, 0.90, 0.45, 1.14), 'note': 'tailgate'},
    ],
    'paint': {'traffic': True},
    'options': {},
}

# ----------------------------------------------------------------------------
# COP FLEET: big, slab-sided, upright; every one carries a police tell in its
# outline (light bar, push bar, A-pillar spotlight, antennas). Navy + silver.
# ----------------------------------------------------------------------------
COP_LIVERY = {'paint': '#1B2A4A', 'paint2': '#C9CED6', 'roof': '#C9CED6'}

C1 = {
    'id': 'c1_patrol', 'role': 'cop', 'label': 'Patrol sedan',
    'refs': 'Crown Victoria P71, Charger Pursuit',
    'rule': 'Big square-backed sedan with a light bar on the roof, a push bar up front and a pillar spotlight.',
    'L': 5.30, 'WB': 2.92, 'OHf': 1.08, 'W': 1.96,
    'wheel': {'r': 0.335, 'w': 0.235, 'track': 1.62, 'arch_gap': 0.045, 'rim': 'steel', 'rim_ratio': 0.70},
    'top': [(0.0, 0.70), (0.05, 0.82), (0.20, 0.90), (1.85, 0.98), (2.48, 1.46), (3.50, 1.48), (3.92, 1.07),
            (5.18, 1.05), (5.27, 1.01), (5.30, 0.80)],
    'floor': [(0, 0.32), (0.30, 0.16), (4.95, 0.16), (5.30, 0.35)],
    'hw': [(0, 0.84), (0.08, 0.94), (0.35, 0.975), (4.95, 0.98), (5.20, 0.96), (5.30, 0.92)],
    'waist': [(0, 0.50), (0.35, 0.62), (5.30, 0.64)],
    'belt': [(0, 0.70), (0.20, 0.88), (1.85, 0.96), (3.92, 1.00), (5.30, 0.99)],
    'tumble': 0.05, 'sill_in': 0.03, 'rocker_h': 0.33,
    'cabin': {'A': 1.85, 'W': 2.48, 'R': 3.50, 'C': 3.92, 'D': 3.76,
              'roof_w': [(2.48, 0.72), (3.50, 0.71), (3.92, 0.76)], 'roof_drop': 0.03, 'pillars': [(2.98, 3.08)]},
    'decals': [
        {'view': 'left', 'rect': (1.95, 0.40, 3.85, 0.92), 'mat': 'paint2', 'mirror': True, 'cell': 0.15, 'tag': 'livery'},
        {'view': 'front', 'rect': (-0.45, 0.62, 0.45, 0.80), 'mat': 'grille'},
        {'view': 'front', 'rect': (0.50, 0.66, 0.86, 0.80), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.92, 0.32, 0.92, 0.48), 'mat': 'trim', 'cell': 0.3},
        {'view': 'rear', 'rect': (0.55, 0.80, 0.92, 0.95), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.26, 0.56, 0.26, 0.70), 'mat': 'trim'},
        {'view': 'rear', 'rect': (-0.92, 0.30, 0.92, 0.46), 'mat': 'trim', 'cell': 0.3},
    ],
    'parts': [
        MIRRORS,
        {'type': 'lightbar', 's': 3.00, 'y': 1.47, 'w': 1.30, 'depth': 0.30, 'h': 0.10},
        {'type': 'pushbar', 's': -0.10, 'y0': 0.32, 'y1': 0.98, 'w': 0.86},
        {'type': 'spotlight'},
    ],
    'exhaust': [{'x': 0.62, 'y': 0.28, 'r': 0.04}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (2.00, 0.55, 3.70, 0.80), 'mirror': True, 'note': 'POLICE'},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.40, 0.30, 1.40), 'note': 'unit number'},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.50, 0.78, 0.50, 0.94), 'note': 'tail panel: POLICE'},
    ],
    'paint': {'livery': COP_LIVERY},
    'options': {},
}

C2 = {
    'id': 'c2_patrolsuv', 'role': 'cop', 'label': 'Patrol SUV',
    'refs': 'Police Interceptor Utility, Tahoe PPV',
    'rule': 'Tall box: long flat roof with the light bar, push bar, three side windows, upright tailgate.',
    'L': 5.10, 'WB': 3.03, 'OHf': 0.98, 'W': 2.00,
    'wheel': {'r': 0.37, 'w': 0.255, 'track': 1.70, 'arch_gap': 0.06, 'rim': 'steel', 'rim_ratio': 0.66},
    'top': [(0.0, 0.94), (0.05, 1.05), (0.25, 1.12), (1.25, 1.18), (1.95, 1.76), (4.80, 1.80), (4.98, 1.30),
            (5.06, 1.25), (5.10, 0.86)],
    'floor': [(0, 0.44), (0.32, 0.23), (4.75, 0.23), (5.10, 0.46)],
    'hw': [(0, 0.86), (0.08, 0.96), (0.35, 1.00), (4.90, 1.00), (5.10, 0.95)],
    'waist': [(0, 0.74), (0.35, 0.86), (5.10, 0.88)],
    'belt': [(0, 0.94), (0.25, 1.08), (1.25, 1.15), (4.95, 1.22), (5.10, 1.16)],
    'tumble': 0.045, 'sill_in': 0.03, 'rocker_h': 0.45, 'rocker_trim': True,
    'cabin': {'A': 1.25, 'W': 1.95, 'R': 4.80, 'C': 4.98, 'D': 4.62,
              'roof_w': [(1.95, 0.80), (4.80, 0.80)], 'roof_drop': 0.03, 'pillars': [(2.62, 2.72), (3.62, 3.70)]},
    'decals': [
        {'view': 'left', 'rect': (1.40, 0.62, 3.62, 1.12), 'mat': 'paint2', 'mirror': True, 'cell': 0.15, 'tag': 'livery'},
        {'view': 'front', 'rect': (-0.50, 0.80, 0.50, 1.02), 'mat': 'grille'},
        {'view': 'front', 'rect': (0.55, 0.86, 0.90, 1.00), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.95, 0.44, 0.95, 0.62), 'mat': 'trim', 'cell': 0.3},
        {'view': 'rear', 'rect': (0.80, 0.92, 0.96, 1.30), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.25, 0.66, 0.25, 0.80), 'mat': 'trim'},
        {'view': 'rear', 'rect': (-0.95, 0.46, 0.95, 0.60), 'mat': 'trim', 'cell': 0.3},
    ],
    'parts': [
        {'type': 'mirrors', 'out': 0.11, 'up': 0.10},
        {'type': 'lightbar', 's': 2.55, 'y': 1.77, 'w': 1.40, 'depth': 0.30, 'h': 0.11},
        {'type': 'pushbar', 's': -0.10, 'y0': 0.42, 'y1': 1.12, 'w': 0.95},
        {'type': 'antennas', 'list': [(0.30, 3.80, 0.30), (-0.30, 4.00, 0.30)]},
    ],
    'exhaust': [{'x': 0.62, 'y': 0.36, 'r': 0.045}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.50, 0.75, 3.50, 1.05), 'mirror': True, 'note': 'POLICE'},
        {'id': 'hood', 'view': 'top', 'rect': (-0.32, 0.35, 0.32, 1.10), 'note': 'unit number'},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.40, 0.90, 0.40, 1.10), 'note': 'tailgate'},
    ],
    'paint': {'livery': COP_LIVERY},
    'options': {},
}

C3 = {
    'id': 'c3_interceptor', 'role': 'cop', 'label': 'Unmarked interceptor',
    'refs': 'unmarked Charger Hellcat, Mustang GT PI',
    'rule': 'Big long-hood fastback with a pillar spotlight, a low push bar and a cluster of trunk antennas; no light bar, plain dark paint.',
    'L': 4.82, 'WB': 2.72, 'OHf': 1.02, 'W': 1.92,
    'wheel': {'r': 0.34, 'w': 0.255, 'w_rear': 0.275, 'track': 1.60, 'arch_gap': 0.025, 'rim': 'mono', 'rim_ratio': 0.70, 'rim_mat': 'rim_dark'},
    'top': [(0.0, 0.62), (0.05, 0.74), (0.30, 0.85), (1.85, 0.97), (2.55, 1.36), (3.15, 1.38), (4.12, 1.06),
            (4.64, 1.04), (4.74, 1.07), (4.78, 1.06), (4.82, 0.84)],
    'floor': [(0, 0.28), (0.30, 0.13), (4.55, 0.13), (4.82, 0.31)],
    'hw': [(0, 0.78), (0.12, 0.91), (0.45, 0.95), (3.40, 0.96), (4.00, 0.96), (4.60, 0.92), (4.82, 0.86)],
    'waist': [(0, 0.46), (0.40, 0.58), (4.82, 0.60)],
    'belt': [(0, 0.62), (0.30, 0.83), (1.85, 0.95), (3.60, 1.02), (4.82, 0.98)],
    'tumble': 0.07, 'sill_in': 0.035, 'rocker_h': 0.30,
    'cabin': {'A': 1.85, 'W': 2.55, 'R': 3.15, 'C': 4.12, 'D': 3.72,
              'roof_w': [(2.55, 0.62), (3.15, 0.60), (4.12, 0.70)], 'roof_drop': 0.035, 'pillars': []},
    'decals': [
        {'view': 'front', 'rect': (-0.48, 0.54, 0.48, 0.70), 'mat': 'grille'},
        {'view': 'front', 'rect': (0.52, 0.62, 0.86, 0.72), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.30, 0.58, -0.18, 0.62), 'mat': 'pol_r'},
        {'view': 'front', 'rect': (0.18, 0.58, 0.30, 0.62), 'mat': 'pol_b'},
        {'view': 'front', 'rect': (-0.62, 0.22, 0.62, 0.36), 'mat': 'grille', 'tag': 'fbumper'},
        {'view': 'rear', 'rect': (0.48, 0.86, 0.86, 0.895), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (0.48, 0.80, 0.86, 0.835), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.25, 0.56, 0.25, 0.70), 'mat': 'trim'},
        {'view': 'rear', 'rect': (-0.75, 0.24, 0.75, 0.36), 'mat': 'trim', 'tag': 'rbumper'},
        {'view': 'rear', 'rect': (-0.20, 0.92, -0.08, 0.95), 'mat': 'pol_r'},
        {'view': 'rear', 'rect': (0.08, 0.92, 0.20, 0.95), 'mat': 'pol_b'},
    ],
    'parts': [
        MIRRORS,
        {'type': 'spotlight'},
        {'type': 'antennas', 'list': [(0.25, 4.42, 0.28), (0.0, 4.48, 0.32), (-0.25, 4.42, 0.28)]},
        # a low black push bar (Build 4, Roy 1475): its police tell up front, so it is no outline twin of the drift coupe
        {'type': 'pushbar', 's': -0.10, 'y0': 0.28, 'y1': 0.80, 'w': 0.84, 'tag': 'pushbar'},
    ],
    'exhaust': [{'x': 0.52, 'y': 0.26, 'r': 0.04}, {'x': 0.66, 'y': 0.26, 'r': 0.04},
                {'x': -0.52, 'y': 0.26, 'r': 0.04}, {'x': -0.66, 'y': 0.26, 'r': 0.04}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (2.00, 0.52, 3.20, 0.74), 'mirror': True, 'note': 'empty (unmarked)'},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.40, 0.30, 1.40), 'note': 'empty (unmarked)'},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.44, 0.79, 0.44, 0.90), 'note': 'empty (unmarked)'},
    ],
    'paint': {'hero': ('Gunmetal', '#2E333C'), 'alts': [('Black', '#15171C'), ('Silver', '#C9CED6'), ('Dark red', '#4A1218')],
              'trim': '#1A1D24', 'rim': '#22252C'},
    'options': {},
}

FLEET = [P0, P1, P2, P3, P4, P5, P6, P7, P10, P17, P8, N1, N2, N3, C1, C2, C3]


def _add_sun_strips():
    """Roy's step 1 sign-off (2026-10-05): 4 sticker slots per car, door, hood,
    windshield sun strip, rear. The strip is a banner across the top of the
    windshield, between the A-pillars, drawn from above so it hugs the glass."""
    for D in FLEET:
        cab = D['cabin']
        rw = cab['roof_w']
        w = (rw[0][1] if isinstance(rw, list) else rw) - 0.07
        note = 'empty (unmarked)' if D['id'] == 'c3_interceptor' else 'windshield sun strip'
        strip = {'id': 'sun', 'view': 'top', 'rect': (-w, cab['W'] - 0.15, w, cab['W'] - 0.02), 'note': note}
        i = [st['id'] for st in D['stickers']].index('rear')
        D['stickers'].insert(i, strip)


_add_sun_strips()

# Traffic paints (NPC): neutral, weighted. Nothing here may outshine a player car.
TRAFFIC_PAINTS = [
    ('Silver', '#C9CED6', 22), ('Pearl', '#E9E6DF', 18), ('Black', '#15171C', 16), ('Gunmetal', '#4A505B', 14),
    ('Navy', '#26314D', 8), ('Beige', '#B9AE98', 7), ('Faded red', '#8E2A28', 6), ('Dark green', '#2B4A3A', 5),
    ('Taxi amber', '#F2B53A', 4),
]


def colors_for(defn, paint_hex=None):
    """Material colour overrides for a render."""
    p = defn['paint']
    if 'livery' in p:
        out = dict(p['livery'])
        out['trim'] = '#1A1D24'
        return out
    if p.get('traffic'):
        return {'paint': paint_hex or '#C9CED6', 'trim': '#1A1D24', 'rim': '#A9AEB6'}
    out = {'paint': paint_hex or p['hero'][1], 'trim': p.get('trim', '#1A1D24'), 'rim': p.get('rim', '#C9CED6')}
    if p.get('rim'):
        out['rim_bronze'] = p['rim']
    out.update(p.get('extra', {}))  # e.g. the beater's primer lid (paint2)
    return out
