package hank;

import hank.Types;
import hank.Lexer;
import hank.Parser;
import hank.Interpreter;

/**
 * A base class for HAL Host Runners in Haxe.
 * Handles script loading, macro resolution, and AST caching.
 * Environment-agnostic: must be extended to provide I/O.
 */
class Runner {
    var pathCache:Map<String, String> = new Map();
    var astCache:Map<String, Expr> = new Map();
    var macroMap:Map<String, String> = new Map();
    public var coreScope:Scope = new HALScope();

    public function new() {}

    /**
     * Reads a file from the host environment.
     */
    public function readFile(path:String):String {
        throw "Not implemented: readFile";
    }

    /**
     * Resolves a macro path relative to the current file.
     */
    public function resolvePath(macroPath:String, baseFile:String):String {
        throw "Not implemented: resolvePath";
    }

    /**
     * Registers a set of native tasks under a module name.
     */
    public function registerModule(name:String, tasks:Map<String, Array<Value>->ExecutionContext->Value>) {
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
     * Pre-loads and caches a script for execution.
     */
    public function load(scriptPath:String):String {
        var absPath = resolvePath(scriptPath, "");
        if (astCache.exists(absPath)) return absPath;

        preprocess(absPath, []);

        var content = pathCache.get(absPath);
        if (content == null) throw 'File not loaded: $absPath';

        var lexer = new Lexer(content);
        var parser = new Parser(lexer.tokenize(), absPath, macroMap);
        var ast = parser.parse();
        
        astCache.set(absPath, ast);
        return absPath;
    }

    /**
     * Removes a script from the cache.
     */
    public function unload(scriptPath:String) {
        var absPath = resolvePath(scriptPath, "");
        astCache.remove(absPath);
        pathCache.remove(absPath);
    }

    /**
     * Executes a HAL script.
     */
    public function run(scriptPath:String, ?args:Array<Value>):Value {
        if (args == null) args = [];
        var absPath = load(scriptPath);
        var ast = astCache.get(absPath);

        var interpreter = new Interpreter(null, coreScope);
        var scriptTask = interpreter.run(ast);

        return switch (scriptTask) {
            case VTask(_): interpreter.call(scriptTask, args);
            default: throw "HAL Error: Script must evaluate to a Task definition.";
        }
    }

    function preprocess(path:String, stack:Array<String>) {
        for (s in stack) if (s == path) throw 'Circular Dependency: $path';
        if (pathCache.exists(path)) return;

        var content = readFile(path);
        pathCache.set(path, content);
        
        var newStack = stack.copy();
        newStack.push(path);
        
        var macros = scanMacros(content);
        for (m in macros) {
            var mPath = resolvePath(m, path);
            preprocess(mPath, newStack);
            macroMap.set(m, pathCache.get(mPath));
        }
    }

    function scanMacros(content:String):Array<String> {
        var lexer = new Lexer(content);
        var tokens = lexer.tokenize();
        var macros = [];
        var i = 0;
        while (i < tokens.length - 1) {
            if (tokens[i].type == At) {
                var next = tokens[i+1];
                switch (next.type) {
                    case String | Identifier:
                        macros.push(next.literal);
                    default:
                }
            }
            i++;
        }
        return macros;
    }
}
