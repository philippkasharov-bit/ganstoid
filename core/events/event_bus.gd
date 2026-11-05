## Decoupling point for cross-cutting notifications — the case where a
## trigger (crime witnessed, gang destroyed, raid resolved) needs to reach
## several future systems without each one being hard-wired into whatever
## fired it.
##
## Deliberately NOT used for everything: systems that always run together
## every tick (RecognitionSystem's own decay) stay as direct calls — an
## event bus there would hide a call that's really just "the next line of
## code" behind a signal, which is indirection with no decoupling benefit.
## This exists for the opposite case: one event, multiple independent
## listeners, added over separate phases (Phase 1's crime system emits
## "crime_witnessed"; Phase 4's law/beef ladders and Phase 1's own
## RecognitionSystem.register_witness both react to it, each without
## knowing the other exists).
class_name EventBus
extends RefCounted

signal event_fired(event_name: StringName, payload: Dictionary)

func emit(event_name: StringName, payload: Dictionary = {}) -> void:
	event_fired.emit(event_name, payload)

## Convenience wrapper so callers don't reach into .event_fired directly —
## keeps "how EventBus works internally" swappable later (e.g. per-event-name
## signals for performance) without touching every call site.
func subscribe(listener: Callable) -> void:
	event_fired.connect(listener)
