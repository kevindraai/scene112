extends SceneTree
const A = preload("res://scripts/street_atmosphere.gd")
var checks:=0
func _initialize():
	for adapter:String in ["Apple Software Renderer","APPLE SOFTWARE RENDERER","Apple Software Renderer 4.1"]:_check(A.is_apple_software_basic("gl_compatibility",adapter),"specific Apple software classification")
	for adapter:String in ["llvmpipe (LLVM 19.1.7, 256 bits)","softpipe","Apple M4","Apple Paravirtual device (Apple5)","Intel Iris Pro","NVIDIA GeForce RTX 4070","AMD Radeon RX 6800","ANGLE Metal Renderer: Apple Paravirtual device","Unknown",""]:_check(not A.is_apple_software_basic("gl_compatibility",adapter),"LLVM/hardware/unknown retain current tier")
	for method:String in ["mobile","forward_plus","headless",""]:_check(not A.is_apple_software_basic(method,"Apple Software Renderer"),"other renderer methods unchanged")
	_check(A.is_software_gl("gl_compatibility","llvmpipe (LLVM 19.1.7, 256 bits)"),"original LLVM software policy retained")
	print("SCENE112_APPLE_PROFILE_CLASSIFICATION_OK checks=",checks," scope=classification fixtures only");quit()
func _check(ok:bool,label:String):
	checks+=1
	if not ok:push_error(label);quit(1)
