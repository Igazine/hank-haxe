package hank.ext;

import hank.Types;

class PlatformExtension implements IExtension {
    public var name(default, null):String = "PlatformExtension";

    public function new() {}

    private static inline var SAFE_INT_MAX:Float = 9007199254740991.0;

    private static function checkSafeInt(n:Float, taskName:String):Value {
        if (Math.abs(n) > SAFE_INT_MAX || !Math.isFinite(n)) {
            return VError(4005, [VNumber(n), VString(taskName)]);
        }
        return VVoid; // Success signal
    }

    private static function fromSafeInt(n:haxe.Int64, taskName:String):Value {
        var f = Std.parseFloat(haxe.Int64.toStr(n));
        if (Math.abs(f) > SAFE_INT_MAX) {
            return VError(4005, [VNumber(f), VString(taskName)]);
        }
        return VNumber(f);
    }

    public function getModules():Map<String, Map<String, Array<Value>->ExecutionContext->Value>> {
        var mods = new Map<String, Map<String, Array<Value>->ExecutionContext->Value>>();

        mods.set("bin", [
            "and" => (args, ctx) -> {
                var a:Float = 0;
                var b:Float = 0;
                switch (args[0]) {
                    case VNumber(n): a = n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.and")]);
                }
                switch (args[1]) {
                    case VNumber(n): b = n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.and")]);
                }

                var err = checkSafeInt(a, "bin.and");
                if (ctx.isError(err)) return err;
                err = checkSafeInt(b, "bin.and");
                if (ctx.isError(err)) return err;

                return fromSafeInt(haxe.Int64.fromFloat(a) & haxe.Int64.fromFloat(b), "bin.and");
            },
            "or" => (args, ctx) -> {
                var a:Float = 0;
                var b:Float = 0;
                switch (args[0]) {
                    case VNumber(n): a = n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.or")]);
                }
                switch (args[1]) {
                    case VNumber(n): b = n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.or")]);
                }

                var err = checkSafeInt(a, "bin.or");
                if (ctx.isError(err)) return err;
                err = checkSafeInt(b, "bin.or");
                if (ctx.isError(err)) return err;

                return fromSafeInt(haxe.Int64.fromFloat(a) | haxe.Int64.fromFloat(b), "bin.or");
            },
            "xor" => (args, ctx) -> {
                var a:Float = 0;
                var b:Float = 0;
                switch (args[0]) {
                    case VNumber(n): a = n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.xor")]);
                }
                switch (args[1]) {
                    case VNumber(n): b = n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.xor")]);
                }

                var err = checkSafeInt(a, "bin.xor");
                if (ctx.isError(err)) return err;
                err = checkSafeInt(b, "bin.xor");
                if (ctx.isError(err)) return err;

                return fromSafeInt(haxe.Int64.fromFloat(a) ^ haxe.Int64.fromFloat(b), "bin.xor");
            },
            "not" => (args, ctx) -> {
                var a:Float = 0;
                switch (args[0]) {
                    case VNumber(n): a = n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.not")]);
                }
                var err = checkSafeInt(a, "bin.not");
                if (ctx.isError(err)) return err;

                return fromSafeInt(~haxe.Int64.fromFloat(a), "bin.not");
            },
            "shiftL" => (args, ctx) -> {
                var a:Float = 0;
                var b:Int = 0;
                switch (args[0]) {
                    case VNumber(n): a = n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.shiftL")]);
                }
                switch (args[1]) {
                    case VNumber(n): b = Std.int(n);
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.shiftL")]);
                }

                var err = checkSafeInt(a, "bin.shiftL");
                if (ctx.isError(err)) return err;

                return fromSafeInt(haxe.Int64.fromFloat(a) << b, "bin.shiftL");
            },
            "shiftR" => (args, ctx) -> {
                var a:Float = 0;
                var b:Int = 0;
                switch (args[0]) {
                    case VNumber(n): a = n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.shiftR")]);
                }
                switch (args[1]) {
                    case VNumber(n): b = Std.int(n);
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("bin.shiftR")]);
                }

                var err = checkSafeInt(a, "bin.shiftR");
                if (ctx.isError(err)) return err;

                return fromSafeInt(haxe.Int64.fromFloat(a) >> b, "bin.shiftR");
            }
        ]);

        return mods;
    }
}
