#include "crossing_bench.h"
#include "gevp_tyre_native.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_neon_sim(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ClassDB::register_class<GevpTyreNative>();
	ClassDB::register_class<CrossingBench>();
}

void uninitialize_neon_sim(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT neon_sim_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_neon_sim);
	init_obj.register_terminator(uninitialize_neon_sim);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
