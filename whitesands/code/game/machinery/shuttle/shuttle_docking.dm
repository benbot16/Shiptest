// This file contains code related to custom ship docking.
// This includes some data on simulated overmap ships, shuttle_docker AI eyes,

/obj/structure/overmap/ship/simulated
	///The overmap object the ship is preparing to dock at (for custom docking)
	var/obj/structure/overmap/dynamic/docking_target
	///The docking port we've created for this ship
	var/obj/docking_port/stationary/my_port
	var/shuttlePortName = "custom location"
	///Who's docking our ship, and the eye they're using
	var/mob/living/docking_camera_user
	var/mob/camera/aiEye/remote/shuttle_docker/eyeobj
	///What we can dock on
	var/static/list/whitelist_turfs = typecacheof(/turf/open/space, /turf/open/floor/grass, /turf/open/floor/plating/asteroid, /turf/open/lava, /turf/closed/mineral)
	///What we're designating
	var/designating_target_loc
	var/designate_time = 5 SECONDS
	///Actions to use for docking
	var/list/actions = list()
	var/datum/action/innate/camera_off/off_action = new
	var/datum/action/innate/shuttledocker_rotate/rotate_action = new
	var/datum/action/innate/shuttledocker_place/place_action = new

/mob/camera/aiEye/remote/shuttle_docker
	visible_icon = FALSE
	use_static = USE_STATIC_NONE
	var/list/placement_images = list()
	var/list/placed_images = list()

/mob/camera/aiEye/remote/shuttle_docker/Initialize(mapload, obj/structure/overmap/ship/simulated/ship)
	origin = ship
	return ..()

/mob/camera/aiEye/remote/shuttle_docker/Destroy()
	var/obj/structure/overmap/ship/simulated/ship = origin
	if(ship.state == OVERMAP_SHIP_ACTING) // We haven't docked yet, but the camera got destroyed for some reason or another
		ship.state = OVERMAP_SHIP_FLYING
	return ..()

/mob/camera/aiEye/remote/shuttle_docker/setLoc(destination)
	. = ..()
	var/obj/structure/overmap/ship/simulated/ship = origin
	ship.checkLandingSpot()

/mob/camera/aiEye/remote/shuttle_docker/update_remote_sight(mob/living/user)
	user.sight = BLIND|SEE_TURFS
	user.lighting_alpha = LIGHTING_PLANE_ALPHA_INVISIBLE
	user.sync_lighting_plane_alpha()
	return TRUE

/datum/action/innate/shuttledocker_rotate
	name = "Rotate"
	icon_icon = 'icons/mob/actions/actions_mecha.dmi'
	button_icon_state = "mech_cycle_equip_off"

/datum/action/innate/shuttledocker_rotate/Activate()
	if(QDELETED(target) || !isliving(target))
		return
	var/mob/living/C = target
	var/mob/camera/aiEye/remote/remote_eye = C.remote_control
	var/obj/structure/overmap/ship/simulated/origin = remote_eye.origin
	origin.rotateLandingSpot()

/datum/action/innate/shuttledocker_place
	name = "Place"
	icon_icon = 'icons/mob/actions/actions_mecha.dmi'
	button_icon_state = "mech_zoom_off"

/datum/action/innate/shuttledocker_place/Activate()
	if(QDELETED(target) || !isliving(target))
		return
	var/mob/living/C = target
	var/mob/camera/aiEye/remote/remote_eye = C.remote_control
	var/obj/structure/overmap/ship/simulated/origin = remote_eye.origin
	origin.placeLandingSpot(target)

/obj/structure/overmap/ship/simulated/proc/checkLandingSpot()
	var/mob/camera/aiEye/remote/shuttle_docker/the_eye = eyeobj
	var/turf/eyeturf = get_turf(the_eye)
	if(!eyeturf)
		return SHUTTLE_DOCKER_BLOCKED
	if(!eyeturf.z)
		return SHUTTLE_DOCKER_BLOCKED

	. = SHUTTLE_DOCKER_LANDING_CLEAR
	var/list/bounds = shuttle.return_coords(the_eye.x, the_eye.y, the_eye.dir)
	var/list/overlappers = SSshuttle.get_dock_overlap(bounds[1], bounds[2], bounds[3], bounds[4], the_eye.z)
	var/list/image_cache = the_eye.placement_images
	for(var/i in 1 to image_cache.len)
		var/image/I = image_cache[i]
		var/list/coords = image_cache[I]
		var/turf/T = locate(eyeturf.x + coords[1], eyeturf.y + coords[2], eyeturf.z)
		I.loc = T
		switch(checkLandingTurf(T, overlappers))
			if(SHUTTLE_DOCKER_LANDING_CLEAR)
				I.icon_state = "green"
			else
				I.icon_state = "red"
				. = SHUTTLE_DOCKER_BLOCKED

/obj/structure/overmap/ship/simulated/proc/checkLandingTurf(turf/T, list/overlappers)
	// Too close to the map edge is never allowed
	if(!T || T.x <= 5 || T.y <= 5 || T.x >= world.maxx - 5 || T.y >= world.maxy - 5)
		return SHUTTLE_DOCKER_BLOCKED
	// If it's one of our shuttle areas assume it's ok to be there
	if(shuttle.shuttle_areas[T.loc])
		return SHUTTLE_DOCKER_LANDING_CLEAR
	. = SHUTTLE_DOCKER_LANDING_CLEAR

	if(length(whitelist_turfs))
		if(!is_type_in_typecache(T.type, whitelist_turfs))
			return SHUTTLE_DOCKER_BLOCKED

	// Checking for overlapping dock boundaries
	for(var/i in 1 to overlappers.len)
		var/obj/docking_port/port = overlappers[i]
		if(port == my_port)
			continue
		var/list/overlap = overlappers[port]
		var/list/xs = overlap[1]
		var/list/ys = overlap[2]
		if(xs["[T.x]"] && ys["[T.y]"])
			return SHUTTLE_DOCKER_BLOCKED

/obj/structure/overmap/ship/simulated/proc/GrantActions(mob/living/user)
	if(off_action)
		off_action.target = user
		off_action.Grant(user)
		actions += off_action

	if(rotate_action)
		rotate_action.target = user
		rotate_action.Grant(user)
		actions += rotate_action

	if(place_action)
		place_action.target = user
		place_action.Grant(user)
		actions += place_action

/obj/structure/overmap/ship/simulated/proc/CreateEye()
	if(state == OVERMAP_SHIP_DOCKING || state == OVERMAP_SHIP_IDLE) // We're already docking
		return

	eyeobj = new /mob/camera/aiEye/remote/shuttle_docker(null, src)
	var/mob/camera/aiEye/remote/shuttle_docker/the_eye = eyeobj
	the_eye.setDir(shuttle.dir)
	var/turf/origin = locate(shuttle.x, shuttle.y, shuttle.z)
	for(var/area/A as anything in shuttle.shuttle_areas)
		for(var/turf/T in A)
			var/image/I = image('icons/effects/alphacolors.dmi', origin, "red")
			var/x_off = T.x - origin.x
			var/y_off = T.y - origin.y
			I.loc = locate(origin.x + x_off, origin.y + y_off, origin.z) //we have to set this after creating the image because it might be null, and images created in nullspace are immutable.
			I.layer = ABOVE_NORMAL_TURF_LAYER
			I.plane = 0
			I.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
			the_eye.placement_images[I] = list(x_off, y_off)

/obj/structure/overmap/ship/simulated/proc/give_eye_control(mob/user, obj/structure/overmap/dynamic/target)
	if(!isliving(user))
		return
	if(!eyeobj)
		CreateEye()
	src.docking_target = target // Save the docking target for later, when we actually dock
	eyeobj.forceMove(get_turf(docking_target.reserve_dock))
	GrantActions(user)
	docking_camera_user = user
	eyeobj.eye_user = user
	eyeobj.name = "Camera Eye ([user.name])"
	user.remote_control = eyeobj
	user.reset_perspective(eyeobj)
	eyeobj.setLoc(eyeobj.loc)
	user.client.view_size.supress()
	if(!QDELETED(user) && user.client)
		var/mob/camera/aiEye/remote/shuttle_docker/the_eye = eyeobj
		var/list/to_add = list()
		to_add += the_eye.placement_images
		to_add += the_eye.placed_images
		user.client.images += to_add
		user.client.view_size.setTo(max(shuttle.width, shuttle.height) + 4)

/obj/structure/overmap/ship/simulated/proc/remove_eye_control(mob/user)
	if(!user)
		return
	for(var/V in actions)
		var/datum/action/A = V
		A.Remove(user)
	actions.Cut()
	for(var/V in eyeobj.visibleCameraChunks)
		var/datum/camerachunk/C = V
		C.remove(eyeobj)
	if(user.client)
		user.reset_perspective(null)
		if(eyeobj.visible_icon && user.client)
			user.client.images -= eyeobj.user_image
		user.client.view_size.unsupress()

	eyeobj.eye_user = null
	user.remote_control = null

	docking_target = null

	if(!QDELETED(user) && user.client)
		var/mob/camera/aiEye/remote/shuttle_docker/the_eye = eyeobj
		var/list/to_remove = list()
		to_remove += the_eye.placement_images
		to_remove += the_eye.placed_images

		user.client.images -= to_remove
		user.client.view_size.resetToDefault()

	// Removes the eye and checks whether we actually got to docking, so that if someone exits the eye mode it doesn't softlock the ship
	qdel(eyeobj)

/obj/structure/overmap/ship/simulated/proc/placeLandingSpot()
	if(designating_target_loc || !docking_camera_user)
		return

	if(state == OVERMAP_SHIP_DOCKING || state == OVERMAP_SHIP_IDLE)
		to_chat(docking_camera_user, "<span class='warning'>WARNING: Target LZ already set.</span>")
		remove_eye_control(docking_camera_user)
		return

	var/mob/camera/aiEye/remote/shuttle_docker/the_eye = eyeobj
	var/landing_clear = checkLandingSpot()
	if(designate_time && (landing_clear != SHUTTLE_DOCKER_BLOCKED))
		to_chat(docking_camera_user, "<span class='notice'>Calculating approach vector. Please stand by.</span>")
		designating_target_loc = the_eye.loc
		var/wait_completed = do_after(docking_camera_user, designate_time, FALSE, designating_target_loc, TRUE, CALLBACK(src, .proc/canDesignateTarget))
		designating_target_loc = null
		if(!docking_camera_user)
			return
		if(!wait_completed)
			to_chat(docking_camera_user, "<span class='warning'>Operation aborted.</span>")
			return
		landing_clear = checkLandingSpot()

	if(landing_clear != SHUTTLE_DOCKER_LANDING_CLEAR)
		to_chat(docking_camera_user, "<span class='warning'>Target LZ obstructed.</span>")
		remove_eye_control(docking_camera_user)
		return

	// Makes a port for us to dock at that gets deleted after undocking.
	if(my_port)
		my_port.delete_after = TRUE
		my_port.name = "Old [my_port.name]"
		my_port = null

	if(!my_port)
		my_port = new()
		my_port.name = shuttlePortName
		my_port.height = shuttle.height
		my_port.width = shuttle.width
		my_port.dheight = shuttle.dheight
		my_port.dwidth = shuttle.dwidth
	my_port.setDir(the_eye.dir)
	my_port.forceMove(locate(eyeobj.x, eyeobj.y, eyeobj.z))

	if(docking_camera_user.client)
		docking_camera_user.client.images -= the_eye.placed_images

	QDEL_LIST(the_eye.placed_images)

	for(var/V in the_eye.placement_images)
		var/image/I = V
		var/image/newI = image('icons/effects/alphacolors.dmi', the_eye.loc, "blue")
		newI.loc = I.loc //It is highly unlikely that any landing spot including a null tile will get this far, but better safe than sorry.
		newI.layer = ABOVE_OPEN_TURF_LAYER
		newI.plane = 0
		newI.mouse_opacity = 0
		the_eye.placed_images += newI

	//Go to destination
	to_chat(docking_camera_user, "<span class='notice'>[dock(docking_target, my_port)]</span>")
	return TRUE

/obj/structure/overmap/ship/simulated/proc/canDesignateTarget()
	if(!designating_target_loc || !docking_camera_user || (eyeobj.loc != designating_target_loc))
		return FALSE
	return TRUE

/obj/structure/overmap/ship/simulated/proc/rotateLandingSpot()
	var/mob/camera/aiEye/remote/shuttle_docker/the_eye = eyeobj
	var/list/image_cache = the_eye.placement_images
	the_eye.setDir(turn(the_eye.dir, -90))
	for(var/i in 1 to image_cache.len)
		var/image/pic = image_cache[i]
		var/list/coords = image_cache[pic]
		var/Tmp = coords[1]
		coords[1] = coords[2]
		coords[2] = -Tmp
		pic.loc = locate(the_eye.x + coords[1], the_eye.y + coords[2], the_eye.z)
	checkLandingSpot()
