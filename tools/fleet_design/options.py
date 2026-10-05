"""Per-car swappable parts (slots -> options) and example builds."""
import mods as M
from cars import P1, P2, P3, P4, P5, P6, N1, N2, N3, C1, C2, C3

STOCK = {'label': 'Stock', 'ops': []}


def _wheel_set(stock_label, *others):
    d = {'stock': {'label': stock_label, 'ops': []}}
    for key, opt in others:
        d[key] = opt
    return d


def _stance():
    return {'stock': STOCK, 'lowered': M.stance(0.03, 'Lowered 3 cm'), 'slammed': M.stance(0.055, 'Slammed 5.5 cm')}


# ------------------------------------------------------------------ P1
P1['options'] = {
    'front_bumper': {'stock': STOCK, 'lip': M.lip(P1), 'race': M.race_front(P1)},
    'rear_bumper': {'stock': STOCK, 'diffuser': M.diffuser(P1)},
    'hood': {'stock': STOCK, 'vented': M.vented_hood(P1, 0.55, 1.40)},
    'skirts': {'stock': STOCK, 'skirts': M.skirts(P1), 'widebody': M.widebody(P1)},
    'spoiler': {'stock': {'label': 'Hoop wing', 'ops': []}, 'ducktail': M.ducktail(P1, 0.05),
                'gt': M.gt_wing(P1, 0.30), 'none': M.no_spoiler('Clean deck')},
    'lamps': {'stock': {'label': 'Pop-ups', 'ops': []},
              'fixed': {'label': 'Fixed-lamp nose', 'ops': [
                  {'op': 'remove', 'tag': 'popups'},
                  {'op': 'decal', 'decal': {'view': 'front', 'rect': (0.40, 0.40, 0.76, 0.48), 'mat': 'head', 'mirror': True}}]}},
    'wheels': _wheel_set('5-spoke', ('mesh', M.wheels('mesh', 'Mesh', 0.74)), ('dish', M.wheels('dish', 'Deep dish', 0.74)),
                         ('six', M.wheels('6spoke', '6-spoke gold', 0.74, 'rim_gold'))),
    'exhaust': {'stock': {'label': 'Dual (split)', 'ops': []}, 'single': M.exhaust(P1, 'single'), 'quad': M.exhaust(P1, 'quad', 0.042)},
    'stance': _stance(),
}
for p in P1['parts']:
    if p['type'] == 'popups':
        p['tag'] = 'popups'

# ------------------------------------------------------------------ P2
P2['options'] = {
    'front_bumper': {'stock': STOCK, 'lip': M.lip(P2), 'race': M.race_front(P2)},
    'rear_bumper': {'stock': STOCK, 'diffuser': M.diffuser(P2)},
    'hood': {'stock': STOCK, 'vented': M.vented_hood(P2, 0.40, 1.10)},
    'skirts': {'stock': STOCK, 'skirts': M.skirts(P2), 'widebody': M.widebody(P2, 0.07)},
    'spoiler': {'stock': {'label': 'Roof spoiler', 'ops': []},
                'big': {'label': 'Big roof wing', 'ops': [
                    {'op': 'remove', 'tag': 'spoiler'},
                    {'op': 'add', 'part': {'type': 'roof_spoiler', 'tag': 'spoiler', 's0': 3.40, 's1': 3.98, 'y0': 1.35,
                                           'y1': 1.31, 'span': 1.32, 'thick': 0.055, 'brake_light': True}}]},
                'none': M.no_spoiler()},
    'wheels': _wheel_set('6-spoke', ('turbofan', M.wheels('turbofan', 'Turbofan', 0.72)), ('mesh', M.wheels('mesh', 'Mesh', 0.74)),
                         ('split', M.wheels('split', 'Split 5-spoke', 0.76, 'rim_dark'))),
    'exhaust': {'stock': {'label': 'Dual (one side)', 'ops': []}, 'center': M.exhaust(P2, 'center'), 'dual': M.exhaust(P2, 'dual', 0.04)},
    'stance': _stance(),
}

# ------------------------------------------------------------------ P3
P3['options'] = {
    'front_bumper': {'stock': STOCK, 'lip': M.lip(P3), 'race': M.race_front(P3)},
    'rear_bumper': {'stock': STOCK, 'diffuser': M.diffuser(P3)},
    'hood': {'stock': STOCK, 'vented': M.vented_hood(P3, 0.45, 1.30)},
    'skirts': {'stock': STOCK, 'skirts': M.skirts(P3), 'widebody': M.widebody(P3)},
    'spoiler': {'stock': {'label': 'Pedestal wing', 'ops': []}, 'gt': M.gt_wing(P3, 0.34, chord=0.34, label='GT wing'),
                'ducktail': M.ducktail(P3, 0.04, 'Lip (sleeper)'), 'none': M.no_spoiler()},
    'wheels': _wheel_set('10-spoke bronze', ('mesh', M.wheels('mesh', 'Mesh gold', 0.74, 'rim_gold')),
                         ('six', M.wheels('6spoke', '6-spoke', 0.74)), ('dish', M.wheels('dish', 'Deep dish', 0.74))),
    'exhaust': {'stock': {'label': 'Single', 'ops': []}, 'center': M.exhaust(P3, 'center'), 'dual': M.exhaust(P3, 'dual'),
                'quad': M.exhaust(P3, 'quad', 0.042)},
    'stance': _stance(),
}

# ------------------------------------------------------------------ P4
P4['parts'] = [dict(p, tag='hoops') if p['type'] == 'rollhoops' else p for p in P4['parts']]
P4['options'] = {
    'roof': {'stock': {'label': 'Open', 'ops': []},
             'hardtop': {'label': 'Hardtop', 'ops': [
                 {'op': 'remove', 'tag': 'hoops'},
                 {'op': 'open', 'value': []},
                 {'op': 'cabin', 'values': {'R': 1.95, 'C': 2.34, 'D': 1.88, 'pillars': []}},
                 {'op': 'curve', 'curve': 'top', 'keys': [(1.30, 1.12), (1.95, 1.13), (2.34, 0.81)]}]},
             'rollbar': {'label': 'Roll bar', 'ops': [
                 {'op': 'remove', 'tag': 'hoops'},
                 {'op': 'add', 'part': {'type': 'bedbar', 's': 2.20, 'h': 1.13, 'x': 0.44}}]}},
    'front_bumper': {'stock': STOCK, 'lip': M.lip(P4)},
    'spoiler': {'stock': {'label': 'None', 'ops': []}, 'ducktail': M.ducktail(P4, 0.04),
                'wing': M.gt_wing(P4, 0.17, chord=0.24, label='Small wing')},
    'skirts': {'stock': STOCK, 'skirts': M.skirts(P4), 'widebody': M.widebody(P4, 0.07)},
    'wheels': _wheel_set('5-spoke', ('mesh', M.wheels('mesh', 'Mesh', 0.72)), ('dish', M.wheels('dish', 'Deep dish', 0.72)),
                         ('steel', M.wheels('steel', 'Steelies', 0.70))),
    'exhaust': {'stock': {'label': 'Single', 'ops': []}, 'center': M.exhaust(P4, 'center', 0.035), 'dual': M.exhaust(P4, 'dual', 0.034)},
    'stance': _stance(),
}

# ------------------------------------------------------------------ P5
P5['options'] = {
    'hood': {'stock': {'label': 'Cowl scoop', 'ops': []},
             'shaker': M.scoop(P5, 0.98, 1.42, 0.44, 0.17, 'Shaker scoop'),
             'flat': M.flat_hood('Flat hood (sleeper)')},
    'front_bumper': {'stock': STOCK, 'chin': M.lip(P5)},
    'spoiler': {'stock': {'label': 'Ducktail', 'ops': []},
                'drag': M.gt_wing(P5, 0.24, chord=0.30, label='Drag wing'),
                'smooth': {'label': 'Smooth deck', 'ops': [{'op': 'curve', 'curve': 'top', 'keys': [(5.20, 1.00), (5.27, 0.99)]}]}},
    'skirts': {'stock': STOCK, 'skirts': M.skirts(P5)},
    'wheels': _wheel_set('Deep dish', ('five', M.wheels('5spoke', '5-spoke', 0.74)), ('mono', M.wheels('mono', 'Monoblock black', 0.76, 'rim_dark')),
                         ('steel', M.wheels('steel', 'Steelies (sleeper)', 0.70))),
    'exhaust': {'stock': {'label': 'Dual (split)', 'ops': []}, 'side': M.exhaust(P5, 'side', 0.05), 'quad': M.exhaust(P5, 'quad', 0.046)},
    'stance': _stance(),
}

# ------------------------------------------------------------------ P6
for p in P6['parts']:
    if p['type'] == 'roof_rails':
        p['tag'] = 'rack'
P6['options'] = {
    'kit': {'stock': {'label': 'Roof rack', 'ops': []},
            'rally': {'label': 'Rally lamp pod', 'ops': [
                {'op': 'add', 'part': {'type': 'lightpod', 's': -0.03, 'y': 0.62, 'w': 0.96, 'n': 4}}]},
            # keeps low rails: with the whole rack off and lowered, P6 read as
            # the hot hatch from 7 angles (B1 audit, tests/fleet_silhouette_sweep.gd)
            'street': {'label': 'Street (crossbars off)', 'ops': [
                {'op': 'remove', 'tag': 'rack'},
                {'op': 'add', 'part': {'type': 'roof_rails', 'tag': 'rack', 's0': 2.05, 's1': 3.75, 'x': 0.60, 'h': 0.07, 'bars': []}}]}},
    'front_bumper': {'stock': STOCK, 'lip': M.lip(P6)},
    'hood': {'stock': STOCK, 'scoop': M.scoop(P6, 0.45, 1.00, 0.50, 0.06, 'Hood scoop')},
    'skirts': {'stock': {'label': 'Cladding', 'ops': []},
               'mudflaps': {'label': 'Mud flaps', 'ops': [{'op': 'add', 'part': {'type': 'mudflaps'}}]}},
    'spoiler': {'stock': {'label': 'Roof spoiler', 'ops': []},
                'big': {'label': 'Big roof wing', 'ops': [
                    {'op': 'remove', 'tag': 'spoiler'},
                    {'op': 'add', 'part': {'type': 'roof_spoiler', 'tag': 'spoiler', 's0': 3.70, 's1': 4.16, 'y0': 1.54,
                                           'y1': 1.52, 'span': 1.40, 'thick': 0.05}}]}},
    'wheels': _wheel_set('5-spoke dark', ('rally', M.wheels('6spoke', 'Rally 6-spoke gold', 0.66, 'rim_gold')),
                         ('mesh', M.wheels('mesh', 'Mesh', 0.70))),
    'exhaust': {'stock': {'label': 'Dual (centre)', 'ops': []}, 'center': M.exhaust(P6, 'center', 0.05)},
    'stance': {'stock': STOCK, 'lowered': M.stance(0.045, 'Street-lowered 4.5 cm'), 'raised': M.stance(-0.03, 'Gravel-raised 3 cm')},
}

# ------------------------------------------------------------------ NPC trims
N1['options'] = {
    'trim': {'stock': {'label': 'Base', 'ops': []},
             'sport': {'label': 'Sport', 'ops': M.lip(N1)['ops'] + M.wheels('5spoke', '5-spoke', 0.70)['ops'] +
                       [{'op': 'add', 'part': {'type': 'lip', 's0': 4.58, 's1': 4.74, 'y': 1.11, 'span': 1.30, 'h': 0.03}}]},
             'taxi': {'label': 'Taxi', 'ops': [
                 {'op': 'add', 'part': {'type': 'box', 's': 2.70, 'xy': (0.0, 1.56), 'size': (0.56, 0.14, 0.20), 'mat': 'turn'}}]}},
}
N2['options'] = {
    'trim': {'stock': {'label': 'Base', 'ops': []},
             'sport': {'label': 'Sport', 'ops': M.wheels('6spoke', '6-spoke', 0.70)['ops'] + [
                 {'op': 'add', 'part': {'type': 'roof_spoiler', 's0': 3.60, 's1': 3.82, 'y0': 1.53, 'y1': 1.49, 'span': 1.20}}]},
             'rack': {'label': 'Roof rack', 'ops': [
                 {'op': 'add', 'part': {'type': 'roof_rails', 's0': 2.00, 's1': 3.55, 'x': 0.56, 'h': 0.06, 'bars': [2.30, 3.20]}}]}},
}
N3['options'] = {
    'trim': {'stock': {'label': 'Open bed', 'ops': []},
             'covered': {'label': 'Bed cover', 'ops': [{'op': 'open', 'value': []}]},
             'sportsbar': {'label': 'Sports bar', 'ops': [{'op': 'add', 'part': {'type': 'bedbar', 's': 3.55, 'h': 1.62, 'x': 0.78}}]}},
}

# ------------------------------------------------------------------ cop variants
for c in (C1, C2):
    for p in c['parts']:
        if p['type'] == 'pushbar':
            p['tag'] = 'pushbar'
        if p['type'] == 'lightbar':
            p['tag'] = 'lightbar'
C1['options'] = {
    'kit': {'stock': {'label': 'Full light bar + push bar', 'ops': []},
            'lowpro': {'label': 'Low-profile bar', 'ops': [
                {'op': 'remove', 'tag': 'lightbar'},
                {'op': 'add', 'part': {'type': 'lightbar', 'tag': 'lightbar', 's': 3.00, 'y': 1.47, 'w': 1.20, 'depth': 0.22, 'h': 0.05, 'segments': 8, 'pattern': 'alt'}}]},
            'nobar': {'label': 'No push bar', 'ops': [{'op': 'remove', 'tag': 'pushbar'}]}},
}
C2['options'] = {
    'kit': {'stock': {'label': 'Full light bar + push bar', 'ops': []},
            'nobar': {'label': 'No push bar', 'ops': [{'op': 'remove', 'tag': 'pushbar'}]}},
}
C3['options'] = {
    'kit': {'stock': {'label': 'Unmarked', 'ops': []},
            'pursuit': {'label': 'Pursuit pack (push bar)', 'ops': [
                {'op': 'add', 'part': {'type': 'pushbar', 's': -0.10, 'y0': 0.28, 'y1': 0.80, 'w': 0.80}}]}},
}

# ------------------------------------------------------------------ builds
BUILDS = {
    'p1_coupe': {
        'street': {'front_bumper': 'lip', 'skirts': 'skirts', 'spoiler': 'ducktail', 'wheels': 'mesh', 'exhaust': 'single', 'stance': 'lowered'},
        'full': {'front_bumper': 'race', 'rear_bumper': 'diffuser', 'hood': 'vented', 'skirts': 'widebody', 'spoiler': 'gt',
                 'lamps': 'fixed', 'wheels': 'six', 'exhaust': 'quad', 'stance': 'slammed'},
    },
    'p2_hothatch': {
        'street': {'front_bumper': 'lip', 'skirts': 'skirts', 'wheels': 'turbofan', 'exhaust': 'center', 'stance': 'lowered'},
        'full': {'front_bumper': 'race', 'rear_bumper': 'diffuser', 'hood': 'vented', 'skirts': 'widebody', 'spoiler': 'big',
                 'wheels': 'split', 'exhaust': 'dual', 'stance': 'slammed'},
    },
    'p3_tuner': {
        'street': {'front_bumper': 'lip', 'spoiler': 'ducktail', 'wheels': 'mesh', 'exhaust': 'center', 'stance': 'lowered'},
        'full': {'front_bumper': 'race', 'rear_bumper': 'diffuser', 'hood': 'vented', 'skirts': 'widebody', 'spoiler': 'gt',
                 'wheels': 'six', 'exhaust': 'quad', 'stance': 'slammed'},
    },
    'p4_kei': {
        'street': {'roof': 'hardtop', 'front_bumper': 'lip', 'spoiler': 'ducktail', 'wheels': 'mesh', 'stance': 'lowered'},
        'full': {'roof': 'rollbar', 'skirts': 'widebody', 'spoiler': 'wing', 'wheels': 'dish', 'exhaust': 'dual', 'stance': 'slammed'},
    },
    'p5_muscle': {
        'street': {'hood': 'shaker', 'wheels': 'five', 'exhaust': 'side', 'stance': 'lowered'},
        'full': {'hood': 'shaker', 'front_bumper': 'chin', 'spoiler': 'drag', 'skirts': 'skirts', 'wheels': 'mono', 'exhaust': 'quad', 'stance': 'slammed'},
    },
    'p6_crossover': {
        'street': {'kit': 'street', 'front_bumper': 'lip', 'hood': 'scoop', 'wheels': 'mesh', 'stance': 'lowered'},
        'full': {'kit': 'rally', 'skirts': 'mudflaps', 'hood': 'scoop', 'spoiler': 'big', 'wheels': 'rally', 'exhaust': 'center', 'stance': 'raised'},
    },
    'n1_commuter': {'sport': {'trim': 'sport'}, 'taxi': {'trim': 'taxi'}},
    'n2_cityhatch': {'sport': {'trim': 'sport'}, 'rack': {'trim': 'rack'}},
    'n3_pickup': {'covered': {'trim': 'covered'}, 'sportsbar': {'trim': 'sportsbar'}},
    'c1_patrol': {'lowpro': {'kit': 'lowpro'}, 'nobar': {'kit': 'nobar'}},
    'c2_patrolsuv': {'nobar': {'kit': 'nobar'}},
    'c3_interceptor': {'pursuit': {'kit': 'pursuit'}},
}
