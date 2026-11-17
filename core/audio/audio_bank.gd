## AU1: the game's sounds, all made by tools/audio/synth.py (maths, no
## samples, so they are ours to ship). Loads each WAV once; the loops (city
## ambience, engine, siren, the car radio) are set to loop here, since the
## imported files are plain one-shots. Also makes the Music and Effects buses
## the volume settings turn (UiSettings).
class_name AudioBank
extends RefCounted

const DIR := "res://assets/audio/"
const LOOPS := ["amb_day", "amb_night", "amb_crowd", "engine", "siren", "radio_1", "radio_2"]
const ONE_SHOTS := ["step_1", "step_2", "step_3", "step_4", "punch", "swing", "slash", "bat_hit",
	"shot", "shot_far", "dry_fire", "equip", "door_open", "door_close", "door_kick", "lockpick", "rattle", "glass",
	"car_door", "horn", "crash", "car_pass", "distant_horn", "dog", "bird", "siren_far",
	"ui_click", "ui_open", "ui_close", "ui_cash", "ui_good", "ui_bad", "ui_stamp", "ui_rank",
	"pager", "phone_buzz", "ui_alert", "heartbeat"]
const STATIONS := ["radio_1", "radio_2"]   # the car radio
const BUSES := ["Music", "Effects"]

static var _cache := {}

## The sound called `name`, or null if the file is missing.
static func stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name + ".wav"
	var s: AudioStreamWAV = load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
	if s != null and LOOPS.has(name):
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = roundi(s.get_length() * s.mix_rate)   # in samples, whatever the import packed it as
	_cache[name] = s
	return s

## Makes the Music and Effects buses (once), feeding Master.
static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, &"Master")
	UiSettings.apply_volumes()
