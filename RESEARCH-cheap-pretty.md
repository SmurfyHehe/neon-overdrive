# Research: how old games looked expensive and ran cheap (2026-09-29)

> **STATUS UPDATE, 2026-10-06: background reading, partly overtaken.** Of the
> "Direct application" list: item 1 (dim cool moonlight key) is built (`bbcb12f`);
> item 4 (roadside detail as MultiMesh: lamps, signs, barriers; no
> `visibility_range` is set) and item 5 (blob shadow under the car, `car_fx.gd`) are
> built in stage A (#84); item 6 (glow) was measured and
> turned on tight (#67). Item 2 (vertex-colour roads) is not approved. **Item 3
> (traffic as MultiMesh) is moot:** traffic shipped in #113 as individual cars
> running the full raycast sim, not instances. The "keep 60 Hz" advice is
> superseded: physics runs at 120 Hz since #110. Written before traffic and audio
> existed; milestone numbers in the intro are the old 11-milestone plan.

Reference notes for Neon Overdrive's art/performance direction. Not a milestone —
background for the environment, traffic, and art passes (roadmap milestones 2-5).

## The one principle

Every trick below is the same idea: **pay for it once, at build time or in the
art, instead of every frame at runtime.** Old hardware couldn't afford per-frame
lighting, per-frame shadows, or distant geometry, so artists moved those costs
into things that are free at runtime — vertex colors, textures, fog, sprites,
and composition.

The modern corollary matters more than the history: a 2026 GPU is fast enough
that we don't *need* these tricks to hit 60fps. We want them because they're
also how you get a **coherent, stylish look on a solo art budget.** The cheap
path and the good-looking path are the same path here.

---

## 1. Bake the light into the art

**Then:** Crash Bandicoot and Spyro painted lighting directly into **vertex
colors** — the mesh ships pre-lit, with darkened crevices and warm pools under
lamps, and the runtime does zero lighting work. Where light needed a hard edge,
artists cut the shadow line into the geometry itself. Games like Spyro even used
vertex-colored skyboxes rather than spending texture memory on one.

**Blob shadows** were near-universal: a dark ellipse sprite under the character
instead of a shadow map. A real shadow-casting light costs an entire extra
render pass; a blob costs one quad.

**Now, in Godot:** `LightmapGI` is "near-free at runtime" for static geometry.
Vertex colors still work and are still nearly free. `StandardMaterial3D` with
`shading_mode = SHADING_MODE_UNSHADED` plus an emission color gives you
something that looks lit while participating in no lighting calculation at all.

**Catch for us:** an endless procedural road can't use baked lightmaps — there's
no static scene to bake. **But we generate our road meshes in code**
(`road_chunk_builder.gd`), which means we can write vertex colors *during
construction*. That's the Spyro trick, available to us for free, and it's the
single highest-leverage lighting idea in this document.

## 2. Darkness and fog are a rendering budget

**Then:** distance fog exists to disguise a short draw distance. Arcade racers
were infamous for "pop-up graphics" — objects appearing out of nothing — and fog
was the standard cover. Silent Hill is the famous case where the workaround
became the identity of the game.

**Night is the strongest version of this.** In daylight you must draw everything
the player can see. At night you only draw what you choose to light, and
everything else is legitimately, diegetically black. The horizon problem solves
itself.

**Now, in Godot:** we already have `fog_density = 0.006`, a gradient
`ProceduralSkyMaterial`, and `camera.far = 400`. That's the right architecture.
What's inconsistent is the **sun**: `light_energy = 1.1` in warm white
(`0.95, 0.86`) is a daylight key light sitting inside a purple night palette.

## 3. Fake the geometry

**Then:** Out Run's entire world is **scaled 2D sprites**. Per Yu Suzuki, the
positions were calculated in 3D and converted back to 2D — the scale and zoom
rate were real perspective math driving flat sprites. Sega's Super Scaler boards
could scale thousands of sprites per second, and that was the whole illusion.
Crowds, trees, and explosions stayed billboards well into the 3D era.

**Impostors** generalize it: pre-render a complex object to an image and show
the image at distance. **LOD** is the same instinct with real geometry.

**Now, in Godot:** `MultiMeshInstance3D` is the direct descendant —
"one MultiMesh with 10,000 instances is one draw call; 10,000 MeshInstance3D
nodes are 10,000 draw calls." Pair it with `visibility_range_begin/end` for hard
cutoffs at 30-60m on clutter, which one guide calls "one of the highest ratio
wins in dense scenes."

(Occlusion culling is the exception that doesn't apply to us — it costs CPU
every frame and pays off in interiors. On an open road with nothing large to
hide behind, it can cost more than it saves.)

## 4. Reuse everything

**Then:** whole cities were built from a handful of modular pieces. Texture
atlases packed many surfaces into one image so the hardware never switched
textures. Meshes were mirrored to halve memory. And **palette swaps** turned one
car or enemy into six.

**Now:** same mesh + same material + per-instance color is essentially free in a
MultiMesh, and every material variant you avoid is draw calls you don't spend.
Mobile guidance targets **under 100 draw calls per frame**; merging materials
into atlases is the standard route there.

## 5. Sell speed with the camera, not the world

Out Run's sense of speed comes from scroll rate and roadside objects whipping
past — not scene complexity. A sparse world moving fast reads as faster than a
dense world moving slowly, and costs less.

Cheap, high-impact: FOV widening with speed, camera shake, screen-edge speed
lines, a scrolling road texture, and a rhythm of emissive roadside posts. Those
are nearly free and they're most of the feel. The original plan (now in ROADMAP.md) already lists
"dynamic camera FOV/shake tied to speed" — that's correctly prioritized.

## 6. Art direction is the cheapest optimization

A **limited palette** and **strong silhouettes** read as deliberate style rather
than as missing detail. High contrast does enormous work: a few genuinely bright
emissive elements against near-black looks richer than a scene of mid-tones. PS1
dithering existed to fake gradients within a tiny color depth, and it gave those
games a texture people now deliberately imitate.

---

## Optimization vs. artifact — don't copy the jank

Worth separating, because "retro 3D" usually means both:

| Genuine technique (steal these) | Hardware artifact (a *choice*, not a win) |
|---|---|
| Vertex-color baked lighting | Vertex wobble / position snapping |
| Billboards, impostors, LOD | Affine texture warping |
| Fog and darkness as draw-distance | 240p resolution, heavy dithering |
| Atlases, modular kits, palette swaps | Bilinear-filtering-off texture crunch |

The agreed direction (ROADMAP.md) commits to **"beautiful low-poly"** — deliberate faceted geometry
with strong lighting, in the vein of *Street-Spec* — explicitly **not**
placeholder boxes and not PS1 jank. So: take the left column, skip the right
column. Faceted geometry is a modern low-poly look, and it's cheap for the same
reasons the old tricks were.

---

## Direct application to Neon Overdrive

Ordered by leverage, against the current code:

1. **Commit the lighting to night.** Drop the warm directional sun to a dim cool
   moonlight key (low energy, blue-violet) and let *emissives* be the light you
   actually see: road markings, signage, streetlights, tail lights, underglow.
   This makes the existing purple sky/fog palette coherent instead of fighting a
   daylight key, and it licenses a much shorter draw distance.

2. **Vertex-color the road chunks at build time.** We already construct these
   meshes in code, so we can bake pools of light under lamps, darker shoulders,
   and curb highlights straight into vertex colors — zero runtime lighting cost,
   and it's the technique that made Spyro's world feel lit on a PS1.

3. **Traffic (milestone 3) should be MultiMesh + palette swap from day one.**
   Two or three car meshes with per-instance color gives real visual variety at
   roughly one draw call. Building traffic as individual nodes is the decision
   that would be expensive to undo later — worth getting right at the start of
   the milestone rather than retrofitting.

4. **Roadside detail via MultiMesh with `visibility_range_end` around 60-120m.**
   Lamp posts, signs, barriers, distant building blocks. This is what will make
   the world feel populated, and it's close to free.

5. **Blob shadow under the player car**, or a single directional shadow with
   `directional_shadow_max_distance = 40` and one cascade. Do not put
   shadow-casting lights on traffic.

6. **Test glow before relying on it.** Bloom is what sells neon, but there's a
   documented severe glow cost on Godot's **Mobile** renderer specifically
   (a reported 120 → 37 fps drop), and `project.godot` currently sets
   `renderer/rendering_method="mobile"`. If it's too expensive, the old-school
   fallback is exactly right: **paint the halo into the emissive texture** so the
   glow is baked art rather than a post-process.

7. **Fake the wet-road reflections.** Vertical smears of light stretched down the
   road under each emissive source, as geometry or texture — not screen-space
   reflections. This is most of the rain-slicked-neon look for almost nothing.

### One piece of standard advice that does NOT apply to us

Mobile guides recommend dropping `physics_ticks_per_second` to 30 because it
"halves physics cost." **Don't.** We run a vendored raycast vehicle controller
(GEVP) whose suspension and tire forces are integrated per physics step —
halving the rate will degrade the exact simcade feel milestone 2 was rewritten
to achieve. Keep 60Hz and find savings in rendering instead.

### How to know if any of this is needed

Godot's **Monitors** tab reports draw calls, frame time, and video memory
directly, and the **Visual Profiler** breaks down GPU time by stage (shadows,
GI, post-processing). Measure before optimizing. The "do we have headroom?"
question is answered below — partly yes, but not in the way "desktop hardware"
suggests.

---

## The target machine (added 2026-09-29)

v1 targets the dev machine and should be measured on it. That's an advantage: the
cost of a bad rendering decision is felt the same day it's made.

| | HP Laptop 15-dy5xxx |
| --- | --- |
| CPU | i5-1235U — 2 P-cores + 8 E-cores, **15 W**, 1.3 GHz base / 4.4 boost |
| GPU | Intel Iris Xe, **80 EU**, no dedicated VRAM |
| RAM | 16 GB DDR4-3200, **dual channel** |
| Display | 1920x1080 @ 60 Hz |
| Godot | v4.7.2-stable, portable exe in `Documents\` |

"Desktop hardware with plenty of headroom" is half right. In raw shading power
this is fine — Iris Xe at 80–96 EU trades blows with a GeForce MX450 and lands
near a GTX 1050 Mobile in synthetics, which is more than a low-poly night racer
needs. The headroom is real. It just isn't where you'd look for it, because the
two actual constraints are not shader throughput:

1. **15 W sustained power.** The chip boosts to 4.4 GHz and cannot hold it. A
   framerate read at minute 1 lies about minute 20. Every measurement below has
   to be taken warm or it isn't a measurement.
2. **Shared memory bandwidth.** There is no dedicated VRAM — CPU and iGPU
   contend for the same DDR4-3200. On integrated graphics bandwidth is what
   kills framerates, so suspect it *before* triangle count, every time. This is
   also why the tricks in this document land harder here than on a desktop with
   a discrete card: vertex colors, atlases, MultiMesh and short draw distance all
   cut bandwidth, not just shader work.

**Budget 8–10 ms per frame, not 16.6.** The spare 6 ms is what keeps minute 20
at 60 fps.

### What this changes about the priorities above

- **Item 6 (test glow) is now a confirmed risk, and it's measurable the moment
  glow exists.** Verified 2026-09-29: the project runs on **Vulkan 1.3.280 /
  Forward Mobile** on this Iris Xe, so godot#98531 applies to this exact
  configuration — and `game.gd` builds its `Environment` with fog but **no
  `glow_enabled` at all yet**. So there is nothing to measure today. Take the
  number in the same sitting glow is switched on during the atmosphere pass,
  before any emissive assets are authored around it: if glow is too expensive,
  halos get painted into textures instead, and that's an art-pipeline decision
  that's cheap now and expensive after a hundred assets exist.
- **Keeping 60 Hz physics is right, and it's the CPU risk.** Only 2 of the 12
  threads are performance cores, and GEVP integrates suspension and tire forces
  per step per vehicle. Player-only is cheap. Milestones 3–4 (traffic, then
  *reactive* traffic) are where this could bite — so traffic cars should not get
  GEVP bodies without a measured reason. ROADMAP already anticipates this for
  police tier count ("capped by actual CPU/engine performance"); it applies to
  traffic density first.
- **Add an internal resolution scale (0.6–1.0) early.** At 1080p on a
  bandwidth-bound iGPU this is the cheapest single lever that exists, and it's
  also what lets the game run on machines weaker than this one.
- **Measure an exported build, warm, on mains power *and* on battery.** The
  editor's own GPU use makes in-editor numbers a fiction, and this chassis
  throttles differently unplugged — which is how people will actually play it.

---

## Sources

- [Retro 3D Art FAQ — Polycount](https://polycount.com/discussion/226167/retro-3d-art-faq-everything-you-need-to-know-to-create-ps1-n64-dreamcast-etc-3d-art)
- [Distance fog — Wikipedia](https://en.wikipedia.org/wiki/Distance_fog)
- [Draw distance — Wikipedia](https://en.wikipedia.org/wiki/Draw_distance)
- [Out Run — Wikipedia](https://en.wikipedia.org/wiki/Out_Run)
- [Sprite Scaling — Giant Bomb](https://www.giantbomb.com/sprite-scaling/3015-7122/)
- [Cheap Rendering Tricks Used in Game Industry — GameDev.net](https://gamedev.net/forums/topic/670401-cheap-rendering-tricks-used-in-game-industry/)
- [Inside Game Development: Using Impostors — 80.lv](https://80.lv/articles/inside-game-development-using-impostors)
- [Godot 3D Optimization Guide 2026 — StraySpark](https://www.strayspark.studio/blog/godot-3d-optimization-guide-2026)
- [Optimizing Godot for Mobile: A Field Guide — slicker.me](https://slicker.me/godot/mobile-optimization.html)
- [Glow extremely slow with Mobile renderer — godotengine/godot#98531](https://github.com/godotengine/godot/issues/98531)
- [Optimizing 3D performance — Godot docs](https://docs.godotengine.org/en/4.4/tutorials/performance/optimizing_3d_performance.html)

For the target-machine section:

- [Intel Core i5-1235U product specifications — Intel](https://www.intel.com/content/www/us/en/products/sku/226266/intel-core-i51235u-processor-12m-cache-up-to-4-40-ghz-with-ipu/specifications.html)
- [Iris Xe vs. MX350 / MX450 / GTX 1050 in synthetic GPU tests — NotebookCheck](https://www.notebookcheck.net/Intel-Iris-Xe-Max-powered-Asus-VivoBook-Flip-14-TP470-in-review-Good-gains-over-Xe-Graphics-G7-96-EUs-MX350-and-GTX-1050-in-synthetic-GPU-tests.512386.0.html)
- [Iris Xe Time Spy results vs. MX450 — WCCFTech](https://wccftech.com/intel-iris-xe-max-gpu-time-spy-benchmarks-trade-blows-with-an-nvidia-mx450/)
- [Renderers (Forward+ / Mobile / Compatibility) — Godot docs](https://docs.godotengine.org/en/4.4/tutorials/rendering/renderers.html)
