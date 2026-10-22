class_name ProfileLog
extends RefCounted
## One-line profiling output for flag-gated timings (`TAG {json}`), so tools can grep a single line per measurement.


static func emit(tag: String, data: Dictionary) -> void:
	print(tag, " ", JSON.stringify(data))
