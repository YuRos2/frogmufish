## Derives persisted collision resources from the imported GLB models.
##
##   godot --headless --path . --script res://tools/gen_collision.gd
##
## The frog needs a concave shape so the mallet can pass through the mouth slot
## and rest on the lip, so its body surface (material slot 0) becomes a
## ConcavePolygonShape3D. The mallet is a compound of two capsules.

extends SceneTree

const OUT_DIR := "res://resources/collision"

## The frog GLB also carries the two pupil meshes (they are separate nodes so
## they can blink). The collision must come from the body surface only, so find
## the mesh that actually owns the body material.
const BODY_MATERIAL := "FrogBody"

const HEAD_R := 0.0136
const HEAD_LEN := 0.0313
const HANDLE_R := 0.0054
const HANDLE_LEN := 0.1900
const HANDLE_MID := 0.0945


func _body_surface(node: Node) -> int:
	"""Index of the surface on `node` that owns the body material, or -1."""
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat != null and mat.resource_name == BODY_MATERIAL:
				return i
	for child in node.get_children():
		var found := _body_surface(child)
		if found >= 0:
			return found
	return -1


func _find_body_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and _body_surface(node) >= 0:
		return node
	for child in node.get_children():
		var found := _find_body_mesh(child)
		if found != null:
			return found
	return null


func _mesh_instance(path: String) -> MeshInstance3D:
	var ps: PackedScene = load(path)
	if ps == null:
		push_error("could not load " + path)
		return null
	var found := _find_body_mesh(ps.instantiate())
	if found == null:
		push_error("no mesh with the %s material in %s" % [BODY_MATERIAL, path])
	return found


func _frog_shape() -> ConcavePolygonShape3D:
	var mi := _mesh_instance("res://assets/models/frog_mokugyo.glb")
	var mesh: Mesh = mi.mesh
	# Use the surface that actually carries the body material rather than
	# assuming it is surface 0; the face details are extra surfaces now.
	var surface := _body_surface(mi)
	var arrays: Array = mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var xf := mi.transform
	var faces := PackedVector3Array()
	if index.is_empty():
		faces.resize(verts.size())
		for i in verts.size():
			faces[i] = xf * verts[i]
	else:
		faces.resize(index.size())
		for i in index.size():
			faces[i] = xf * verts[index[i]]

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	print("frog body: %d triangles from %s surface %d" % [
		faces.size() / 3, mi.name, surface])
	return shape


func _save(res: Resource, file: String) -> void:
	var path := "%s/%s" % [OUT_DIR, file]
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("save failed %s -> %d" % [path, err])
	else:
		print("wrote ", path)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# Local Y of a Y-aligned capsule maps onto world X.
	var to_x := Transform3D(
		Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3.ZERO)

	_save(_frog_shape(), "frog_body.res")

	var head := CapsuleShape3D.new()
	head.radius = HEAD_R
	head.height = HEAD_LEN
	_save(head, "mallet_head.tres")

	var handle := CapsuleShape3D.new()
	handle.radius = HANDLE_R
	handle.height = HANDLE_LEN
	_save(handle, "mallet_handle.tres")

	print("to_x basis = ", to_x)
	quit()
