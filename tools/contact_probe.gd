## Temporary: check where the frog's collision actually is, and what the
## contact helpers report.
extends Node


func _ready() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var body: CollisionShape3D = main.get_node("Frog/Body")
	var shape: ConcavePolygonShape3D = body.shape
	print("frog body shape aabb ", shape.get_aabb(), "  body xform ", body.global_transform)
	var mesh: MeshInstance3D = main.get_node("Frog/Model/FrogMesh/FrogMokugyo")
	print("frog mesh aabb ", mesh.global_transform * mesh.get_aabb())
	print("frog mesh surfaces ", mesh.mesh.get_surface_count())
	var mallet: RigidBody3D = main.get_node("Mallet")
	print("mallet t0 ", mallet.global_transform)

	# park the mallet hard against the frog's side and watch one contact
	var held := func():
		mallet.set_held(true)
		mallet._pointer_driven = false
		mallet._hold_basis = mallet.global_transform.basis
	await get_tree().physics_frame
	held.call()
	mallet._desired = Vector3(0.055, 0.07, 0.0)
	var watched := 0
	while watched < 200:
		await get_tree().physics_frame
		watched += 1
		if mallet.get_contact_count() > 0:
			var st := PhysicsServer3D.body_get_direct_state(mallet.get_rid())
			for i in st.get_contact_count():
				var other = st.get_contact_collider_object(i)
				print("contact %d other=%s local_pos=%s collider_pos=%s mallet_origin=%s" % [
					i, other.name if other else "null",
					st.get_contact_local_position(i),
					st.get_contact_collider_position(i),
					mallet.global_position])
			break
	print("final mallet ", mallet.global_position)
	get_tree().quit()
