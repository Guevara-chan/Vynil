# ==Exported functions array==
Δexport				= (entity, pkg = module)	-> pkg.exports[entity.name] = entity
Δexport Δimport		= (namespace)				-> Object.assign global, namespace
Δexport repack		= (array)					-> array.GetValue idx for idx in [0...array.Length]
Δexport BranchProxy	= (root, body)	->
	Object.setPrototypeOf (new Proxy body, 
		{get: (self, key) -> if typeof (val = self[key]) is 'function' then val.bind(self) else val}), root
Δexport Δexport

# ==Additional prototype extensions==
Function::getter	= (name, proc)	-> Object.defineProperty @prototype, name, {get: proc, configurable: true}
Function::setter	= (name, proc) 	-> Object.defineProperty @prototype, name, {set: proc, configurable: true}
Function::new_branch = (name, body) -> @getter name, -> new BranchProxy @, body