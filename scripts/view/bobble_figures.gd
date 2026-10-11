class_name BobbleFigures
extends RefCounted

# The dash bobble head catalogue (interiors build step 10, 2026-10-11; spec:
# interiors doc section 5). Data only: who a figure is and its paint. The
# shapes are built in BobbleHead from the id (simple placeholders; the art
# pass redoes them). Original figures, no licensed characters, no brands.
#
# group "crew": won from beaten rivals (the rule is not built yet).
# group "shop": bought in the shop (not built yet). For the test build every
# figure is pickable. Colours are the ROADMAP palette plus each crew's own.

const NONE := "none"

const SKIN := Color("#D9A878")
const SKIN_PALE := Color("#E8C9A6")
const SKIN_DARK := Color("#8A5A3A")
const BONE := Color("#E9E6DF")
const SILVER := Color("#C9CED6")
const NAVY := Color("#26314D")
const NAVY_DEEP := Color("#1B2A4A")
const SODIUM := Color("#FF8A1F")
const AMBER := Color("#FFC066")
const INK := Color("#15171C")
const RUST := Color("#B8641A")
const PINE := Color("#2B4A3A")
const FUR := Color("#8A6A45")

## Pick order in the pause menu: index 0 is "none", then the crews, then the shop.
const IDS: Array[String] = [
	NONE,
	"kasumi_driver", "diesel_trucker", "gruppe9_driver", "ironbridge_welder",
	"rally_codriver", "topspeed_king", "eurosedan_king", "muscle_king", "pike",
	"dog", "walt", "dave", "cone_face", "hula", "cat", "skeleton", "tiny_mechanic",
]

## name: pause-menu text; group; head: face paint; body: jacket / shirt;
## accent: the figure's second colour (see BobbleHead._fig_*).
const FIGURES := {
	"kasumi_driver": {"name": "Kasumi Run driver", "group": "crew", "head": SKIN, "body": BONE, "accent": SODIUM},
	"diesel_trucker": {"name": "Diesel Row trucker", "group": "crew", "head": SKIN_PALE, "body": RUST, "accent": NAVY},
	"gruppe9_driver": {"name": "Gruppe 9 driver", "group": "crew", "head": SKIN, "body": NAVY, "accent": SILVER},
	"ironbridge_welder": {"name": "Ironbridge welder", "group": "crew", "head": SKIN_DARK, "body": SILVER, "accent": INK},
	"rally_codriver": {"name": "Rally king co-driver", "group": "crew", "head": SKIN, "body": SODIUM, "accent": NAVY},
	"topspeed_king": {"name": "Top-speed king", "group": "crew", "head": SKIN_PALE, "body": NAVY_DEEP, "accent": AMBER},
	"eurosedan_king": {"name": "Euro-sedan king", "group": "crew", "head": SKIN, "body": NAVY, "accent": SILVER},
	"muscle_king": {"name": "Muscle king", "group": "crew", "head": SKIN_DARK, "body": BONE, "accent": SODIUM},
	"pike": {"name": "Pike", "group": "crew", "head": AMBER, "body": NAVY_DEEP, "accent": SODIUM},
	"dog": {"name": "Dog", "group": "shop", "head": FUR, "body": SODIUM, "accent": BONE},
	"walt": {"name": "Walt", "group": "shop", "head": SKIN_PALE, "body": NAVY, "accent": SILVER},
	"dave": {"name": "Dave", "group": "shop", "head": SKIN, "body": PINE, "accent": INK},
	"cone_face": {"name": "Cone with a face", "group": "shop", "head": SODIUM, "body": NAVY, "accent": BONE},
	"hula": {"name": "Hula figure", "group": "shop", "head": SKIN_DARK, "body": SODIUM, "accent": PINE},
	"cat": {"name": "Cat", "group": "shop", "head": SILVER, "body": NAVY, "accent": SODIUM},
	"skeleton": {"name": "Skeleton", "group": "shop", "head": BONE, "body": BONE, "accent": INK},
	"tiny_mechanic": {"name": "Tiny mechanic", "group": "shop", "head": SKIN, "body": SODIUM, "accent": SILVER},
}

static func name_of(id: String) -> String:
	if id == NONE:
		return "None"
	return str(FIGURES.get(id, {}).get("name", id))

## Pause-menu labels in IDS order.
static func names() -> Array[String]:
	var out: Array[String] = []
	for id in IDS:
		out.append(name_of(id))
	return out

## Index in IDS of the id (0, "none", if unknown).
static func index_of(id: String) -> int:
	return maxi(IDS.find(id), 0)
