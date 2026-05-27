package hank;

enum ValueType {
    TypeVoid;
    TypeNumber;
    TypeString;
    TypeArray;
    TypeObject;
    TypeOpaque;
    TypeTask;
}

enum Value {
    VVoid;
    VNumber(v:Float);
    VString(v:String);
    VArray(v:Array<Value>);
    VObject(v:Map<String, Value>);
    VOpaque(label:String, data:Dynamic);
    VTask(v:TaskValue);
}

typedef TaskValue = {
    var isNative:Bool;
    var name:String;
    @:optional var params:Array<Param>;
    @:optional var body:Expr;
    @:optional var closure:Scope;
    @:optional var native:Array<Value>->ExecutionContext->Value;
}

typedef Param = {
    var name:String;
    var isOptional:Bool;
    @:optional var defaultValue:Expr;
}

interface ExecutionContext {
    function call(task:Value, args:Array<Value>):Value;
    function eval(node:Expr):Value;
    var scope(get, never):Scope;
}

interface Scope {
    function get(name:String):Value;
    function set(name:String, val:Value):Void;
    function exists(name:String):Bool;
}

typedef TokenData = {
    var line:Int;
    var lineText:String;
}

enum Expr {
    EBlock(stmts:Array<Expr>, td:TokenData);
    EAssign(name:String, value:Expr, td:TokenData);
    ELiteral(value:Value, td:TokenData);
    EIdent(name:String, isCore:Bool, td:TokenData);
    EField(object:Expr, fieldName:String, td:TokenData);
    EFuncDef(params:Array<Param>, body:Expr, td:TokenData);
    EFuncCall(target:Expr, args:Array<Expr>, td:TokenData);
    EUnOp(op:String, target:Expr, td:TokenData);
    EObject(fields:Map<String, Expr>, td:TokenData);
    EArray(items:Array<Expr>, td:TokenData);
    EFlowControl(condition:Expr, success:Expr, ?fallback:Expr, ?rescue:Expr, ?catchVar:String, td:TokenData);
}

interface IHALSerializable {
    function serializeHAL():String;
}

class ValueTools {
    public static function getType(v:Value):ValueType {
        return switch (v) {
            case VVoid: TypeVoid;
            case VNumber(_): TypeNumber;
            case VString(_): TypeString;
            case VArray(_): TypeArray;
            case VObject(_): TypeObject;
            case VOpaque(_, _): TypeOpaque;
            case VTask(_): TypeTask;
        }
    }

    public static function toString(v:Value):String {
        return switch (v) {
            case VVoid: "Void";
            case VNumber(n): 
                var s = Std.string(n);
                if (StringTools.endsWith(s, ".0")) s = s.substring(0, s.length - 2);
                s;
            case VString(s): s;
            case VArray(_): "[Array]";
            case VObject(_): "{Object}";
            case VOpaque(label, _): '[Opaque:$label]';
            case VTask(_): "[Task]";
        }
    }
}

class ExprTools {
    public static function getTd(e:Expr):TokenData {
        return switch (e) {
            case EBlock(_, td) | EAssign(_, _, td) | ELiteral(_, td) | EIdent(_, _, td) | EField(_, _, td) | EFuncDef(_, _, td) | EFuncCall(_, _, td) | EUnOp(_, _, td) | EObject(_, td) | EArray(_, td) | EFlowControl(_, _, _, _, _, td): td;
        }
    }
}
