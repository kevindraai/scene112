extends SceneTree
const Atmosphere = preload("res://scripts/street_atmosphere.gd")
var checks := 0
func _initialize() -> void:
	for name in ["Apple Software Renderer", "llvmpipe (LLVM 19.1.7, 256 bits)", "softpipe"]:
		if not check(Atmosphere.is_software_gl("gl_compatibility",name), "actual software name " + name): return
	for name in ["Apple M4", "Apple Paravirtual device (Apple5)", "NVIDIA GeForce RTX 4070", "AMD Radeon RX 6800", "Intel Iris Pro", "ANGLE Metal Renderer: Apple Paravirtual device", "Unknown", "", "NVIDIA llvmpipe labelled hardware"]:
		if not check(not Atmosphere.is_software_gl("gl_compatibility",name), "hardware/unknown excluded " + name): return
	for method in ["forward_plus", "mobile", "headless", ""]:
		if not check(not Atmosphere.is_software_gl(method,"Apple Software Renderer"), "nonGL excluded " + method): return
	print("SCENE112_SOFTWARE_CLASSIFICATION_OK checks=", checks, " scope=classification fixtures; no native renderer proof")
	quit(0)
func check(value: bool, description: String) -> bool:
	checks += 1
	if not value:
		push_error(description)
		quit(1)
	return value
