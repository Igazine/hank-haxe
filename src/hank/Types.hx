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

interface IHankSerializable {
    function serializeHank():String;
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

enum abstract HankError(Int) to Int from Int {
    // Lexical Errors (10xx)
    var UnexpectedCharacter = 1001;
    var UnclosedStringLiteral = 1002;

    // Syntax Errors (20xx)
    var EmptyScript = 2001;
    var ExpectedMainTask = 2002;
    var UnexpectedCodeOutsideMainTask = 2003;
    var InvalidAssignmentTarget = 2004;
    var UnexpectedToken = 2005;
    var MacroRequiresString = 2006;
    var ExpectedIdentifier = 2007;

    // Resolution & Runner Errors (30xx)
    var CircularDependency = 3001;
    var ResourceContentNotLoaded = 3002;
    var ScriptMustBeTask = 3003;
    var MacroResourceNotFound = 3004;

    // Runtime Errors (40xx)
    var TargetNotFunction = 4001;
    var TooManyArguments = 4002;
    var MissingRequiredParameter = 4003;
    var Halt = 4004;
    var GenericRuntimeError = 4005;
}

typedef HankErrorValue = {
    var code:HankError;
    var message:String;
}

class HankErrorRegistry {
    public static var messages:Map<HankError, String> = [
        UnexpectedCharacter => "Unexpected character: {0}",
        UnclosedStringLiteral => "Unclosed string literal",
        
        EmptyScript => "Syntax Error: Script is empty.",
        ExpectedMainTask => "Syntax Error: Expected main task definition (a closure or a block).",
        UnexpectedCodeOutsideMainTask => "Syntax Error: Unexpected code outside of main task. A Hank script must contain exactly one Task definition.",
        InvalidAssignmentTarget => "Invalid assignment target",
        UnexpectedToken => "Unexpected token: {0} ({1})",
        MacroRequiresString => "Syntax Error: The '@' macro strictly requires a string literal path (e.g., @ \"utils\"). Identifier shorthand is not allowed.",
        ExpectedIdentifier => "Expected identifier, found {0}",
        
        CircularDependency => "Circular Dependency: {0}",
        ResourceContentNotLoaded => "Resource content not loaded: {0}",
        ScriptMustBeTask => "Hank Error: Script must evaluate to a Task definition.",
        MacroResourceNotFound => "Macro resource not found: @{0}",
        
        TargetNotFunction => "Target is not a function: {0}",
        TooManyArguments => "Too many arguments",
        MissingRequiredParameter => "Missing required parameter: {0}",
        Halt => "HANK_HALT:{0}",
        GenericRuntimeError => "{0}"
    ];

    public static function create(code:HankError, ?args:Array<Dynamic>, ?fileName:String, ?line:Int, ?lineText:String):HankErrorValue {
        var tmpl = messages.get(code);
        if (tmpl == null) tmpl = "Unknown Error";

        if (args != null) {
            for (i in 0...args.length) {
                tmpl = StringTools.replace(tmpl, '{' + i + '}', Std.string(args[i]));
            }
        }

        if (fileName != null && line != null && lineText != null) {
            tmpl = 'ERROR: $tmpl in $fileName at\n\t$line:\t$lineText';
        }

        return { code: code, message: tmpl };
    }
}
