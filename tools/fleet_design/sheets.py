"""Compose the B1 design sheets (PNG): one per car, a fleet overview and the
outline check. Run: python sheets.py [car_id ...]"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import car
import cars
import options  # noqa: F401  (attaches the option catalogs)
import render
import views
from render import SHADOW, SKY, SODIUM, AMBER, SILVER, TAIL

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', '..', 'docs', 'design', 'fleet'))
FONT_DIR = '/usr/share/fonts/opentype/inter/'


# Windows has no Inter; Segoe UI is close enough that the sheets stay readable
WIN_FONT_DIR = 'C:/Windows/Fonts/'
WIN_FONTS = {'b': 'segoeuib.ttf', 's': 'seguisb.ttf', 'r': 'segoeui.ttf', 'm': 'segoeui.ttf'}


def F(weight, size):
    name = {'b': 'Inter-Bold.otf', 's': 'Inter-SemiBold.otf', 'r': 'Inter-Regular.otf', 'm': 'Inter-Medium.otf'}[weight]
    if not os.path.isdir(FONT_DIR):
        return ImageFont.truetype(WIN_FONT_DIR + WIN_FONTS[weight], size)
    return ImageFont.truetype(FONT_DIR + name, size)


MUTED = (150, 160, 182)
PANEL = (22, 32, 56)
LINE = (44, 58, 92)
ROLE_NAME = {'player': 'Player car', 'npc': 'Traffic (NPC)', 'cop': 'Police'}
SLOT_NAMES = {
    'front_bumper': 'Front bumper', 'rear_bumper': 'Rear bumper', 'hood': 'Hood', 'skirts': 'Skirts / fenders',
    'spoiler': 'Spoiler', 'wheels': 'Wheels', 'exhaust': 'Exhaust tips', 'stance': 'Ride height', 'lamps': 'Lamps',
    'roof': 'Roof', 'kit': 'Kit', 'trim': 'Trim',
}


def wrap(draw, text, font, width):
    words = text.split()
    lines, cur = [], ''
    for w in words:
        t = (cur + ' ' + w).strip()
        if draw.textlength(t, font=font) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def text_block(draw, xy, text, font, fill, width, gap=6):
    x, y = xy
    for ln in wrap(draw, text, font, width):
        draw.text((x, y), ln, font=font, fill=fill)
        y += font.size + gap
    return y


def panel(sheet, box, label=None):
    d = ImageDraw.Draw(sheet)
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, radius=10, fill=PANEL, outline=LINE, width=2)
    if label:
        d.text((x0 + 14, y0 + 10), label, font=F('s', 17), fill=MUTED)


def paste_in(sheet, img, box, pad=6, top_pad=32):
    x0, y0, x1, y1 = box
    W, H = x1 - x0 - 2 * pad, y1 - y0 - pad - top_pad
    im = img.copy()
    im.thumbnail((W, H), Image.LANCZOS)
    sheet.paste(im, (x0 + pad + (W - im.width) // 2, y0 + top_pad + (H - im.height) // 2))


def colors(D, paint=None):
    return cars.colors_for(D, paint)


def model_colors(m, D, paint=None):
    return render.resolve_colors(m.mesh.mats, colors(D, paint))


def scale_bar(img, scale, x=16, y=None):
    d = ImageDraw.Draw(img)
    y = img.height - 12 if y is None else y
    d.line((x, y, x + scale, y), fill=AMBER, width=3)
    d.line((x, y - 6, x, y + 2), fill=AMBER, width=2)
    d.line((x + scale, y - 6, x + scale, y + 2), fill=AMBER, width=2)
    d.text((x + scale + 8, y - 12), '1 m', font=F('m', 15), fill=AMBER)


def tri_count(m):
    return len(m.mesh) - getattr(m, 'decal_tris', 0)


SCALE = 150  # px per metre on every sheet, so cars compare across sheets


def car_sheet(D, verify=None, critique=None):
    m = car.build(D)
    cols = model_colors(m, D)
    W, H = 2560, 1640
    sheet = Image.new('RGB', (W, H), SHADOW)
    d = ImageDraw.Draw(sheet)

    # ---------------- header
    code = D['id'].split('_')[0].upper()
    d.text((34, 22), f"{code}  {D['label'].upper()}", font=F('b', 52), fill=SILVER)
    d.text((36, 88), f"{ROLE_NAME[D['role']]}  ·  proportions from {D['refs']}  ·  original design, no real makes",
           font=F('m', 22), fill=MUTED)
    text_block(d, (1240, 26), 'Silhouette rule: ' + D['rule'], F('s', 27), AMBER, 1290)

    # ---------------- row 1: side, front, rear night
    side = views.view_image(m, cols, 'side', scale=SCALE, size=(940, 300))
    scale_bar(side, SCALE)
    front = views.view_image(m, cols, 'front', scale=SCALE, size=(380, 300))
    rearn = views.view_image(m, cols, 'rear', mode='night', scale=SCALE, size=(380, 300))
    for box, im, lab in (((30, 140, 990, 480), side, 'SIDE'), ((1005, 140, 1405, 480), front, 'FRONT'),
                         ((1420, 140, 1820, 480), rearn, 'REAR  ·  NIGHT READ')):
        panel(sheet, box, lab)
        paste_in(sheet, im, box)

    # ---------------- row 2: top + chase / traffic-ahead
    top = views.view_image(m, cols, 'top', scale=SCALE, size=(940, 300))
    panel(sheet, (30, 495, 990, 835), 'TOP')
    paste_in(sheet, top, (30, 495, 990, 835))
    if D['role'] == 'player':
        chase = views.view_image(m, cols, 'chase', mode='night', size=(1280, 720), ss=2, crop=(240, 260, 1040, 620))
        lab = 'CHASE CAM (stage A framing)  ·  NIGHT'
    else:
        chase = ahead_view(m, cols)
        lab = 'TRAFFIC AHEAD, 14 m, FROM THE CHASE CAM  ·  NIGHT'
    panel(sheet, (1005, 495, 1820, 835), lab)
    paste_in(sheet, chase, (1005, 495, 1820, 835))

    # ---------------- right column: outline only
    panel(sheet, (1835, 140, 2530, 835), 'OUTLINE ONLY')
    sil_tiles(sheet, m, D, (1835, 140, 2530, 835))

    # ---------------- row 3: 3/4s and builds
    qf = views.view_image(m, cols, 'q_front', size=(700, 420), ss=2)
    qr = views.view_image(m, cols, 'q_rear', size=(700, 420), ss=2)
    panel(sheet, (30, 850, 700, 1250), '3/4 FRONT')
    paste_in(sheet, qf, (30, 850, 700, 1250))
    panel(sheet, (715, 850, 1385, 1250), '3/4 REAR')
    paste_in(sheet, qr, (715, 850, 1385, 1250))
    builds_panel(sheet, D, (1400, 850, 2530, 1250))

    # ---------------- row 4: stickers, parts, colours, budget + critique
    stickers_panel(sheet, D, (30, 1265, 700, 1615))
    parts_panel(sheet, D, (715, 1265, 1385, 1615))
    colour_panel(sheet, D, (1400, 1265, 1900, 1615))
    notes_panel(sheet, D, m, (1915, 1265, 2530, 1615), verify, critique)
    return sheet


def ahead_view(m, cols):
    tris = m.mesh.array() + np.array([0.0, 0.0, -14.0])
    cam = dict(render.VIEWS['chase'])
    img, _ = render.render(tris, m.mesh.mats, cam, 1920, 1080, cols, mode='night', ss=1,
                           extra_layers=views.road_layer)
    return img.crop((660, 380, 1260, 720)).resize((900, 510), Image.LANCZOS)


def sil_tiles(sheet, m, D, box):
    tris = m.mesh.array()
    x0, y0, x1, y1 = box
    specs = [('side', 'side'), ('front', 'front'), ('q_front', '3/4 front'), ('q_rear', '3/4 rear'), ('top', 'top'), ('rear', 'rear')]
    d = ImageDraw.Draw(sheet)
    tiles = []
    for v, lab in specs:
        if v in ('side', 'top'):
            cam = views.ortho_cam(D, v, 70, 420, 150)
            mk = render.silhouette_mask(tris, cam, 420, 150)
        elif v in ('front', 'rear'):
            cam = views.ortho_cam(D, v, 70, 200, 150)
            mk = render.silhouette_mask(tris, cam, 200, 150)
        else:
            cam = dict(render.VIEWS[v])
            mk = render.silhouette_mask(tris, cam, 420, 260)
        im = np.ones(mk.shape + (3,), np.uint8) * np.array(SILVER, np.uint8)
        im[mk] = SHADOW
        tiles.append((Image.fromarray(im), lab))
    # layout: side | front ; 3/4 front | 3/4 rear ; top | rear
    cells = [(x0 + 14, y0 + 40, x0 + 450, y0 + 250), (x0 + 460, y0 + 40, x1 - 14, y0 + 250),
             (x0 + 14, y0 + 255, x0 + 340, y0 + 460), (x0 + 350, y0 + 255, x1 - 14, y0 + 460),
             (x0 + 14, y0 + 465, x0 + 450, y0 + 675), (x0 + 460, y0 + 465, x1 - 14, y0 + 675)]
    for (im, lab), c in zip(tiles, cells):
        cx0, cy0, cx1, cy1 = c
        d.rectangle(c, fill=SILVER)
        t = im.copy()
        t.thumbnail((cx1 - cx0 - 10, cy1 - cy0 - 30), Image.LANCZOS)
        sheet.paste(t, (cx0 + (cx1 - cx0 - t.width) // 2, cy0 + 24 + (cy1 - cy0 - 24 - t.height) // 2))
        d.text((cx0 + 8, cy0 + 4), lab, font=F('s', 15), fill=SHADOW)


def builds_panel(sheet, D, box):
    x0, y0, x1, y1 = box
    blist = options.BUILDS.get(D['id'], {})
    names = [('stock', {})] + list(blist.items())
    title = 'BUILDS  ·  mods change the shape' if D['role'] == 'player' else 'VARIANTS'
    panel(sheet, box, title)
    n = len(names)
    w = (x1 - x0 - 20) // n
    d = ImageDraw.Draw(sheet)
    for k, (name, b) in enumerate(names):
        m = car.build(D, b)
        cols = model_colors(m, D)
        im = views.view_image(m, cols, 'q_front' if D['role'] == 'cop' else 'q_rear', size=(560, 340), ss=2)
        cx0 = x0 + 10 + k * w
        sub = (cx0, y0 + 30, cx0 + w - 6, y1 - 96)
        im.thumbnail((sub[2] - sub[0], sub[3] - sub[1]), Image.LANCZOS)
        sheet.paste(im, (sub[0] + (sub[2] - sub[0] - im.width) // 2, sub[1]))
        d.text((cx0 + 6, y1 - 92), name.upper(), font=F('b', 18), fill=AMBER)
        labels = []
        for slot, opt in b.items():
            labels.append(D['options'][slot][opt]['label'])
        text_block(d, (cx0 + 6, y1 - 68), ', '.join(labels) if labels else 'factory parts', F('r', 14), MUTED, w - 14, gap=2)


def stickers_panel(sheet, D, box):
    x0, y0, x1, y1 = box
    panel(sheet, box, 'STICKER SLOTS (exactly 4, fixed)')
    m = car.build(D, stickers=True)
    # neutral paint so the amber slots always show
    cols = render.resolve_colors(m.mesh.mats, dict(colors(D), paint='#4A505B', paint2='#6B7280', roof='#4A505B'))
    a = views.view_image(m, cols, 'q_front', size=(520, 330), ss=2)
    b = views.view_image(m, cols, 'q_rear', size=(520, 330), ss=2)
    w = (x1 - x0 - 30) // 2
    for k, im in enumerate((a, b)):
        im.thumbnail((w, 190), Image.LANCZOS)
        sheet.paste(im, (x0 + 10 + k * (w + 10), y0 + 34))
    d = ImageDraw.Draw(sheet)
    y = y0 + 232
    for i, st in enumerate(D['stickers']):
        where = {'left': 'both doors (mirrored)' if st.get('mirror') else 'left door', 'top': 'from above',
                 'rear': 'from behind'}[st['view']]
        if st['id'] == 'sun':
            where = 'across the top of the windshield'
        note = st.get('note') or st['id']
        d.text((x0 + 14, y), f"{i + 1}  {st['id']}: {note}, {where}", font=F('m', 17), fill=SILVER)
        y += 24


def parts_panel(sheet, D, box):
    x0, y0, x1, y1 = box
    panel(sheet, box, 'SWAPPABLE PARTS' if D['role'] == 'player' else 'VARIANT PARTS')
    d = ImageDraw.Draw(sheet)
    y = y0 + 40
    for slot, opts in D['options'].items():
        labels = [o['label'] for o in opts.values()]
        d.text((x0 + 14, y), SLOT_NAMES.get(slot, slot), font=F('s', 17), fill=AMBER)
        y = text_block(d, (x0 + 175, y), '  ·  '.join(labels), F('r', 16), SILVER, x1 - x0 - 190, gap=3) + 6
        if y > y1 - 20:
            break


def colour_panel(sheet, D, box):
    x0, y0, x1, y1 = box
    panel(sheet, box, 'COLOUR SCHEME')
    d = ImageDraw.Draw(sheet)
    p = D['paint']
    rows = []
    if 'livery' in p:
        rows = [('Body', p['livery']['paint']), ('Doors + roof', p['livery']['paint2']), ('Light bar', '#E5262B'),
                ('Light bar', '#2E4FD8'), ('Trim', '#1A1D24')]
    elif p.get('traffic'):
        rows = [(n, h) for n, h, w in cars.TRAFFIC_PAINTS[:6]] + [('(+3 more)', None)]
    else:
        rows = [('Hero: ' + p['hero'][0], p['hero'][1])] + [(n, h) for n, h in p['alts']]
        rows.append(('Trim', p.get('trim', '#1A1D24')))
        rows.append(('Wheels', p.get('rim', '#C9CED6')))
    y = y0 + 42
    for name, hx in rows:
        if hx:
            d.rounded_rectangle((x0 + 14, y, x0 + 54, y + 24), radius=5, fill=render.hexc(hx), outline=LINE)
            d.text((x0 + 66, y + 1), f'{name}', font=F('m', 17), fill=SILVER)
            d.text((x1 - 100, y + 1), hx.upper(), font=F('r', 15), fill=MUTED)
        else:
            d.text((x0 + 66, y + 1), name, font=F('r', 15), fill=MUTED)
        y += 32
    d.text((x0 + 14, y1 - 30), 'Lights: tail #E5262B · head warm white · amber #FFC066', font=F('r', 14), fill=MUTED)


def notes_panel(sheet, D, m, box, verify, critique):
    x0, y0, x1, y1 = box
    panel(sheet, box, 'BUDGET  ·  EXHAUST  ·  OUTLINE CHECK')
    d = ImageDraw.Draw(sheet)
    budget = {'player': 10000, 'cop': 6000, 'npc': 4000}[D['role']]
    full = car.build(D, list(options.BUILDS.get(D['id'], {'x': {}}).values())[-1])
    y = y0 + 40
    y = text_block(d, (x0 + 14, y), f"Proxy: {tri_count(m):,} tris stock, {tri_count(full):,} heaviest build. Target {budget:,} "
                   f"(measure on the laptop in B2). Plan: one merged mesh, 3 surfaces + 1 wheel mesh.", F('r', 16), SILVER,
                   x1 - x0 - 28, gap=3) + 8
    tips = m.meta['exhaust_tips']
    pos = '; '.join(f"({t['pos'][0]:+.2f}, {t['pos'][1]:.2f}, {t['pos'][2]:+.2f})" for t in tips)
    y = text_block(d, (x0 + 14, y), f"Exhaust (stock): {len(tips)} tip(s) at x, y, z m {pos}. Per-option tips in fleet.json.",
                   F('r', 16), SILVER, x1 - x0 - 28, gap=3) + 8
    if critique:
        y = text_block(d, (x0 + 14, y), critique, F('m', 16), AMBER, x1 - x0 - 28, gap=3) + 6
    if verify:
        text_block(d, (x0 + 14, y), verify, F('r', 15), MUTED, x1 - x0 - 28, gap=3)


def main(ids=None):
    os.makedirs(os.path.join(OUT, 'sheets'), exist_ok=True)
    vpath = os.path.join(OUT, 'verify.json')
    verify = json.load(open(vpath)) if os.path.exists(vpath) else {}
    import critique as C
    for D in cars.FLEET:
        if ids and D['id'] not in ids:
            continue
        v = verify.get('per_car', {}).get(D['id'])
        img = car_sheet(D, v, C.CRITIQUE.get(D['id']))
        path = os.path.join(OUT, 'sheets', D['id'] + '.png')
        img.save(path, optimize=True)
        print(path, flush=True)


if __name__ == '__main__':
    main(sys.argv[1:] or None)


FAMILY = [('PLAYER FLEET', 'player', 'low, wide, wheels fill the arches; one hero shape cue each'),
          ('TRAFFIC', 'npc', 'taller, softer, small wheels in big arch gaps; they recede so the player pops'),
          ('POLICE', 'cop', 'big and upright; every one carries a police tell in its outline')]


def hero_shot(D, size=(760, 470), build=None, view='q_front'):
    """3/4 render cropped tight around the car."""
    m = car.build(D, build)
    cols = model_colors(m, D)
    cam = dict(render.VIEWS[view])
    W, H = size
    ss = 2
    img, cov = render.render(m.mesh.array(), m.mesh.mats, cam, W, H, cols, mode='shaded', ss=ss)
    ys, xs = np.nonzero(cov)
    pad = 18
    box = (max(xs.min() // ss - pad, 0), max(ys.min() // ss - pad, 0), min(xs.max() // ss + pad, W), min(ys.max() // ss + pad + 10, H))
    return img.crop(box)


def overview():
    W, H = 2560, 1520
    sheet = Image.new('RGB', (W, H), SHADOW)
    d = ImageDraw.Draw(sheet)
    d.text((34, 22), 'NEON OVERDRIVE  ·  FLEET DESIGN SHEET (STAGE B1)', font=F('b', 50), fill=SILVER)
    d.text((36, 86), '12 original cars, real-inspired proportions  ·  Amber vs. Dusk  ·  design proxies: the game models '
                     'are built from the same numbers in B2 and D', font=F('m', 22), fill=MUTED)
    tile_w = (W - 60 - 5 * 12) // 6
    rows = [[('PLAYER FLEET', 'player')], [('TRAFFIC', 'npc'), ('POLICE', 'cop')]]
    y = 135
    for row in rows:
        k = 0
        fams = []
        for title, role in row:
            fams += [(title, role, D) for D in cars.FLEET if D['role'] == role]
        seen = set()
        for i, (title, role, D) in enumerate(fams):
            x = 30 + i * (tile_w + 12)
            if title not in seen:
                tag = [t for t in FAMILY if t[1] == role][0][2]
                d.text((x + 4, y), title, font=F('b', 26), fill=AMBER)
                tw = d.textlength(title, font=F('b', 26))
                text_block(d, (x + tw + 18, y + 5), tag, F('m', 17), MUTED, 3 * (tile_w + 12) - tw - 40, gap=1)
                seen.add(title)
        y += 58
        for i, (title, role, D) in enumerate(fams):
            x = 30 + i * (tile_w + 12)
            box = (x, y, x + tile_w, y + 375)
            panel(sheet, box)
            im = hero_shot(D)
            im.thumbnail((tile_w - 16, 250), Image.LANCZOS)
            sheet.paste(im, (x + (tile_w - im.width) // 2, y + 10 + (250 - im.height) // 2))
            code = D['id'].split('_')[0].upper()
            d.text((x + 12, y + 270), f"{code}  {D['label']}", font=F('b', 21), fill=SILVER)
            text_block(d, (x + 12, y + 302), D['rule'], F('r', 15), MUTED, tile_w - 24, gap=2)
        y += 395
    # side lineup at true scale (outline only)
    d.text((34, y), 'SIDE OUTLINES AT TRUE SCALE', font=F('b', 26), fill=AMBER)
    d.text((W - 660, y + 6), 'sodium = player  ·  silver = traffic  ·  blue = police (outline colour only)', font=F('r', 16), fill=MUTED)
    y += 44
    sc = 62
    x = 34
    row_y = y
    for D in cars.FLEET:
        m = car.build(D)
        tris = m.mesh.array()
        w = int(D['L'] * sc) + 24
        cam = views.ortho_cam(D, 'side', sc, w, 136, ground_px=8)
        mk = render.silhouette_mask(tris, cam, w, 136)
        im = np.ones(mk.shape + (3,), np.uint8) * np.array(SHADOW, np.uint8)
        col = {'player': SODIUM, 'npc': SILVER, 'cop': (110, 140, 220)}[D['role']]
        im[mk] = col
        if x + w > W - 30:
            x = 34
            row_y += 168
        sheet.paste(Image.fromarray(im), (x, row_y))
        d.text((x + 6, row_y + 138), D['id'].split('_')[0].upper(), font=F('s', 16), fill=MUTED)
        x += w + 14
    path = os.path.join(OUT, 'fleet_overview.png')
    sheet.save(path, optimize=True)
    print(path)


def outline_check(verify):
    import metrics
    allm = {D['id']: metrics.masks_for(car.build(D)) for D in cars.FLEET}
    metrics.crop_union(allm, 'ahead')
    ids = [D['id'] for D in cars.FLEET]
    W, H = 2560, 1800
    sheet = Image.new('RGB', (W, H), SHADOW)
    d = ImageDraw.Draw(sheet)
    d.text((34, 22), 'OUTLINE CHECK  ·  RECOGNIZABLE BY OUTLINE ALONE?', font=F('b', 46), fill=SILVER)
    d.text((36, 80), 'Same scale within each row. In each blind round a fresh agent that never saw the designs matched shuffled, '
                     'unlabeled silhouettes to the 12 class names (results at the bottom).', font=F('m', 21), fill=MUTED)
    rows = [('side', 'SIDE', 6), ('front', 'FRONT  (the rear outline is its mirror)', 12), ('q_front', '3/4 FRONT', 12),
            ('q_rear', '3/4 REAR', 12), ('top', 'TOP', 6), ('ahead', 'TRAFFIC AHEAD, 14 m, FROM THE CHASE CAM', 12)]
    y = 122
    gap = 8
    for v, lab, per_row in rows:
        d.text((34, y), lab, font=F('s', 18), fill=AMBER)
        y += 26
        tw = (W - 68 - (per_row - 1) * gap) // per_row
        th = 118 if per_row == 6 else 150
        for k, cid in enumerate(ids):
            if k and k % per_row == 0:
                y += th + 22
            x = 34 + (k % per_row) * (tw + gap)
            mk = allm[cid][v]
            im = np.ones(mk.shape + (3,), np.uint8) * np.array(SILVER, np.uint8)
            im[mk] = SHADOW
            t = Image.fromarray(im)
            t.thumbnail((tw - 8, th - 8), Image.LANCZOS)
            d.rectangle((x, y, x + tw, y + th), fill=SILVER)
            sheet.paste(t, (x + (tw - t.width) // 2, y + (th - t.height) // 2))
            d.text((x + 4, y + th + 2), cid.split('_')[0].upper(), font=F('s', 14), fill=MUTED)
        y += th + 30
    if verify:
        d.text((34, y), 'BLIND TEST RESULTS', font=F('b', 26), fill=AMBER)
        y += 40
        cols_x = [34, 300, 470, 640, 810, 980, 1150, 1370]
        heads = ['', 'side', 'front', '3/4 front', '3/4 rear', 'top', 'traffic ahead', 'all 72']
        for x, h in zip(cols_x, heads):
            d.text((x, y), h, font=F('s', 19), fill=MUTED)
        y += 30
        keys = ['side', 'front', 'front_34', 'rear_34', 'top', 'ahead']
        for r, lab in (('r1', 'Round 1: sure'), ('r2', 'Round 2: sure'), ('r3', 'Round 3 (final): sure')):
            R = verify['rounds'][r]
            vals = [str(R['per_view_sure'][k]) + '/12' for k in keys] + [f"{R['sure_correct']}/72"]
            d.text((cols_x[0], y), lab, font=F('m', 19), fill=SILVER)
            for x, val in zip(cols_x[1:], vals):
                d.text((x, y), val, font=F('m', 19), fill=SILVER)
            y += 28
        d.text((cols_x[0], y), 'Named correctly', font=F('m', 19), fill=SILVER)
        for x in cols_x[1:-1]:
            d.text((x, y), '12/12', font=F('m', 19), fill=SILVER)
        d.text((cols_x[-1], y), '72/72 every round', font=F('m', 19), fill=SILVER)
        y += 40
        x2 = 1700
        yy = y - 40 - 28 * 4 - 30
        d.text((x2, yy), 'Audit round, sure per car (of 9 views)' if 'audit' in verify else 'Final round, sure per car (of 6 views)',
               font=F('s', 19), fill=MUTED)
        yy += 30
        pc = verify['per_car']
        order = sorted(pc.items(), key=lambda kv: -int(kv[1].split('sure in ')[1].split('/')[0]))
        for i, (cid, txt) in enumerate(order):
            n = txt.split('sure in ')[1].rstrip('.')
            col = i // 6
            d.text((x2 + col * 420, yy + (i % 6) * 26), f"{cid.split('_')[0].upper()}  {cid.split('_')[1]}: {n}", font=F('m', 18), fill=SILVER)
        for line in verify.get('summary', [])[3:]:
            d.text((34, y), line, font=F('r', 18), fill=MUTED)
            y += 26
    path = os.path.join(OUT, 'outline_check.png')
    sheet.save(path, optimize=True)
    print(path)
