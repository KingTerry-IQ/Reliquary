## Local cache of extracted cartridges. Losing this file loses nothing but
## the download; the chain still holds the zip.

class_name Shelf
extends RefCounted

const INDEX_PATH := "user://shelf.json"

var entries: Dictionary = {}


func load_index() -> void:
	entries = {}
	if not FileAccess.file_exists(INDEX_PATH):
		return
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		entries = parsed


func save_index() -> void:
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(entries))
	file.close()


func remember(table: String, record: Dictionary) -> void:
	entries[table] = record
	save_index()


func forget(table: String) -> void:
	entries.erase(table)
	save_index()
