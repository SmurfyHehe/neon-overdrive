"""Check sheet for a pipeline car: the parts each in its own tint so the cuts
show, the car as it is painted, the hood, doors and trunk swung open on their
hinges, and a shut line up close.

    python tools/car_pipeline/parts_sheet.py p1_coupe
    -> docs/design/pipeline/<id>_parts.png

It builds the car with the Blender backend into a scratch folder (nothing in
assets/ is touched), renders six views with Blender's Workbench (no GPU
features needed, works headless) and lays them out with Pillow. Blender is
found through NEON_BLENDER, then C:/Tools/blender-4.5/blender.exe, then PATH;
see README.md.

The same file is the render script: Blender runs it with `--render`.
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
OUT_DIR = os.path.join(ROOT, 'docs', 'design', 'pipeline')
W, H = 960, 540
# name, eye, target (car space: x right, y up, -z forward), lens mm, tinted, open
SHOTS = [
    ('parts_front', (3.3, 1.5, -4.6), (0, 0.55, 0), 50, True, False, 'every part in its own tint, front'),
    ('parts_rear', (-3.3, 1.5, 4.6), (0, 0.55, 0), 50, True, False, 'every part in its own tint, rear'),
    ('paint_front', (3.3, 1.5, -4.6), (0, 0.55, 0), 50, False, False, 'as painted, closed'),
    ('open_front', (3.3, 1.5, -4.6), (0, 0.55, 0), 50, False, True, 'hood, doors and trunk open'),
    ('open_rear', (-3.3, 1.5, 4.6), (0, 0.55, 0), 50, False, True, 'open, from the rear'),
    ('gap', (1.25, 1.25, -1.45), (0.72, 0.74, -1.2), 85, False, False, 'hood, fender and door shut lines, close'),
]


def find_blender():
    for cand in (os.environ.get('NEON_BLENDER'), 'C:/Tools/blender-4.5/blender.exe', shutil.which('blender')):
        if cand and os.path.isfile(cand):
            return cand
    raise SystemExit('Blender not found: set NEON_BLENDER to blender.exe (see tools/car_pipeline/README.md)')


def render(out_dir):
    """Inside Blender, with the car's .blend open: write one PNG per shot."""
    import bpy
    from mathutils import Vector

    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    sh = scene.display.shading
    sh.light = 'STUDIO'
    sh.show_cavity = True
    sh.cavity_type = 'BOTH'
    sh.show_specular_highlight = True
    sh.show_shadows = False
    scene.display.render_aa = '8'
    scene.render.resolution_x, scene.render.resolution_y = W, H
    scene.world = bpy.data.worlds.new('sheet')
    scene.world.color = (0.012, 0.016, 0.033)        # the palette's dusk navy
    cam_data = bpy.data.cameras.new('sheet')
    cam = bpy.data.objects.new('sheet', cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    car = lambda p: Vector((p[0], -p[2], p[1]))      # car space -> Blender
    hinges = [ob for ob in bpy.data.objects if ob.name.startswith('hinge_') and 'axis' in ob]
    for name, eye, target, lens, tinted, opened, _ in SHOTS:
        sh.color_type = 'RANDOM' if tinted else 'MATERIAL'
        for ob in hinges:
            ax = list(ob['axis'])
            ob.rotation_mode = 'AXIS_ANGLE'
            ang = math.radians(float(ob['open_sign']) * float(ob['open_deg'])) if opened else 0.0
            ob.rotation_axis_angle = (ang, ax[0], -ax[2], ax[1])
        cam.location = car(eye)
        cam.rotation_euler = (car(target) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam_data.lens = lens
        scene.render.filepath = os.path.join(out_dir, name + '.png')
        bpy.ops.render.render(write_still=True)


def main(car_id='p1_coupe'):
    import json
    from PIL import Image, ImageDraw
    blender = find_blender()
    tmp = tempfile.mkdtemp(prefix='neon_parts_sheet_')
    blend = os.path.join(tmp, car_id + '.blend')
    subprocess.check_call([blender, '-b', '--factory-startup', '--python', os.path.join(HERE, 'build_car.py'), '--',
                           car_id, '--out', tmp, '--blend', blend], stdout=subprocess.DEVNULL)
    subprocess.check_call([blender, '-b', blend, '--python', os.path.abspath(__file__), '--', '--render', tmp],
                          stdout=subprocess.DEVNULL)
    with open(os.path.join(tmp, car_id, 'body.json')) as f:
        meta = json.load(f)
    sheet = Image.new('RGB', (W * 3, H * 2 + 44), '#0E1424')
    draw = ImageDraw.Draw(sheet)
    draw.text((12, 14), '%s body.glb: %d parts, %d triangles without the wheels, shut gap %.1f mm, bevel %s mm, backend %s' % (
        car_id, len(meta['parts']), meta['tris_body'], meta['shut']['gap'] * 1000,
        '/'.join('%g' % b for b in meta['bevel_mm']) or 'none', meta['backend']), fill='#FFC066')
    for i, shot in enumerate(SHOTS):
        x, y = (i % 3) * W, 44 + (i // 3) * H
        sheet.paste(Image.open(os.path.join(tmp, shot[0] + '.png')).convert('RGB'), (x, y))
        draw.text((x + 12, y + 10), shot[6], fill='#E9E6DF')
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, '%s_parts.png' % car_id)
    sheet.save(out)
    print(os.path.relpath(out, ROOT))


if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if argv and argv[0] == '--render':
        render(argv[1])
    else:
        main(*argv[:1])
