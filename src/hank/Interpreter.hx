package hank;

import hank.Types;

enum EvalResult {
    Value(v:Value);
    Return(v:Value);
    Break;
    Error(v:Value); // VError
}

class Interpreter implements ExecutionContext {
    public var globalScope:Scope;
    var coreScope:Scope;

    public var scope(get, never):Scope;
    function get_scope():Scope return globalScope;

    public function new(?parentScope:Scope, coreScope:Scope, ?localization:Map<Int, String>) {
        this.coreScope = coreScope;
        this.globalScope = new HankScope(parentScope != null ? parentScope : coreScope);
        this.localization = localization != null ? localization : new Map();
    }

    var localization:Map<Int, String>;
    public function getLocalization():Map<Int, String> return localization;

    public function run(ast:Expr):Value {
        return switch (evalInScope(ast, globalScope)) {
            case Value(v) | Return(v): v;
            case Break: VVoid;
            case Error(v): v;
        }
    }

    public function eval(node:Expr):Value {
        return switch (evalInScope(node, globalScope)) {
            case Value(v) | Return(v): v;
            case Break: VOpaque("__ControlFlow", "Break");
            case Error(v): v;
        }
    }

    public function isError(v:Value):Bool {
        return switch (v) {
            case VError(_, _): true;
            default: false;
        }
    }

    function evalInScope(node:Expr, scope:Scope):EvalResult {
        return switch (node) {
            case ELiteral(v, _): Value(v);
            case EError(code, args, _):
                var evaluatedArgs = [];
                for (arg in args) {
                    switch (evalInScope(arg, scope)) {
                        case Value(v): evaluatedArgs.push(v);
                        case other: return other;
                    }
                }
                Value(VError(code, evaluatedArgs));
            case EIdent(name, isCore, _):
                Value(isCore ? coreScope.get(name) : scope.get(name));
            case EAssign(name, valExpr, _):
                var res = evalInScope(valExpr, scope);
                switch (res) {
                    case Value(v):
                        scope.set(name, v);
                        return Value(v);
                    case other: return other;
                }
            case EBlock(stmts, _):
                // --- TASK HOISTING PASS ---
                for (stmt in stmts) {
                    switch (stmt) {
                        case EAssign(name, valExpr, _):
                            switch (valExpr) {
                                case EFuncDef(_, _, _):
                                    switch (evalInScope(valExpr, scope)) {
                                        case Value(v): scope.set(name, v);
                                        default:
                                    }
                                case EAssign(innerName, innerVal, _):
                                    // Nested macro hoisting
                                    switch (innerVal) {
                                        case EFuncDef(_, _, _):
                                            switch (evalInScope(innerVal, scope)) {
                                                case Value(v): scope.set(innerName, v);
                                                default:
                                            }
                                        default:
                                    }
                                default:
                            }
                        default:
                    }
                }

                var last:Value = VVoid;
                for (stmt in stmts) {
                    // Skip already hoisted tasks in eval pass
                    switch (stmt) {
                        case EAssign(_, valExpr, _):
                            switch (valExpr) {
                                case EFuncDef(_, _, _): continue;
                                case EAssign(_, innerVal, _):
                                    switch (innerVal) {
                                        case EFuncDef(_, _, _): continue;
                                        default:
                                    }
                                default:
                            }
                        default:
                    }

                    var res = evalInScope(stmt, scope);
                    switch (res) {
                        case Value(v): last = v;
                        case other: return other;
                    }
                }
                Value(last);

            case EFuncDef(params, body, _):
                Value(VTask({
                    isNative: false,
                    name: "anonymous",
                    params: params,
                    body: body,
                    closure: scope
                }));

            case EFuncCall(targetExpr, argExprs, _):
                var tRes = evalInScope(targetExpr, scope);
                switch (tRes) {
                    case Value(target):
                        var args = [];
                        for (argExpr in argExprs) {
                            var aRes = evalInScope(argExpr, scope);
                            switch (aRes) {
                                case Value(v): args.push(v);
                                case other: return other;
                            }
                        }
                        return callInternal(target, args, scope);
                    case other: return other;
                }

            case EField(objExpr, fieldName, _):
                var oRes = evalInScope(objExpr, scope);
                switch (oRes) {
                    case Value(v):
                        switch (v) {
                            case VObject(map):
                                return Value(map.exists(fieldName) ? map.get(fieldName) : VVoid);
                            case VArray(vec) if (fieldName == "length"):
                                return Value(VNumber(vec.length));
                            case VString(s) if (fieldName == "length"):
                                return Value(VNumber(s.length));
                            default: return Value(VVoid);
                        }
                    case other: return other;
                }

            case EObject(fields, _):
                var map = new Map<String, Value>();
                for (k => vExpr in fields) {
                    var res = evalInScope(vExpr, scope);
                    switch (res) {
                        case Value(v): map.set(k, v);
                        case other: return other;
                    }
                }
                Value(VObject(map));

            case EArray(items, _):
                var vec = [];
                for (itemExpr in items) {
                    var res = evalInScope(itemExpr, scope);
                    switch (res) {
                        case Value(v): vec.push(v);
                        case other: return other;
                    }
                }
                Value(VArray(vec));

            case EUnOp(op, target, _):
                var res = evalInScope(target, scope);
                switch (res) {
                    case Value(val):
                        switch (op) {
                            case "!": return Value(isTruthy(val) ? VVoid : VNumber(1));
                            case "?": return Value(val);
                            case "^": return Return(val);
                            default: return Value(VVoid);
                        }
                    case other: return other;
                }

            case EFlowControl(condition, success, fallback, rescue, catchVar, _):
                var condRes = evalInScope(condition, scope);
                var branchRes:EvalResult = null;

                switch (condRes) {
                    case Value(condVal):
                        if (isTruthy(condVal)) {
                            branchRes = evalInScope(success, scope);
                        } else if (fallback != null) {
                            branchRes = evalInScope(fallback, scope);
                        } else {
                            branchRes = Value(VVoid);
                        }
                    case other: branchRes = other;
                }

                switch (branchRes) {
                    case Error(err) if (rescue != null):
                        var rescueScope = new HankScope(scope);
                        if (catchVar != null) rescueScope.set(catchVar, err);
                        return evalInScope(rescue, rescueScope);
                    default: return branchRes;
                }
        }
    }

    function callInternal(task:Value, args:Array<Value>, scope:Scope):EvalResult {
        return switch (task) {
            case VTask(t):
                if (t.isNative) {
                    try {
                        var res = t.native(args, this);
                        switch (res) {
                            case VOpaque(l, d) if (l == "__ControlFlow" && Std.string(d) == "Break"): return Break;
                            case VError(_, _): return Error(res);
                            default: return Value(res);
                        }
                    } catch (e:Dynamic) {
                        return Error(VError(4006, [VString(Std.string(e))]));
                    }
                } else {
                    if (args.length > t.params.length) {
                        return Error(VError(4002, []));
                    }
                    
                    var taskScope = new HankScope(t.closure);
                    for (i in 0...t.params.length) {
                        var p = t.params[i];
                        var val:Value = VVoid;
                        if (i < args.length) {
                            val = args[i];
                        } else if (p.defaultValue != null) {
                            var res = evalInScope(p.defaultValue, taskScope);
                            switch (res) {
                                case Value(v): val = v;
                                case other: return other;
                            }
                        } else if (!p.isOptional) {
                            return Error(VError(4003, [VString(p.name)]));
                        }
                        taskScope.set(p.name, val);
                    }
                    
                    var res = evalInScope(t.body, taskScope);
                    switch (res) {
                        case Value(v) | Return(v):
                            if (isError(v)) return Error(v) else return Value(v);
                        case other: return other;
                    }
                }
            default:
                Error(VError(4001, [VString(ValueTools.toString(task))]));
        }
    }

    public function call(task:Value, args:Array<Value>):Value {
        var finalArgs = args;
        switch (task) {
            case VTask(t) if (!t.isNative && t.params != null):
                if (args.length > t.params.length) {
                    finalArgs = args.slice(0, t.params.length);
                }
            default:
        }
        var res = callInternal(task, finalArgs, globalScope);
        return switch (res) {
            case Value(v) | Return(v): v;
            case Error(v): v;
            case Break: VOpaque("__ControlFlow", "Break");
        }
    }

    function isTruthy(v:Value):Bool {
        return switch (v) {
            case VVoid: false;
            default: true;
        }
    }
}

class HankScope implements Scope {
    var values:Map<String, Value> = new Map();
    var parent:Scope;

    public function new(?parent:Scope) {
        this.parent = parent;
    }

    public function get(name:String):Value {
        if (values.exists(name)) return values.get(name);
        if (parent != null) return parent.get(name);
        return VVoid;
    }

    public function set(name:String, val:Value):Void {
        values.set(name, val);
    }

    public function exists(name:String):Bool {
        return values.exists(name) || (parent != null && parent.exists(name));
    }
}
