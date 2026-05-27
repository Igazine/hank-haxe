package hank;

import hank.Types;

enum EvalResult {
    Value(v:Value);
    Return(v:Value);
    Error(msg:String);
}

class Interpreter implements ExecutionContext {
    public var globalScope:Scope;
    var coreScope:Scope;

    public var scope(get, never):Scope;
    function get_scope():Scope return globalScope;

    public function new(?parentScope:Scope, coreScope:Scope) {
        this.coreScope = coreScope;
        this.globalScope = new HALScope(parentScope != null ? parentScope : coreScope);
    }

    public function run(ast:Expr):Value {
        return switch (evalInScope(ast, globalScope)) {
            case Value(v) | Return(v): v;
            case Error(msg):
                Sys.stderr().writeString('Runtime Error: $msg\n');
                VVoid;
        }
    }

    public function eval(node:Expr):Value {
        return switch (evalInScope(node, globalScope)) {
            case Value(v) | Return(v): v;
            case Error(msg): throw msg;
        }
    }

    function evalInScope(node:Expr, scope:Scope):EvalResult {
        return switch (node) {
            case ELiteral(v, _): Value(v);
            case EIdent(name, isCore, _):
                Value(isCore ? coreScope.get(name) : scope.get(name));
            case EAssign(name, valExpr, _):
                switch (evalInScope(valExpr, scope)) {
                    case Value(v):
                        scope.set(name, v);
                        Value(v);
                    case other: other;
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

                    switch (evalInScope(stmt, scope)) {
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
                switch (evalInScope(targetExpr, scope)) {
                    case Value(target):
                        var args = [];
                        for (argExpr in argExprs) {
                            switch (evalInScope(argExpr, scope)) {
                                case Value(v): args.push(v);
                                case other: return other;
                            }
                        }
                        callInternal(target, args, scope);
                    case other: other;
                }

            case EField(objExpr, fieldName, _):
                switch (evalInScope(objExpr, scope)) {
                    case Value(VObject(map)):
                        Value(map.exists(fieldName) ? map.get(fieldName) : VVoid);
                    case Value(VArray(vec)) if (fieldName == "length"):
                        Value(VNumber(vec.length));
                    case Value(VString(s)) if (fieldName == "length"):
                        Value(VNumber(s.length));
                    case Value(_): Value(VVoid);
                    case other: other;
                }

            case EObject(fields, _):
                var map = new Map<String, Value>();
                for (k => vExpr in fields) {
                    switch (evalInScope(vExpr, scope)) {
                        case Value(v): map.set(k, v);
                        case other: return other;
                    }
                }
                Value(VObject(map));

            case EArray(items, _):
                var vec = [];
                for (itemExpr in items) {
                    switch (evalInScope(itemExpr, scope)) {
                        case Value(v): vec.push(v);
                        case other: return other;
                    }
                }
                Value(VArray(vec));

            case EUnOp(op, target, _):
                switch (evalInScope(target, scope)) {
                    case Value(val):
                        switch (op) {
                            case "!": Value(isTruthy(val) ? VVoid : VNumber(1));
                            case "?": Value(val);
                            case "^": Return(val);
                            default: Value(VVoid);
                        }
                    case other: other;
                }

            case EFlowControl(condition, success, fallback, rescue, catchVar, _):
                switch (evalInScope(condition, scope)) {
                    case Value(condVal):
                        var res = if (isTruthy(condVal)) {
                            evalInScope(success, scope);
                        } else if (fallback != null) {
                            evalInScope(fallback, scope);
                        } else {
                            Value(VVoid);
                        }

                        switch (res) {
                            case Error(errMsg):
                                if (rescue != null) {
                                    var rescueScope = new HALScope(scope);
                                    if (catchVar != null) rescueScope.set(catchVar, VString(errMsg));
                                    evalInScope(rescue, rescueScope);
                                } else res;
                            default: res;
                        }
                    case other: other;
                }
        }
    }

    function callInternal(task:Value, args:Array<Value>, scope:Scope):EvalResult {
        return switch (task) {
            case VTask(t):
                if (t.isNative) {
                    Value(t.native(args, this));
                } else {
                    if (args.length > t.params.length) return Error("Too many arguments");
                    
                    var taskScope = new HALScope(t.closure);
                    for (i in 0...t.params.length) {
                        var p = t.params[i];
                        var val:Value = VVoid;
                        if (i < args.length) {
                            val = args[i];
                        } else if (p.defaultValue != null) {
                            switch (evalInScope(p.defaultValue, taskScope)) {
                                case Value(v): val = v;
                                case other: return other;
                            }
                        } else if (!p.isOptional) {
                            return Error('Missing required parameter: ${p.name}');
                        }
                        taskScope.set(p.name, val);
                    }
                    
                    switch (evalInScope(t.body, taskScope)) {
                        case Value(v) | Return(v): Value(v);
                        case other: other;
                    }
                }
            default: Error('Target is not a function: ${ValueTools.toString(task)}');
        }
    }

    public function call(task:Value, args:Array<Value>):Value {
        return switch (callInternal(task, args, globalScope)) {
            case Value(v) | Return(v): v;
            case Error(msg): throw msg;
        }
    }

    function isTruthy(v:Value):Bool {
        return switch (v) {
            case VVoid: false;
            default: true;
        }
    }
}

class HALScope implements Scope {
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
