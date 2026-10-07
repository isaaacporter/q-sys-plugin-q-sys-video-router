table.insert(props, {
	Name = "Source Count",
	Type = "integer",
	Value = 8,
	Min = 1,
	Max = 64
})
table.insert(props, {
	Name = "Destination Count",
	Type = "integer",
	Value = 4,
	Min = 1,
	Max = 64
})
table.insert(props, {
	Name = "Default Mode",
	Type = "enum",
	Choices = {"One-To-One (Matrix)", "One-To-All"},
	Value = "One-To-One (Matrix)"
})
-- One-To-One selection order. Source First: pick a source, then the
-- destinations to send it to. Destination First: pick a destination, then its
-- source.
table.insert(props, {
	Name = "Matrix Select Order",
	Type = "enum",
	Choices = {"Destination First", "Source First"},
	Value = "Source First"
})
table.insert(props, {
	Name = "Debug Print",
	Type = "enum",
	Choices = {"None", "Function Calls", "Routes", "All"},
	Value = "None"
})
