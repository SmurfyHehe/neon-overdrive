# Title and garage: the 3D look (2026-10-14, Fable)

What the first two screens look like today (build 4, branch
claude/project-thread-f2fai6 at 252ce45, shot in the cloud with software
OpenGL, 1280x720) and the smallest changes that make them look great.
Rule from Roy: real-life-based, arcadey, effects exaggerated and fun.
Laptop is CPU-bound: nothing here adds physics, draw calls stay in the tens.

## Title ("Kerbside")

What is there: the player's car at the kerb under one sodium lamp, a long
blank wall with graffiti, litter, a manhole with steam, roaches, rats, cat,
pigeons, stars. All of that is good and stays.

What looks weak (see shots/4_title.png in this folder's thread):

1. **Flat light.** The lamp is one light with no shadow. The car has no
   shadow of its own (a soft dark quad stands in), the lamp post casts none,
   the wheels sit on the road like stickers.
2. **Dry, dead road.** The asphalt is matte (roughness 0.82) so the sodium
   lamp makes a faint smudge instead of a hot pool with a reflection of the car.
3. **No separation.** The car's roof line and far side are the same dark as
   the wall behind it. Nothing lights the car from behind.
4. **Small car.** The car is about a quarter of the picture width, down in
   the corner (camera 9 m back, FOV 48). Roy already picked 55-60 % of the
   frame (1126), but the whole set (manhole, litter lane, poster, piece,
   roach runs) is laid out for the present camera and the tests pin it, so
   the big reframe is its own step.

Smallest changes, in order (step 1 is built in this thread's PR):

| Step | Change | Cost |
|---|---|---|
| 1 (PR) | Lamp casts a real shadow (one spot, 30 fps title). Cool dusk rim light behind the car. Wet asphalt: low roughness so the lamp pools and the car reflects. Camera a little closer and tighter (FOV 48 -> 42). | 1 shadow pass on 1 light, ~30 draw calls; needs a laptop frame check |
| 2 | Reframe: car 55-60 % of width, FOV 30, re-lay the manhole, litter lane, poster and roach runs for the new camera, retune the tests. | none at run time |
| 3 | Depth: far rooftops and a water tower above the wall, three lit windows, the city glow dome behind. | +4 draw calls |
| 4 | Car presentation: headlamps glow faintly, one puddle under the kerb with a sodium streak, dirt from the save on the car. | small |
| 5 | Continue = headlamps on, engine catch, camera push (already yes 1130). | none |

Needs a laptop look: step 1's shadow cost on integrated graphics and whether
the wet road reads as wet, not grey.

## Garage

What is there: a flat navy panel with GARAGE and five buttons
(shots/1_garage.png). No 3D at all. The garage design (notes/garage-design-
2026-10-10.md) is the full bay with five stations; nothing of it is built.

What looks weak: everything. The player's first "home" screen is a settings
page.

Smallest changes, in order:

| Step | Change | Cost |
|---|---|---|
| 1 | A garage bay set, built like the title set (its own small set far below the road, freed on Go out): concrete floor with oil stains, back wall with a shadow board, roller door half up with the dusk street outside, one hanging work lamp over the car with a shadow, the player's own car (same car copy the title uses) at three-quarter front, buttons stay on the left. | 1 shadow light, ~25 draw calls |
| 2 | Life: lamp sways a touch, a fan turns, moths at the lamp, a radio on the bench, Walt's board on the wall where the row already is. | small |
| 3 | Lift camera: Service car raises the lift and the camera looks under; Wash car rolls the car to the door. | none |
| 4 | Light follows the night clock through the roller door (decided 64-71). | none |
| 5 | The five stations and the mod tree (garage-design doc). | large |

Needs a laptop look: the bay's light balance against the title's.

## Not changed

No physics, no new cars, no tuner work. Car paint shader stays the car
thread's.
