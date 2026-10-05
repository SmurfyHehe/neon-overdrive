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
        {'id': 'rear', 'view': 'rear', 'rect': (-0.45, 1.06, 0.45, 1.14), 'note': 'rear window banner'},
    ],
    'paint': {'hero': ('Sodium', '#FF8A1F'), 'alts': [('Silver', '#C9CED6'), ('Midnight', '#1B2A4A'), ('Signal red', '#B3191E'), ('Pearl', '#E9E6DF')],
              'trim': '#1A1D24', 'rim': '#C9CED6'},
    'options': {},
}

P2 = {
    'id': 'p2_hothatch', 'role': 'player', 'label': 'Hot hatch',
    'refs': 'Civic Si/EK, Golf GTI Mk2, 205 GTI',
    'rule': 'Short brick on wheels pushed to the corners: upright hatch, roof spoiler, wide low stance.',
    'L': 4.05, 'WB': 2.55, 'OHf': 0.86, 'W': 1.76,
    'wheel': {'r': 0.305, 'w': 0.215, 'track': 1.53, 'arch_gap': 0.025, 'rim': '6spoke', 'rim_ratio': 0.68},
    'top': [(0.0, 0.60), (0.05, 0.69), (0.25, 0.78), (1.22, 0.92), (1.84, 1.35), (3.58, 1.36), (3.66, 1.33),
            (3.90, 0.99), (4.00, 0.96), (4.05, 0.62)],
    'floor': [(0, 0.27), (0.22, 0.13), (3.75, 0.13), (4.05, 0.28)],
    'hw': [(0, 0.70), (0.10, 0.82), (0.40, 0.86), (0.48, 0.88), (1.24, 0.88), (1.32, 0.86), (3.03, 0.86), (3.11, 0.88),
           (3.71, 0.88), (3.80, 0.86), (3.92, 0.845), (4.05, 0.80)],
    'waist': [(0, 0.48), (0.40, 0.58), (3.80, 0.60), (4.05, 0.58)],
    'belt': [(0, 0.58), (0.25, 0.75), (1.22, 0.90), (3.58, 1.00), (4.05, 0.92)],
    'tumble': 0.05, 'sill_in': 0.03, 'rocker_h': 0.28,
    'cabin': {'A': 1.22, 'W': 1.84, 'R': 3.58, 'C': 3.90, 'D': 3.38,
              'roof_w': [(1.86, 0.63), (3.55, 0.61)], 'roof_drop': 0.03, 'pillars': [(2.62, 2.70)]},
    'decals': [
        {'view': 'front', 'rect': (-0.40, 0.50, 0.40, 0.58), 'mat': 'grille'},
        {'view': 'front', 'rect': (0.42, 0.50, 0.76, 0.62), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.50, 0.22, 0.50, 0.36), 'mat': 'grille', 'tag': 'fbumper'},
        {'view': 'front', 'circle': (0.60, 0.29, 0.04, 10), 'mat': 'head', 'mirror': True},
        {'view': 'rear', 'rect': (0.56, 0.70, 0.82, 0.94), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.25, 0.52, 0.25, 0.66), 'mat': 'trim'},
        {'view': 'rear', 'rect': (-0.65, 0.22, 0.65, 0.32), 'mat': 'trim', 'tag': 'rbumper'},
    ],
    'parts': [
        MIRRORS,
        {'type': 'roof_spoiler', 'tag': 'spoiler', 's0': 3.46, 's1': 3.80, 'y0': 1.36, 'y1': 1.28, 'span': 1.32, 'thick': 0.045, 'brake_light': True},
    ],
    'exhaust': [{'x': -0.42, 'y': 0.24, 'r': 0.038}, {'x': -0.32, 'y': 0.24, 'r': 0.038}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.55, 0.42, 2.45, 0.66), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.35, 0.30, 1.05)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.42, 1.22, 0.42, 1.30), 'note': 'hatch glass banner'},
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
        {'id': 'rear', 'view': 'top', 'rect': (-0.40, 3.60, 0.40, 4.05), 'note': 'trunk lid'},
    ],
    'paint': {'hero': ('Pearl white', '#E9E6DF'), 'alts': [('Gunmetal', '#4A505B'), ('Silver', '#C9CED6'), ('Sodium', '#FF8A1F'), ('Black', '#15171C')],
              'trim': '#1A1D24', 'rim': '#9C6B3A'},
    'options': {},
}

P4 = {
    'id': 'p4_kei', 'role': 'player', 'label': 'Kei roadster',
    'refs': 'Honda Beat, Suzuki Cappuccino, Autozam AZ-1',
    'rule': 'Tiny open two-seater: no roof, twin headrest humps, wheels at the very corners.',
    'L': 3.30, 'WB': 2.27, 'OHf': 0.55, 'W': 1.40,
    'wheel': {'r': 0.28, 'w': 0.175, 'w_rear': 0.185, 'track': 1.23, 'arch_gap': 0.025, 'rim': '5spoke', 'rim_ratio': 0.66},
    'top': [(0.0, 0.48), (0.05, 0.57), (0.22, 0.63), (0.92, 0.74), (1.30, 1.12), (1.36, 1.13), (1.42, 0.82),
            (2.32, 0.80), (3.05, 0.82), (3.22, 0.79), (3.30, 0.62)],
    'floor': [(0, 0.24), (0.16, 0.12), (3.10, 0.12), (3.30, 0.28)],
    'hw': [(0, 0.52), (0.08, 0.63), (0.30, 0.69), (3.00, 0.70), (3.20, 0.66), (3.30, 0.60)],
    'waist': [(0, 0.36), (0.30, 0.46), (3.30, 0.48)],
    'belt': [(0, 0.46), (0.30, 0.60), (0.92, 0.71), (2.32, 0.77), (3.30, 0.74)],
    'tumble': 0.05, 'sill_in': 0.03, 'rocker_h': 0.26,
    'cabin': {'A': 0.92, 'W': 1.30, 'R': 1.36, 'C': 1.42, 'D': 1.40,
              'roof_w': 0.54, 'roof_drop': 0.02, 'pillars': [], 'roof_h': 1.13},
    'open': [{'s0': 1.42, 's1': 2.32, 'floor': 0.42, 'wall': 0.06, 'mat': 'interior'}],
    'decals': [
        {'view': 'front', 'ellipse': (0.48, 0.52, 0.10, 0.055, 12), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.25, 0.28, 0.25, 0.36), 'mat': 'grille', 'tag': 'fbumper'},
        {'view': 'left', 'rect': (2.36, 0.46, 2.60, 0.62), 'mat': 'grille', 'mirror': True},
        {'view': 'rear', 'ellipse': (0.48, 0.66, 0.09, 0.05, 12), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.50, 0.22, 0.50, 0.30), 'mat': 'trim', 'tag': 'rbumper'},
    ],
    'parts': [
        {'type': 'mirrors', 's': 1.10},
        {'type': 'rollhoops', 's': 2.30, 'h': 1.00, 'x': 0.30, 'w': 0.26},
    ],
    'exhaust': [{'x': 0.35, 'y': 0.22, 'r': 0.035}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.30, 0.40, 2.05, 0.60), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.25, 0.15, 0.25, 0.80)},
        {'id': 'rear', 'view': 'top', 'rect': (-0.40, 2.60, 0.40, 3.10), 'note': 'engine lid'},
    ],
    'paint': {'hero': ('Signal yellow', '#F2B53A'), 'alts': [('Signal red', '#B3191E'), ('Cream', '#E8DCC0'), ('Racing green', '#1F4D3A'), ('Silver', '#C9CED6')],
              'trim': '#1A1D24', 'rim': '#C9CED6'},
    'options': {},
}

P5 = {
    'id': 'p5_muscle', 'role': 'player', 'label': 'Muscle sedan',
    'refs': 'Impala SS (1994-96), Chevelle SS, Caprice 9C1',
    'rule': 'Long, low, wide land yacht: tall cowl scoop, chopped slit-window cabin, ducktail, coke-bottle hips; full-width tail bar.',
    'L': 5.35, 'WB': 2.95, 'OHf': 1.12, 'W': 1.98,
    'wheel': {'r': 0.345, 'w': 0.255, 'w_rear': 0.30, 'track': 1.62, 'arch_gap': 0.03, 'rim': 'dish', 'rim_ratio': 0.68},
    'top': [(0.0, 0.70), (0.04, 0.79), (0.22, 0.84), (1.88, 0.95), (2.55, 1.31), (3.28, 1.33), (3.92, 1.00),
            (5.06, 0.99), (5.20, 1.08), (5.27, 1.08), (5.32, 0.88), (5.35, 0.70)],
    'floor': [(0, 0.28), (0.30, 0.15), (5.00, 0.15), (5.20, 0.22), (5.35, 0.36)],
    'hw': [(0, 0.86), (0.08, 0.94), (0.45, 0.965), (1.12, 0.975), (1.70, 0.965), (2.40, 0.95), (3.30, 0.955),
           (3.75, 0.975), (4.07, 0.99), (4.60, 0.985), (5.05, 0.95), (5.25, 0.90), (5.35, 0.84)],
    'waist': [(0, 0.48), (0.50, 0.60), (4.00, 0.66), (5.35, 0.62)],
    'belt': [(0, 0.66), (0.30, 0.81), (1.88, 0.93), (3.92, 0.99), (5.35, 0.93)],
    'tumble': 0.09, 'sill_in': 0.04, 'rocker_h': 0.32,
    'cabin': {'A': 1.88, 'W': 2.55, 'R': 3.28, 'C': 3.92, 'D': 3.62,
              'roof_w': [(2.55, 0.66), (3.28, 0.60), (3.92, 0.70)], 'roof_drop': 0.035, 'pillars': [(2.98, 3.08)]},
    'decals': [
        {'view': 'front', 'rect': (-0.48, 0.52, 0.48, 0.66), 'mat': 'grille'},
        {'view': 'front', 'rect': (0.50, 0.53, 0.86, 0.65), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.60, 0.26, 0.60, 0.38), 'mat': 'grille', 'tag': 'fbumper'},
        {'view': 'rear', 'rect': (0.12, 0.80, 0.86, 0.88), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.12, 0.80, 0.12, 0.88), 'mat': 'trim'},
        {'view': 'rear', 'rect': (-0.26, 0.50, 0.26, 0.64), 'mat': 'trim'},
        {'view': 'rear', 'rect': (-0.80, 0.24, 0.80, 0.36), 'mat': 'trim', 'tag': 'rbumper'},
    ],
    'parts': [
        MIRRORS,
        {'type': 'scoop', 'tag': 'hood', 's0': 0.85, 's1': 1.62, 'w': 0.68, 'h': 0.13},
    ],
    'exhaust': [{'x': 0.62, 'y': 0.26, 'r': 0.05}, {'x': -0.62, 'y': 0.26, 'r': 0.05}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (2.00, 0.45, 3.60, 0.66), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.32, 0.40, 0.32, 1.45)},
        {'id': 'rear', 'view': 'top', 'rect': (-0.45, 4.15, 0.45, 5.05), 'note': 'trunk lid'},
    ],
    'paint': {'hero': ('Cherry', '#6A1620'), 'alts': [('Black', '#15171C'), ('Silver', '#C9CED6'), ('Racing green', '#1F4D3A'), ('Pearl', '#E9E6DF')],
              'trim': '#1A1D24', 'rim': '#C9CED6'},
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
        {'type': 'roof_rails', 's0': 2.05, 's1': 3.75, 'x': 0.58, 'h': 0.07, 'bars': [2.45, 3.40]},
        {'type': 'roof_spoiler', 'tag': 'spoiler', 's0': 3.76, 's1': 3.96, 'y0': 1.53, 'y1': 1.49, 'span': 1.26},
    ],
    'exhaust': [{'x': 0.24, 'y': 0.38, 'r': 0.045}, {'x': -0.24, 'y': 0.38, 'r': 0.045}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.55, 0.62, 2.90, 0.85), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.30, 0.30, 1.10)},
        {'id': 'rear', 'view': 'rear', 'rect': (-0.42, 1.38, 0.42, 1.46), 'note': 'hatch glass banner'},
    ],
    'paint': {'hero': ('Sand', '#B8A27A'), 'alts': [('Silver', '#C9CED6'), ('Rally red', '#C41E24'), ('Black', '#15171C'), ('Racing green', '#1F4D3A')],
              'trim': '#1A1D24', 'rim': '#2A2D33'},
    'options': {},
}

# ----------------------------------------------------------------------------
# NPC FLEET: taller, softer, small wheels in big arch gaps, tyres tucked in,
# no aero, plain paints. They recede so the player's car always pops.
# ----------------------------------------------------------------------------
N1 = {
    'id': 'n1_commuter', 'role': 'npc', 'label': 'Commuter sedan',
    'refs': 'Camry, Accord, Sentra',
    'rule': 'Soft, tall-cabin modern sedan: short hood, high short deck, small wheels in big arch gaps.',
    'L': 4.80, 'WB': 2.80, 'OHf': 0.98, 'W': 1.82,
    'wheel': {'r': 0.32, 'w': 0.215, 'track': 1.56, 'arch_gap': 0.065, 'rim': 'turbofan', 'rim_ratio': 0.66},
    'top': [(0.0, 0.66), (0.07, 0.77), (0.30, 0.85), (1.30, 0.98), (2.12, 1.46), (3.12, 1.48), (3.96, 1.10),
            (4.62, 1.08), (4.74, 1.03), (4.80, 0.86)],
    'floor': [(0, 0.30), (0.30, 0.16), (4.50, 0.16), (4.68, 0.22), (4.80, 0.36)],
    'hw': [(0, 0.70), (0.20, 0.86), (0.60, 0.905), (4.20, 0.91), (4.60, 0.88), (4.80, 0.82)],
    'waist': [(0, 0.52), (0.40, 0.64), (4.80, 0.66)],
    'belt': [(0, 0.66), (0.30, 0.84), (1.30, 0.97), (3.96, 1.06), (4.80, 1.00)],
    'tumble': 0.08, 'sill_in': 0.035, 'rocker_h': 0.32,
    'cabin': {'A': 1.30, 'W': 2.12, 'R': 3.12, 'C': 3.96, 'D': 3.72,
              'roof_w': [(2.12, 0.66), (3.12, 0.63), (3.96, 0.70)], 'roof_drop': 0.035, 'pillars': [(2.70, 2.80)]},
    'decals': [
        {'view': 'front', 'rect': (0.48, 0.66, 0.86, 0.76), 'mat': 'head', 'mirror': True},
        {'view': 'front', 'rect': (-0.40, 0.58, 0.40, 0.70), 'mat': 'grille'},
        {'view': 'front', 'rect': (-0.45, 0.28, 0.45, 0.40), 'mat': 'grille'},
        {'view': 'rear', 'rect': (0.52, 0.88, 0.88, 1.00), 'mat': 'tail', 'mirror': True},
        {'view': 'rear', 'rect': (-0.25, 0.56, 0.25, 0.70), 'mat': 'trim'},
    ],
    'parts': [MIRRORS],
    'exhaust': [{'x': -0.55, 'y': 0.28, 'r': 0.03}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (1.90, 0.50, 3.40, 0.72), 'mirror': True},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.40, 0.30, 1.15)},
        {'id': 'rear', 'view': 'top', 'rect': (-0.40, 4.10, 0.40, 4.60), 'note': 'trunk lid'},
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
        {'id': 'rear', 'view': 'top', 'rect': (-0.45, 4.05, 0.45, 5.05), 'note': 'trunk lid'},
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
    'rule': 'Big long-hood fastback with a pillar spotlight and a cluster of trunk antennas; no light bar, plain dark paint.',
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
    ],
    'exhaust': [{'x': 0.52, 'y': 0.26, 'r': 0.04}, {'x': 0.66, 'y': 0.26, 'r': 0.04},
                {'x': -0.52, 'y': 0.26, 'r': 0.04}, {'x': -0.66, 'y': 0.26, 'r': 0.04}],
    'stickers': [
        {'id': 'door', 'view': 'left', 'rect': (2.00, 0.52, 3.20, 0.74), 'mirror': True, 'note': 'empty (unmarked)'},
        {'id': 'hood', 'view': 'top', 'rect': (-0.30, 0.40, 0.30, 1.40), 'note': 'empty (unmarked)'},
        {'id': 'rear', 'view': 'top', 'rect': (-0.40, 4.25, 0.40, 4.62), 'note': 'empty (unmarked)'},
    ],
    'paint': {'hero': ('Gunmetal', '#2E333C'), 'alts': [('Black', '#15171C'), ('Silver', '#C9CED6'), ('Dark red', '#4A1218')],
              'trim': '#1A1D24', 'rim': '#22252C'},
    'options': {},
}

FLEET = [P1, P2, P3, P4, P5, P6, N1, N2, N3, C1, C2, C3]

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
    return out
