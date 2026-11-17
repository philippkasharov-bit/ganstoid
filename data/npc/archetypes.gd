## NB1: kinds of people, as data. Each archetype gives the range every trait is
## rolled in (order of GanstoidEnums.MindTrait: bold, sociable, lawful, greedy,
## curious, patient, paranoid, energetic) and how fast each need runs down per
## game hour (order of GanstoidEnums.MindDrive: energy, food, money, social,
## safety, fun). A new kind of person is a new entry here, not new code.
## "jobs" lists the NPCData.job titles that make someone this archetype.
class_name Archetypes
extends RefCounted

const DEFAULT := &"resident"

const TABLE := {
	&"resident": {
		"label": "Resident",
		"traits": [[0.2, 0.8], [0.2, 0.8], [0.4, 0.9], [0.2, 0.7], [0.2, 0.8], [0.3, 0.8], [0.2, 0.7], [0.2, 0.8]],
		"drive_fall": [0.045, 0.07, 0.02, 0.03, 0.01, 0.03],
		"jobs": [],
	},
	&"office_worker": {
		"label": "Office worker",
		"traits": [[0.1, 0.6], [0.3, 0.8], [0.6, 1.0], [0.3, 0.7], [0.2, 0.7], [0.4, 0.9], [0.3, 0.7], [0.3, 0.7]],
		"drive_fall": [0.05, 0.07, 0.015, 0.035, 0.01, 0.035],
		"jobs": [&"secretary", &"accountant", &"lawyer", &"teller", &"loan officer", &"branch manager", &"receptionist"],
	},
	&"shop_owner": {
		"label": "Shop owner",
		"traits": [[0.3, 0.8], [0.4, 0.9], [0.5, 0.9], [0.5, 0.9], [0.2, 0.6], [0.4, 0.8], [0.5, 0.9], [0.4, 0.8]],
		"drive_fall": [0.05, 0.06, 0.03, 0.025, 0.015, 0.02],
		"jobs": [&"owner", &"shop owner", &"manager", &"store manager"],
	},
	&"homeless": {
		"label": "Homeless",
		"traits": [[0.2, 0.7], [0.1, 0.6], [0.2, 0.6], [0.1, 0.5], [0.3, 0.8], [0.5, 0.9], [0.5, 1.0], [0.1, 0.5]],
		"drive_fall": [0.06, 0.09, 0.04, 0.02, 0.03, 0.02],
		"jobs": [],
	},
	&"gang_member": {
		"label": "Gang member",
		"traits": [[0.6, 1.0], [0.4, 0.9], [0.0, 0.25], [0.5, 1.0], [0.2, 0.6], [0.1, 0.5], [0.5, 0.9], [0.5, 0.9]],
		"drive_fall": [0.04, 0.07, 0.04, 0.04, 0.025, 0.05],
		"jobs": [],
	},
	&"cop_on_beat": {
		"label": "Cop on the beat",
		"traits": [[0.5, 0.9], [0.2, 0.7], [0.4, 1.0], [0.2, 0.7], [0.4, 0.8], [0.2, 0.6], [0.4, 0.8], [0.4, 0.8]],
		"drive_fall": [0.05, 0.07, 0.015, 0.025, 0.01, 0.025],
		"jobs": [],
	},
}
