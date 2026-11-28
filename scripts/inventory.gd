extends RefCounted
## Mochila del jugador: cuenta cuántos objetos de cada tipo lleva.

signal changed

var items: Dictionary = {}


func add(item: String, amount: int = 1) -> void:
	items[item] = get_count(item) + amount
	changed.emit()


func get_count(item: String) -> int:
	return int(items.get(item, 0))


## Saca objetos de la mochila. Devuelve false (y no saca nada) si no alcanzan.
func remove(item: String, amount: int = 1) -> bool:
	if get_count(item) < amount:
		return false
	items[item] = get_count(item) - amount
	if items[item] <= 0:
		items.erase(item)
	changed.emit()
	return true
