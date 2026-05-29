package hank;

import hank.Interpreter;
import hank.Lexer;
import hank.Parser;
import hank.Types;

/**
 * A Hank Host Runner.
 * Handles resource orchestration, macro resolution, and AST caching.
 * Platform-agnostic: uses the Resource model for all content retrieval.
 */
class Runner {
    var resourceCache:Map<String, Resource> = new Map();
    public var coreScope:Scope = new HankScope();

    public function new() {}

    /**
     * Registers a set of native tasks under a module name.
     */
    final public function registerModule(name:String, tasks:Map<String, (Array<Value>, ExecutionContext)->Value>) {
        var moduleObj = new Map<String, Value>();
        for (tName => func in tasks) {
            moduleObj.set(tName, VTask({
                isNative: true,
                name: '$name.$tName',
                native: func
            }));
        }
        coreScope.set(name, VObject(moduleObj));
    }

    /**
     * Pre-loads and caches a resource for execution.
     */
    final public function load(resource:Resource, ?stack:Array<String>):Expr {
        if (stack == null) stack = [];

        // Check cache using resource ID
        var cached = resourceCache.get(resource.id);
        if (cached != null && cached.ast != null) return cached.ast;
        
        // Circular Dependency Check
        if (stack.indexOf(resource.id) != -1) throw HankErrorRegistry.create(CircularDependency, [resource.id]);
        
        // Ensure we are working with the cached instance if it exists, otherwise cache this one
        if (cached == null) {
            resourceCache.set(resource.id, resource);
            cached = resource;
        }

        cached.load();
        if (cached.content == null) throw HankErrorRegistry.create(ResourceContentNotLoaded, [cached.id]);

        var newStack = stack.copy();
        newStack.push(cached.id);

        var lexer = new Lexer(cached.content);
        var parser = new Parser(lexer.tokenize(), cached.id, function(macroPath) {
            var mRes = cached.resolve(macroPath);
            return load(mRes, newStack);
        });
        
        cached.ast = parser.parse();
        return cached.ast;
    }

    /**
     * Removes a resource and its AST from the cache.
     */
    public function unload(resource:Resource) {
        resourceCache.remove(resource.id);
    }

    /**
     * Executes a Hank Resource.
     */
    public function run(resource:Resource, ?args:Array<Value>):Value {
        if (args == null) args = [];
        var ast = load(resource);

        var interpreter = new Interpreter(null, coreScope);
        var scriptTask = interpreter.run(ast);

        return switch (scriptTask) {
            case VTask(_): interpreter.call(scriptTask, args);
            default: throw HankErrorRegistry.create(ScriptMustBeTask);
        }
    }
}
