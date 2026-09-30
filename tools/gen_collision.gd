## Derives the frog's crown shape from the imported froggreen GLB.
##
##   godot --headless --path . --script res://tools/gen_collision.gd
##
## The rebuilt frog is solid, and the striker is scripted rather than
## solver-driven, so the only physical body that needs a shape is the frog
## itself. A single sphere over the upper dome is enough for anything that
## wants to query or rest on the frog; it is derived here so it cannot drift
## from the art.

extends SceneTree

const OUT_DIR := "res://resources/collision"
const FROG_MODEL := "res://assets/models/frog_muyu.glb"

## Target world height of the frog, matching the scale baked into `frog.tscn`.
const FROG_HEIGHT := 0.1355

## The dome sphere's radius. Its top is placed on the frog's crown.
const HEAD_RADIUS := 0.046


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var ps: PackedScene = load(FROG_MODEL)
	var root := ps.instantiate()

	var frog_min := Vector3(1e9, 1e9, 1e9)
	var frog_max := Vector3(-1e9, -1e9, -1e9)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mi := node as MeshInstance3D
		if mi == null or mi.name.begins_with("Striker"):
			continue
		for i in 8:
			var corner: Vector3 = mi.transform * mi.get_aabb().get_endpoint(i)
			frog_min = frog_min.min(corner)
			frog_max = frog_max.max(corner)

	var scale := FROG_HEIGHT / (frog_max.y - frog_min.y)
	var crown := (frog_max.y - frog_min.y) * scale
	print("frog bounds ", frog_min, " .. ", frog_max, "  scale = %.6f" % scale)

	var head := SphereShape3D.new()
	head.radius = HEAD_RADIUS
	_save(head, "frog_head.tres")
	print("crown %.4f -> sphere centre y %.4f, radius %.4f"
		% [crown, crown - HEAD_RADIUS, HEAD_RADIUS])

	root.free()
	quit()


func _save(res: Resource, file: String) -> void:
	var path := "%s/%s" % [OUT_DIR, file]
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("save failed %s -> %d" % [path, err])
	else:
		print("wrote ", path)
