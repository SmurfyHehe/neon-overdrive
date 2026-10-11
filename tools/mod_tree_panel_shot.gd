extends SceneTree

# Screenshots of the garage's mod tree panel (G3a) in a half-built state, for
# looking at the board without the garage room. Needs the real renderer (not
# --headless). Writes PNGs into the folder given after "--" (default user://).
#
#   Godot_v4.7.2-stable_win64_console.exe --path . -s res://tools/mod_tree_panel_shot.gd -- C:/some/folder

const SaveStore := preload("res://scripts/save/save_store.gd")
const Wallet := preload("res://scripts/core/wallet.gd")
const TreePanel := preload("res://scripts/ui/mod_tree_panel.gd")
const PlayerTune := preload("res://scripts/car/player_tune.gd")

const ROOT := "user://test_mod_tree_panel_shot"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := String(args[0]) if not args.is_empty() else "user://"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	SaveStore.root = ROOT.path_join("saves")
	SaveStore.slot = 0
	SaveStore.select_slot(1)
	PlayerTune.path = ROOT.path_join("player_tune.json")
	SaveStore.save_wallet(0, 9000)
	SaveStore.save_garage([])
	SaveStore.save_mod_tree({})
	root.size = Vector2i(1280, 720)
	var wallet: Node = Wallet.new()
	root.add_child(wallet)
	var panel: Control = TreePanel.new()
	root.add_child(panel)
	panel.open("p1_coupe", wallet)
	wallet.bank = 60000
	for id in ["service", "B", "B1", "A", "suspension_1", "tyres_1", "tyres_2", "brakes_1", "lamps_fixed",
			"short_shifter", "ecu_unlock", "brake_pads", "fog_lamps", "cabin_strip_1"]:
		panel.model.buy(id)
	panel.model.swap_to("B")
	wallet.bank = 2500
	var shots := [["buyable", "B2", ""], ["locked_keystone", "grip", ""], ["swapped_out", "A", ""], ["chassis", "suspension_2", ""],
		["bolt", "cold_air_intake", ""], ["ticket", "brakes_2", "brakes_2"]]
	for shot in shots:
		panel.selected = shot[1]
		panel.ticket = shot[2]
		for i in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out.path_join("mod_tree_panel_%s.png" % shot[0])
		root.get_texture().get_image().save_png(path)
		print("wrote " + path)
	quit(0)
