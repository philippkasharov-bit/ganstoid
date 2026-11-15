## QA4 validator: closing the game while the hourly autosave is still writing.
## That used to crash on exit (the worker was never waited for), and the quit
## save could write the same file at the same moment. Now the close waits for
## the autosave, writes once, and the save on disk is the moment you quit.
## Any save already in the user folder is put back afterwards.
extends SceneTree

func _initialize() -> void:
	var backup := SaveGame.PATH + ".verify_backup"
	if SaveGame.exists():
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SaveGame.PATH), ProjectSettings.globalize_path(backup))
	Engine.set_meta("skip_new_game", true)
	Engine.set_meta("seed", 4242)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var ok := await _run(main)
	main.queue_free()
	await process_frame
	SaveGame.delete()
	if FileAccess.file_exists(backup):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(SaveGame.PATH))
	print("AUTOSAVE_QUIT_VERIFY: PASS" if ok else "AUTOSAVE_QUIT_VERIFY: FAIL - see above")
	quit(0 if ok else 1)

func _run(main: Node) -> bool:
	var driver: Node = main.get_node("WorldDriver")
	while SimNav.active == null or not SimNav.active.is_ready():
		await process_frame
	for i in 3:
		await physics_frame
	driver.world.tick = SimClock.hours(12.0)   # a new hour: the next tick starts the autosave
	await physics_frame
	var started: int = driver._save_task
	if not _check(started != -1, "a new game hour starts the autosave on a worker"):
		return false
	driver.world.tick = SimClock.hours(13.0)   # the next hour comes round while the first may still be writing
	await physics_frame
	var me: NPCData = driver.world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	me.cash = 9191
	driver._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)   # Phil closes the window
	if not _check(driver._save_task == -1, "closing waits for the autosave to finish"):
		return false
	var saved := SaveGame.read()
	if not _check(not saved.is_empty() and saved["tick"] == driver.world.tick, "the save on disk is the moment of quitting (tick %s)" % saved.get("tick")):
		return false
	var cash: int = saved["entities"][PlayerFactory.PLAYER_ENTITY_ID][ComponentNames.NPC]["cash"]
	return _check(cash == 9191, "it has what changed just before quitting (cash $%d)" % cash)

func _check(ok: bool, what: String) -> bool:
	print(("ok    " if ok else "FAIL  ") + what)
	return ok
