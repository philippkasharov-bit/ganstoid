## A car (V1). Parked along the kerbs at new game; the player can take one.
## Metres, radians, m/s. Pure data.
class_name VehicleData
extends Resource

@export var id: StringName
@export var position: Vector2
@export var heading: float = 0.0          # radians, 0 = facing +x
@export var speed: float = 0.0            # m/s along heading (negative = reversing)
@export var locked: bool = true
@export var owner_id: StringName = &""    # who it belongs to (&"player" once bought; stolen stays theirs)
@export_range(0.0, 1.0) var damage: float = 0.0
@export var color: Color = Color(0.6, 0.6, 0.65)
@export var length_m: float = 4.6
@export var width_m: float = 1.85
@export var driver_id: StringName = &""
@export var trunk: Dictionary = {}          # INV4: item id -> count kept in the trunk
@export var touched: bool = false        # anyone ever got in: only these need saving (the rest are as seeded)
