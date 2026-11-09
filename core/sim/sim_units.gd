## MG1b: movement speeds in metres per second. The world is in metres (real LA
## geometry), so every speed and radius in the systems is a real distance.
class_name SimUnits
extends RefCounted

const STROLL := 0.8   # idling around a doorway
const WALK := 1.5
const JOG := 3.5
const SPRINT := 6.0
const DRIVE := 12.0          # stand-in for cars (crew driver) until vehicles exist
const DRIVE_GETAWAY := 16.0  # driving hard with heat on you
const ARRIVE_M := 1.0   # "close enough" to a walk target
