@tool
class_name Codegen extends Resource
var OPTION_HANDLING: = RustOptionHandling.OPTION_T_AS_T
var HIDE_PRIVATE_TABLES: = true
const PLUGIN_DATA_FOLDER = "spacetime_data"
const CODEGEN_FOLDER = "schema"
const REQUIRED_FOLDERS_IN_CODEGEN_FOLDER = ["tables", "spacetime_types"]

const GDNATIVE_TYPES := {
	"I8": "int",
	"I16": "int",
	"I32": "int",
	"I64": "int",
	"U8": "int",
	"U16": "int",
	"U32": "int",
	"U64": "int",
	"F32": "float",
	"F64": "float",
	"String": "String",
	"Vector4": "Vector4",
	"Vector4I": "Vector4i",
	"Vector3": "Vector3",
	"Vector3I": "Vector3i",
	"Vector2": "Vector2",
	"Vector2I": "Vector2i",
	"Plane": "Plane",
	"Color": "Color",
	"Quaternion": "Quaternion",
	"Bool": "bool",
}
var TYPE_MAP := {
	"__identity__": "PackedByteArray",
	"__connection_id__": "PackedByteArray",
	"__timestamp_micros_since_unix_epoch__": "int",
	"__time_duration_micros__": "int",
}
var META_TYPE_MAP := {
	"I8": "i8",
	"I16": "i16",
	"I32": "i32",
	"I64": "i64",
	"U8": "u8",
	"U16": "u16",
	"U32": "u32",
	"U64": "u64",
	"F32": "f32",
	"F64": "f64",
	"__identity__": "identity",
	"__connection_id__": "connection_id",
	"__timestamp_micros_since_unix_epoch__": "i64",
	"__time_duration_micros__": "i64",
}

enum RustOptionHandling {
	IGNORE = 1, #This will not generate any fields for Option<T> types.
	USE_GODOT_OPTION = 2, #https://github.com/WhoStoleMyCoffee/godot-optional/tree/main
	OPTION_T_AS_T = 3 #This will use Option<T> as T in GDScript. This may have issues with nullability in Godot, so use with caution.
}


func _init() -> void:
	TYPE_MAP.merge(GDNATIVE_TYPES)

func _on_request_completed(json_string: String, module_name: String) -> Array[String]:
	var json = JSON.parse_string(json_string)
	var schema: Dictionary = parse_schema(json, module_name)
	if not DirAccess.dir_exists_absolute("res://%s/%s" %[PLUGIN_DATA_FOLDER, "codegen_debug"]):
		DirAccess.make_dir_recursive_absolute("res://%s/%s" %[PLUGIN_DATA_FOLDER , "codegen_debug"])
	
	for folder in REQUIRED_FOLDERS_IN_CODEGEN_FOLDER:
		if not DirAccess.dir_exists_absolute("res://%s/%s/%s" %[PLUGIN_DATA_FOLDER, CODEGEN_FOLDER, folder]):
			DirAccess.make_dir_recursive_absolute("res://%s/%s/%s" %[PLUGIN_DATA_FOLDER, CODEGEN_FOLDER, folder])
			
	var file = FileAccess.open("res://%s/%s/readme.txt" %[PLUGIN_DATA_FOLDER , "codegen_debug"], FileAccess.WRITE)
	file.store_string("You can delete this directory and files. It's only used for codegen debugging.")
	file = FileAccess.open("res://%s/%s/schema_%s.json" % [PLUGIN_DATA_FOLDER, "codegen_debug", module_name], FileAccess.WRITE)
	file.store_string(JSON.stringify(schema, "\t", false))
	var generated_files := build_gdscript_from_schema(schema)
	return generated_files

func build_gdscript_from_schema(schema: Dictionary) -> Array[String]:
	var module_name: String = schema.get("module", null)
	var generated_files: Array[String] = []
	for type in schema.get("types", []):
		if type.has("gd_native"): continue
		if type.has("struct"):
			var struct: Array = type.get("struct", [])
			var folder_path: String = "spacetime_types"
			if type.has("table_name"):
				if not type.has("primary_key_name"): continue
				if HIDE_PRIVATE_TABLES and type.get("is_private", false): 
					Spacetime.print_log("Skipping private table %s" % type.get("name", ""))
					continue
				folder_path = "tables"
			var content: String = generate_struct_gdscript(type, module_name)
			var output_file_name: String = "%s_%s.gd" % \
				[module_name.to_snake_case(), type.get("name", "").to_snake_case()]
			var output_file_path: String = "res://%s/%s/%s/%s" % [PLUGIN_DATA_FOLDER, CODEGEN_FOLDER, folder_path, output_file_name]
			if not DirAccess.dir_exists_absolute("res://%s/%s/%s" % [PLUGIN_DATA_FOLDER, CODEGEN_FOLDER, folder_path]):
				DirAccess.make_dir_recursive_absolute("res://%s/%s/%s" % [PLUGIN_DATA_FOLDER, CODEGEN_FOLDER, folder_path])
			var file = FileAccess.open(output_file_path, FileAccess.WRITE)
			if file:
				file.store_string(content)
			generated_files.append(output_file_path)
		elif type.has("enum"):
			if not type.get("is_sum_type"): continue
			var sum: Array = type.get("enum", [])
			var folder_path: String = "spacetime_types"
			var content: String = generate_enum_gdscript(type, module_name)
			var output_file_name: String = "%s_%s.gd" % \
				[module_name.to_snake_case(), type.get("name", "").to_snake_case()]
			var output_file_path: String = "res://%s/%s/%s/%s" % [PLUGIN_DATA_FOLDER ,CODEGEN_FOLDER, folder_path, output_file_name]
			if not DirAccess.dir_exists_absolute("res://%s/%s/%s" % [PLUGIN_DATA_FOLDER ,CODEGEN_FOLDER, folder_path]):
				DirAccess.make_dir_recursive_absolute("res://%s/%s/%s" % [PLUGIN_DATA_FOLDER, CODEGEN_FOLDER, folder_path])
			var file = FileAccess.open(output_file_path, FileAccess.WRITE)
			if file:
				file.store_string(content)
			generated_files.append(output_file_path)
	var module_content: String = generate_module_gdscript(schema)
	var output_file_name: String = "module_%s.gd" % module_name.to_snake_case()
	var output_file_path: String = "res://%s/%s/%s" % [PLUGIN_DATA_FOLDER ,CODEGEN_FOLDER, output_file_name]
	var file = FileAccess.open(output_file_path, FileAccess.WRITE)
	if file:
		file.store_string(module_content)
		generated_files.append(output_file_path)
	var reducers_content: String = generate_reducer_gdscript(schema)
	output_file_name = "module_%s_reducers.gd" % module_name.to_snake_case()
	output_file_path = "res://%s/%s/%s" % [PLUGIN_DATA_FOLDER, CODEGEN_FOLDER, output_file_name]
	file = FileAccess.open(output_file_path, FileAccess.WRITE)
	if file:
		file.store_string(reducers_content)
		generated_files.append(output_file_path)
	var types_content: String = generate_types_gdscript(schema)
	output_file_name = "module_%s_types.gd" % module_name.to_snake_case()
	output_file_path = "res://%s/%s/%s" % [PLUGIN_DATA_FOLDER ,CODEGEN_FOLDER, output_file_name]
	file = FileAccess.open(output_file_path, FileAccess.WRITE)
	if file:
		file.store_string(types_content)
		generated_files.append(output_file_path)
	Spacetime.print_log(["Generated files:\n", "\n".join(generated_files)])
	return generated_files

func generate_struct_gdscript(type, module_name) -> String:
	var struct_name: String = type.get("name", "")
	var fields: Array = type.get("struct", [])
	var meta_data: Array = []
	var table_name: String = type.get("table_name", "")
	var _class_name: String = module_name.to_pascal_case() + struct_name.to_pascal_case()
	var _extends_class = "Resource"
	if table_name:
		meta_data.append("set_meta('table_name', '%s')" % table_name)
		_extends_class = "ModuleTable"
		var primary_key_name: String = type.get("primary_key_name", "")
		if primary_key_name:
			meta_data.append("set_meta('primary_key', '%s')" % primary_key_name)
	
	var content: String = "#Do not edit this file, it is generated automatically.\n" + \
	"class_name %s extends %s\n\n" % [_class_name, _extends_class]
	var class_fields: Array = []
	for field in fields:
		var field_name: String = field.get("name", "")
		var field_type: String = TYPE_MAP.get(field.get("type", ""), "")
		if field.has("is_option"):
			match OPTION_HANDLING:
				RustOptionHandling.IGNORE: continue
				RustOptionHandling.USE_GODOT_OPTION:
					field_type = "Option"
		if field.has("is_array"):
			field_type = "Array[%s]" % field_type
		var meta: String = META_TYPE_MAP.get(field.get("type", ""), "")
		if not meta.is_empty():
			meta_data.append("set_meta('bsatn_type_%s', &'%s')" 
				% [field_name, meta])
		content += "@export var %s: %s\n" % [field_name, field_type]
		class_fields.append([field_name, field_type])
	content += "\nfunc _init():\n"
	for m in meta_data:
		content += "\t%s\n" % m
	if meta_data.size() == 0:
		content += "\tpass\n"
	content += "\nstatic func create(%s) -> %s:\n" % \
	[", ".join(class_fields.map(func(x): return "_%s: %s" % [x[0], x[1]])), _class_name] + \
	"\tvar result = %s.new()" % [_class_name]
	for field in fields:
		var field_name: String = field.get("name", "")
		content += "\n\tresult.%s = _%s" % [field_name, field_name]
	content += "\n\treturn result\n"
	return content.left(-1)

func generate_enum_gdscript(type, module_name) -> String:
	var enum_name: String = type.get("name", "")
	var variants: Array = type.get("enum", [""])
	var default_value: String = variants[0].get("name", "")
	var variant_types: String = "["
	var variant_names: String = ""
	for v in variants:
		variant_names += "\t%s,\n" % [v.get("name", "")]
		var _type = META_TYPE_MAP.get(v.get("type", ""), "")
		if v.has("is_array"):
			variant_types += "&'vec_%s', " % _type
		elif _type.is_empty():
			variant_types += "&'', "
		else:
			variant_types += "&'%s', " % _type
	variant_types = variant_types.left(-2) + "]"
	variant_names = variant_names.left(-2)
	var _class_name: String = module_name.to_pascal_case() + enum_name.to_pascal_case()
	var content: String = "#Do not edit this file, it is generated automatically.\n" + \
	"class_name %s extends Resource\n\n" % _class_name + \
	"""const enum_sub_classes: Array = %s\n""" % variant_types + \
	"const gd_sub_classes: Array = [%s]\n\n" % \
	[", ".join(variants.map(func(x): return "&'" + TYPE_MAP.get(x.get("type", ""), "") + "'"))] + \
	"var value: int = %s\n" % default_value + \
	"var data: Variant\n\n" + \
	"enum {\n%s\n}\n\n" % variant_names + \
	"static func parse(i: int) -> String:\n" + \
	"\tmatch i:\n"
	for i in range(variants.size()):
		content += "\t\t%d: return \"%s\"\n" % [i, variants[i].get("name", "")]
	content += "\t\t_:\n" + \
	"\t\t\tprinterr(\"Enum does not have value for %d. This is out of bounds.\")\n" + \
	"\t\t\treturn \"Unknown\"\n\n"	
	for v in variants:
		var variant_name: String = v.get("name", "")
		var variant_type: String = TYPE_MAP.get(v.get("type", ""), "int")
		if v.has("is_array"):
			variant_type = "Array[%s]" % variant_type
		content += "func get_%s() -> %s:\n" % [variant_name.to_snake_case(), variant_type] + \
		"\treturn data\n\n"
	content +="static func create(type: int, _data: Variant = null) -> %s:\n" % _class_name + \
	"\tvar result = %s.new()\n" % _class_name + \
	"\tresult.value = type\n" + \
	"\tresult.data = _data\n" + \
	"\treturn result\n\n"
	for v in variants:
		var variant_name: String = v.get("name", "")
		var variant_type: String = TYPE_MAP.get(v.get("type", ""), "")
		if variant_type.is_empty():
			content += "static func create_%s() -> %s:\n" % [variant_name.to_snake_case(), _class_name] + \
			"\treturn create(%s)\n\n" % [variant_name]
			continue
		if v.has("is_array"):
			variant_type = "Array[%s]" % variant_type
		content += "static func create_%s(_data: %s) -> %s:\n" % [variant_name.to_snake_case(), variant_type, _class_name] + \
		"\treturn create(%s, _data)\n\n" % [variant_name]
	return content.left(-2)

func generate_module_gdscript(schema: Dictionary) -> String:
	var module_name: String = schema.get("module", null)
	var content: String = "#Do not edit this file, it is generated automatically.\n" + \
	"class_name %sModule extends Resource\n\n" % module_name.to_pascal_case()
	content += "const Reducers = preload('res://%s/%s/module_%s_reducers.gd')\n" % [PLUGIN_DATA_FOLDER, CODEGEN_FOLDER, 
		module_name.to_snake_case()]
	content += "const Types = preload('res://%s/%s/module_%s_types.gd')\n\n" % [PLUGIN_DATA_FOLDER ,CODEGEN_FOLDER, 
		module_name.to_snake_case()]
	content += generate_types_gdscript(schema, true) + "\n"
	content += generate_reducer_gdscript(schema)
	return content

func generate_types_gdscript(schema: Dictionary, const_pointer: bool = false) -> String:
	var content: String
	var module_name: String = schema.get("module", null)
	for _type in schema.get("types", []):
		if _type.has("gd_native"): continue
		var type_name: String = _type.get("name", "")
		var subfolder = "spacetime_types"
		if _type.has("table_name"):
			if not _type.has("primary_key_name"): 
				Spacetime.print_log(["Table %s has no primary key." % type_name,
				"Only tables with a primary key can be generated."])				
				continue			
			if HIDE_PRIVATE_TABLES and _type.get("is_private", false): continue
			subfolder = "tables"
		if const_pointer:
			content += "const %s = Types.%s\n" % \
			[type_name.to_pascal_case(), type_name.to_pascal_case()]
			continue
		#If enum is not a rust sum type use enum
		if _type.has("is_sum_type") and not _type.get("is_sum_type"):
			content += "enum %s {\n" % type_name.to_pascal_case()
			for variant in _type.get("enum", []):
				var variant_name: String = variant.get("name", "")
				content += "\t_%s,\n" % variant_name.to_pascal_case()
			content += "}\n"
		else:
			content += "const %s = preload('res://%s/%s/%s/%s_%s.gd')\n" % \
			[type_name.to_pascal_case(), PLUGIN_DATA_FOLDER, CODEGEN_FOLDER, subfolder, 
			module_name.to_snake_case(), type_name.to_snake_case()]
	return content

func generate_reducer_gdscript(schema: Dictionary) -> String:
	var content: String
	for reducer in schema.get("reducers", []):
		var params_str: String = ""
		for param in reducer.get("params", []):
			var param_name: String = param.get("name", "")
			var param_type: String = TYPE_MAP.get(param.get("type", ""), "")
			if param.has("is_array"):
				param_type = "Array[%s]" % param_type
			params_str += "%s: %s, " % [param_name, param_type]
		if params_str.is_empty():
			params_str = "cb: Callable = func(_t: TransactionUpdateData): pass"
		else:
			params_str += "cb: Callable = func(_t: TransactionUpdateData): pass"
		var param_names = ", ".join(reducer.get("params", []).map(func(x): return x.get("name", "")))
		var param_types = ", ".join(reducer.get("params", []).map(func(x): 
			var meta_type = META_TYPE_MAP.get(x.get("type", ""), "")
			if meta_type.is_empty(): return "''"
			return "&'"+META_TYPE_MAP.get(x.get("type", ""), "")+"'"))
		var reducer_name: String = reducer.get("name", "")
		content += "static func %s(%s) -> void:\n" % [reducer_name, params_str] + \
		"\tvar __id__: int = SpacetimeDB.call_reducer('%s', [%s], [%s])\n" % \
		[reducer_name, param_names, param_types] + \
		"\tvar __result__ = await SpacetimeDB.wait_for_reducer_response(__id__)\n" + \
		"\tcb.call(__result__)\n\n"
	content = content.left(-2)
	return content

func generate_module_link(modules: Array[String]) -> void:
	var content: String = "#Do not edit this file, it is generated automatically.\n" + \
	"class_name SpacetimeModule extends Resource\n\n"
	for module_name in modules:
		content += "const %s = preload('res://%s/%s/module_%s.gd')\n" % \
		[module_name.to_pascal_case(), PLUGIN_DATA_FOLDER, CODEGEN_FOLDER, module_name.to_snake_case()]
	var output_file_name: String = "spacetime_modules.gd"
	var output_file_path: String = "res://%s/%s/%s" % [PLUGIN_DATA_FOLDER ,CODEGEN_FOLDER, output_file_name]
	var file = FileAccess.open(output_file_path, FileAccess.WRITE)
	if file:
		file.store_string(content)

func parse_schema(schema: Dictionary, module_name: String) -> Dictionary:
	var schema_tables: Array = schema.get("tables", [])
	var schema_types: Array= schema.get("types", [])
	var schema_reducers: Array = schema.get("reducers", [])
	var typespace: Array = schema.get("typespace", {}).get("types", [])
	schema_types.sort_custom(func(a, b): return a.get("ty", -1) < b.get("ty", -1))
	var types := []

	for type_info in schema_types:
		var type_name: String = type_info.get("name", {}).get("name", null)
		if not type_name:
			printerr("Invalid schema: Type name not found for type: %s" % type_info)
			return {}
		var type_data := {
			"name": type_name,
		}
		if GDNATIVE_TYPES.has(type_name):
			type_data["gd_native"] = true
		var ty := int(type_info.get("ty", -1))
		if ty == -1:
			printerr("Invalid schema: Type 'ty' not found for type: %s" % type_info)
			return {}
		var struct: Dictionary = typespace[ty].get("Product", {})
		var sum_type: Dictionary = typespace[ty].get("Sum", {})
		if struct:
			var elements := []
			for e in struct.get("elements", []):
				var data := {
					"name": e.get("name",{}).get("some", null),
				}
				var field_type = e.get("algebraic_type", {})
				if field_type.has("Array"):
					data["is_array"] = true
					field_type = field_type.Array
				if field_type.has("Product"):
					field_type = field_type.Product.get("elements", [])[0].get('name', {}).get('some', null)
				elif field_type.has("Sum"):
					if is_sum_option(field_type.Sum):
						data["is_option"] = true
					field_type = field_type.Sum.variants[0].get('algebraic_type', {}).keys()[0]
				elif field_type.has("Ref"):
					field_type = schema_types[field_type.Ref].get("name", {}).get("name", null)
				else:
					field_type = field_type.keys()[0]
				data["type"] = field_type				
				elements.append(data)
			if not type_data.has("gd_native"):
				TYPE_MAP[type_name] = module_name.to_pascal_case() + type_name.to_pascal_case()
				META_TYPE_MAP[type_name] = module_name.to_pascal_case() + type_name.to_pascal_case()
			type_data["struct"] = elements
			types.append(type_data)
		elif sum_type:
			var elements := []
			type_data["is_sum_type"] = false
			for e in sum_type.get("variants", []):
				var data := {
					"name": e.get("name",{}).get("some", null)
				}
				var variant_type = e.get("algebraic_type", {})
				if variant_type.has("Array"):
					data["is_array"] = true
					variant_type = variant_type.Array
				if variant_type.has("Product"):
					variant_type = variant_type.Product.get("elements", [])
					if variant_type.size() >= 1:
						variant_type = variant_type[0].get('name', {}).get('some', null)
					else:
						variant_type = null
				elif variant_type.has("Sum"):
					if is_sum_option(variant_type.Sum):
						data["is_option"] = true
					variant_type = variant_type.Sum.variants[0].get('algebraic_type', {}).keys()[0]
				elif variant_type.has("Ref"):
					variant_type = schema_types[variant_type.Ref].get("name", {}).get("name", null)
				else:
					variant_type = variant_type.keys()[0]
				if variant_type:
					data["type"] = variant_type
					type_data["is_sum_type"] = true
				elements.append(data)
			type_data["enum"] = elements
			types.append(type_data)
			if not type_data.get("is_sum_type"):
				META_TYPE_MAP[type_name] = "u8"
				TYPE_MAP[type_name] = "{0}Module.{1}".format([module_name.to_pascal_case(), type_name.to_pascal_case()])
			else:
				TYPE_MAP[type_name] = module_name.to_pascal_case() + type_name.to_pascal_case()
				META_TYPE_MAP[type_name] = "enum"
		else:
			printerr("Invalid schema: Type 'Product' or 'Sum' not found for type: %s" % type_info)
			return {}

	for table_info in schema_tables:
		var table_name: String = table_info.get("name", null)
		var ref = table_info.get("product_type_ref", null)
		if ref == null or table_name == null: continue
		types[ref].table_name = table_name
		var primary_key: Array = table_info.get("primary_key", [])
		if primary_key.size() == 1:
			types[ref].primary_key = int(primary_key[0])
			types[ref].primary_key_name = types[ref].struct[primary_key[0]].name
		if table_info.get("table_access", {}).has("Private"):
			types[ref].is_private = true
	
	var reducers := []
	for reducer_info in schema_reducers:
		var lifecycle = reducer_info.get("lifecycle", {}).get("some", null)
		if lifecycle: continue
		var name = reducer_info.get("name", null)
		var params := []
		for p in reducer_info.get("params", {}).get("elements", []):
			var data := {
				"name": p.get("name",{}).get("some", null),
			}
			var param_type = p.get("algebraic_type", {})
			if param_type.has("Array"):
				data["is_array"] = true
				param_type = param_type.Array
			if param_type.has("Product"):
				param_type = param_type.Product.get("elements", [])[0].get('name', {}).get('some', null)
			elif param_type.has("Ref"):
				param_type = schema_types[param_type.Ref].get("name", {}).get("name", null)
			elif param_type.has("Sum"):
				if is_sum_option(param_type.Sum):
					data["is_option"] = true
				param_type = param_type.Sum.variants[0].get('algebraic_type', {}).keys()[0]
			else:
				param_type = param_type.keys()[0]
			data["type"] = param_type
			params.append(data)
		reducers.append({
			"name": name,
			"params": params
		})

	var parsed_schema = {
		"module": module_name.to_pascal_case(),
		"types": types,
		"reducers": reducers,
		"type_map": TYPE_MAP,
		"meta_type_map": META_TYPE_MAP,
		"tables": schema_tables,
	}
	return parsed_schema

func is_sum_option(sum) -> bool:
	var variants = sum.get("variants", [])
	if variants.size() != 2:
		return false
	elif variants[0].get("name", {}).get("some", "") != "some":
		return false
	elif variants[1].get("name", {}).get("some", "") != "none":
		return false
	return true
