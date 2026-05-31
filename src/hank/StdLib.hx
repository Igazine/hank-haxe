package hank;

import hank.Types;
import haxe.Json;

class StdLib implements IExtension {
    public var name(default, null):String = "StdLib";
    public var envState:Map<String, Value>;

    public function new() {
        envState = new Map<String, Value>();
    }

    /**
     * Returns the recommended standard library tasks.
     * Developers should register these manually on their Runner.
     */
    public function getTasks():Map<String, Array<Value>->ExecutionContext->Value> {
        var valToString = (v:Value) -> ValueTools.toString(v);

        var mapAnyToHank:Dynamic->Value = null;
        mapAnyToHank = function(v:Dynamic):Value {
            if (v == null) return VVoid;
            if (Std.isOfType(v, Float)) return VNumber(cast v);
            if (Std.isOfType(v, Int)) return VNumber(cast v);
            if (Std.isOfType(v, String)) return VString(cast v);
            if (Std.isOfType(v, Bool)) return (v:Bool) ? VNumber(1.0) : VVoid;
            if (Std.isOfType(v, Array)) {
                var arr:Array<Dynamic> = cast v;
                return VArray(arr.map(mapAnyToHank));
            }
            if (Reflect.isObject(v)) {
                var map = new Map<String, Value>();
                for (f in Reflect.fields(v)) {
                    map.set(f, mapAnyToHank(Reflect.field(v, f)));
                }
                return VMap(map);
            }
            return VVoid;
        };

        var mapHankToAny:Value->Dynamic = null;
        mapHankToAny = function(v:Value):Dynamic {
            return switch (v) {
                case VNumber(n): n;
                case VString(s): s;
                case VArray(a): a.map(mapHankToAny);
                case VMap(m):
                    var obj = {};
                    for (k => val in m) {
                        var any = mapHankToAny(val);
                        if (any != null) Reflect.setField(obj, k, any);
                    }
                    obj;
                case VOpaque(_, _): null;
                default: null;
            };
        };

        var checkOpaque:Value->Bool = null;
        checkOpaque = function(v:Value):Bool {
            return switch (v) {
                case VOpaque(_, _): true;
                case VArray(a):
                    var found = false;
                    for (i in a) if (checkOpaque(i)) { found = true; break; }
                    found;
                case VMap(m):
                    var found = false;
                    for (_ => val in m) if (checkOpaque(val)) { found = true; break; }
                    found;
                default: false;
            };
        };

        var hankEquals:Value->Value->Bool = null;
        hankEquals = function(a:Value, b:Value):Bool {
            return switch [a, b] {
                case [VVoid, VVoid]: true;
                case [VNumber(n1), VNumber(n2)]: n1 == n2;
                case [VString(s1), VString(s2)]: s1 == s2;
                case [VArray(a1), VArray(a2)]:
                    if (a1.length != a2.length) return false;
                    for (i in 0...a1.length) if (!hankEquals(a1[i], a2[i])) return false;
                    true;
                case [VMap(o1), VMap(o2)]:
                    var k1 = [for (k in o1.keys()) k];
                    var k2 = [for (k in o2.keys()) k];
                    if (k1.length != k2.length) return false;
                    for (k in k1) if (!o2.exists(k) || !hankEquals(o1.get(k), o2.get(k))) return false;
                    true;
                case [VOpaque(l1, d1), VOpaque(l2, d2)]: l1 == l2 && d1 == d2;
                case [VError(c1, a1), VError(c2, a2)]:
                    if (c1 != c2 || a1.length != a2.length) return false;
                    for (i in 0...a1.length) if (!hankEquals(a1[i], a2[i])) return false;
                    true;
                default: false;
            };
        };

        var tasks = new Map<String, Array<Value>->ExecutionContext->Value>();

        // log
        tasks.set("log_print", (args, ctx) -> { Sys.println(args.map(valToString).join(" ")); VVoid; });
        tasks.set("log_error", (args, ctx) -> { Sys.stderr().writeString(args.map(valToString).join(" ") + "\n"); VVoid; });
        tasks.set("log_warn", (args, ctx) -> { Sys.println("[WARN] " + args.map(valToString).join(" ")); VVoid; });

        // runtime
        tasks.set("runtime_halt", (args, ctx) -> {
            var code = 0;
            if (args.length > 0) switch (args[0]) { case VNumber(n): code = Std.int(n); default: }
            Sys.exit(code);
            VVoid;
        });
        tasks.set("runtime_elapsedTime", (args, ctx) -> VNumber(haxe.Timer.stamp() * 1000));
        tasks.set("runtime_signal", (args, ctx) -> {
            if (args.length > 0) Sys.println('[SIGNAL] ' + valToString(args[0]));
            VVoid;
        });

        // loop
        tasks.set("loop_while", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            var cond = args[0];
            var body = args[1];
            var last:Value = VVoid;
            while (true) {
                var condVal = ctx.call(cond, []);
                if (ctx.isError(condVal)) return condVal;
                if (condVal == VVoid) break;
                
                var res = ctx.call(body, []);
                if (ctx.isError(res)) return res;

                var isBreak = false;
                switch (res) {
                    case VOpaque(l, d): 
                        if (l == "__ControlFlow" && Std.string(d) == "Break") isBreak = true;
                    default:
                }
                if (isBreak) break;

                last = res;
            }
            last;
        });
        tasks.set("loop_break", (args, ctx) -> VOpaque("__ControlFlow", "Break"));

        // env
        tasks.set("env_get", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            var key = valToString(args[0]);
            return envState.exists(key) ? envState.get(key) : VVoid;
        });
        tasks.set("env_set", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            var key = valToString(args[0]);
            envState.set(key, args[1]);
            return VVoid;
        });
        tasks.set("env_keys", (args, ctx) -> {
            var keys = [for (k in envState.keys()) VString(k)];
            return VArray(keys);
        });

        // str
        tasks.set("str_length", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            return switch (args[0]) {
                case VString(s): VNumber(s.length);
                case other: VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("str_length")]);
            }
        });
        tasks.set("str_format", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            var res = valToString(args[0]);
            for (i in 1...args.length) {
                res = StringTools.replace(res, '%$i', valToString(args[i]));
            }
            VString(res);
        });
        tasks.set("str_concat", (args, ctx) -> VString(args.map(valToString).join("")));
        tasks.set("str_trim", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            return switch (args[0]) {
                case VString(s): VString(StringTools.trim(s));
                case other: VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("str_trim")]);
            }
        });

        // num
        tasks.set("num_parse", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            var s = valToString(args[0]);
            var base = 0;
            if (args.length > 1) switch (args[1]) { case VNumber(n): base = Std.int(n); default: }
            
            if (base == 0) {
                if (StringTools.startsWith(s, "0x")) base = 16;
                else if (StringTools.startsWith(s, "0b")) base = 2;
                else if (StringTools.startsWith(s, "0o")) base = 8;
                else base = 10;
            }

            if (base == 16 || base == 10 || base == 8 || base == 2) {
                var n = Std.parseInt(s);
                return n == null ? VVoid : VNumber(n);
            }

            // Custom base (up to 36)
            var chars = "0123456789abcdefghijklmnopqrstuvwxyz";
            var res = 0.0;
            s = s.toLowerCase();
            for (i in 0...s.length) {
                var idx = chars.indexOf(s.charAt(i));
                if (idx == -1 || idx >= base) return VVoid;
                res = res * base + idx;
            }
            VNumber(res);
        });
        tasks.set("num_format", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            var n = 0; switch (args[0]) { case VNumber(val): n = Std.int(val); default: return VVoid; }
            var base = 10; if (args.length > 1) switch (args[1]) { case VNumber(val): base = Std.int(val); default: }
            if (base < 2 || base > 36) return VVoid;

            var chars = "0123456789abcdefghijklmnopqrstuvwxyz";
            if (n == 0) return VString("0");
            var res = "";
            var isNeg = n < 0;
            if (isNeg) n = -n;
            while (n > 0) {
                res = chars.charAt(n % base) + res;
                n = Std.int(n / base);
            }
            VString((isNeg ? "-" : "") + res);
        });

        // math
        tasks.set("math_add", (args, ctx) -> {
            var sum = 0.0;
            for (a in args) {
                switch (a) {
                    case VNumber(n): sum += n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_add")]);
                }
            }
            VNumber(sum);
        });
        tasks.set("math_sub", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            var a = 0.0;
            var b = 0.0;
            switch (args[0]) {
                case VNumber(n): a = n;
                case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_sub")]);
            }
            switch (args[1]) {
                case VNumber(n): b = n;
                case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_sub")]);
            }
            VNumber(a - b);
        });
        tasks.set("math_mul", (args, ctx) -> {
            if (args.length == 0) return VNumber(0.0);
            var res = 1.0;
            for (a in args) {
                switch (a) {
                    case VNumber(n): res *= n;
                    case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_mul")]);
                }
            }
            VNumber(res);
        });
        tasks.set("math_div", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            var a = 0.0;
            var b = 0.0;
            switch (args[0]) {
                case VNumber(n): a = n;
                case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_div")]);
            }
            switch (args[1]) {
                case VNumber(n): b = n;
                case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_div")]);
            }
            if (b == 0) VVoid else VNumber(a / b);
        });
        tasks.set("math_mod", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            var a = 0.0;
            var b = 0.0;
            switch (args[0]) {
                case VNumber(n): a = n;
                case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_mod")]);
            }
            switch (args[1]) {
                case VNumber(n): b = n;
                case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_mod")]);
            }
            if (b == 0) VVoid else VNumber(a % b);
        });
        tasks.set("math_gt", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            var a = 0.0;
            var b = 0.0;
            switch (args[0]) {
                case VNumber(n): a = n;
                case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_gt")]);
            }
            switch (args[1]) {
                case VNumber(n): b = n;
                case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_gt")]);
            }
            if (a > b) VNumber(1.0) else VVoid;
        });
        tasks.set("math_lt", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            var a = 0.0;
            var b = 0.0;
            switch (args[0]) {
                case VNumber(n): a = n;
                case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_lt")]);
            }
            switch (args[1]) {
                case VNumber(n): b = n;
                case other: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("math_lt")]);
            }
            if (a < b) VNumber(1.0) else VVoid;
        });
        tasks.set("math_eq", (args, ctx) -> (args.length < 2) ? VVoid : (hankEquals(args[0], args[1]) ? VNumber(1.0) : VVoid));

        // logic
        tasks.set("logic_and", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            var last = VVoid;
            for (a in args) if (a == VVoid) return VVoid else last = a;
            last;
        });
        tasks.set("logic_or", (args, ctx) -> {
            for (a in args) if (a != VVoid) return a;
            VVoid;
        });
        tasks.set("logic_eq", (args, ctx) -> (args.length < 2) ? VVoid : (hankEquals(args[0], args[1]) ? VNumber(1.0) : VVoid));

        // type
        tasks.set("type_isVoid", (args, ctx) -> (args.length > 0 && args[0] == VVoid) ? VNumber(1.0) : VVoid);
        tasks.set("type_isNumber", (args, ctx) -> (args.length > 0 && args[0].match(VNumber(_))) ? VNumber(1.0) : VVoid);
        tasks.set("type_isString", (args, ctx) -> (args.length > 0 && args[0].match(VString(_))) ? VNumber(1.0) : VVoid);
        tasks.set("type_isArray", (args, ctx) -> (args.length > 0 && args[0].match(VArray(_))) ? VNumber(1.0) : VVoid);
        tasks.set("type_isMap", (args, ctx) -> (args.length > 0 && args[0].match(VMap(_))) ? VNumber(1.0) : VVoid);
        tasks.set("type_isOpaque", (args, ctx) -> (args.length > 0 && args[0].match(VOpaque(_, _))) ? VNumber(1.0) : VVoid);
        tasks.set("type_isTask", (args, ctx) -> (args.length > 0 && args[0].match(VTask(_))) ? VNumber(1.0) : VVoid);
        tasks.set("type_isError", (args, ctx) -> (args.length > 0 && args[0].match(VError(_, _))) ? VNumber(1.0) : VVoid);

        // arr
        tasks.set("arr_length", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            return switch (args[0]) {
                case VArray(a): VNumber(a.length);
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_length")]);
            }
        });
        tasks.set("arr_get", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            return switch (args[0]) {
                case VArray(a):
                    switch (args[1]) {
                        case VNumber(n):
                            var idx = Std.int(n);
                            if (idx < 0 || idx >= a.length) VVoid else a[idx];
                        case other: VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_get")]);
                    }
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_get")]);
            }
        });
        tasks.set("arr_push", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            return switch (args[0]) {
                case VArray(a): a.push(args[1]); VVoid;
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_push")]);
            }
        });
        tasks.set("arr_pop", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            return switch (args[0]) {
                case VArray(a): if (a.length > 0) a.pop() else VVoid;
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_pop")]);
            }
        });
        tasks.set("arr_shift", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            return switch (args[0]) {
                case VArray(a): if (a.length > 0) a.shift() else VVoid;
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_shift")]);
            }
        });
        tasks.set("arr_unshift", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            return switch (args[0]) {
                case VArray(a): a.unshift(args[1]); VVoid;
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_unshift")]);
            }
        });
        tasks.set("arr_slice", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            return switch (args[0]) {
                case VArray(a):
                    var start = 0; switch (args[1]) { case VNumber(n): start = Std.int(n); default: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(args[1]))), VString("arr_slice")]); }
                    var end = a.length; if (args.length > 2) switch (args[2]) { case VNumber(n): end = Std.int(n); default: return VError(4007, [VString("Number"), VString(ValueTools.typeToString(ValueTools.getType(args[2]))), VString("arr_slice")]); }
                    VArray(a.slice(start, end));
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_slice")]);
            }
        });
        tasks.set("arr_sort", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            return switch (args[0]) {
                case VArray(a):
                    if (args.length > 1) {
                        var task = args[1];
                        a.sort((x, y) -> {
                            var res = ctx.call(task, [x, y]);
                            switch (res) {
                                case VNumber(n): return Std.int(n);
                                default: return 0;
                            }
                        });
                    } else {
                        a.sort((x, y) -> {
                            var sx = valToString(x);
                            var sy = valToString(y);
                            return sx == sy ? 0 : (sx < sy ? -1 : 1);
                        });
                    }
                    VVoid;
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_sort")]);
            }
        });
        tasks.set("arr_indexof", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            return switch (args[0]) {
                case VArray(a):
                    var target = args[1];
                    var idx = -1;
                    for (i in 0...a.length) {
                        if (hankEquals(a[i], target)) { idx = i; break; }
                    }
                    if (idx == -1) VVoid else VNumber(idx);
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_indexof")]);
            }
        });
        tasks.set("arr_each", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            return switch (args[0]) {
                case VArray(a):
                    var task = args[1];
                    var items = a.copy();
                    for (i in 0...items.length) {
                        var res = ctx.call(task, [items[i], VNumber(i)]);
                        if (ctx.isError(res)) return res;

                        var isBreak = false;
                        switch (res) {
                            case VOpaque(l, d): if (l == "__ControlFlow" && Std.string(d) == "Break") isBreak = true;
                            default:
                        }
                        if (isBreak) break;
                    }
                    VVoid;
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_each")]);
            }
        });
        tasks.set("arr_map", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            return switch (args[0]) {
                case VArray(a):
                    var task = args[1];
                    var resArr = [];
                    for (i in 0...a.length) {
                        var res = ctx.call(task, [a[i], VNumber(i)]);
                        if (ctx.isError(res)) return res;
                        resArr.push(res);
                    }
                    VArray(resArr);
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_map")]);
            }
        });
        tasks.set("arr_filter", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            return switch (args[0]) {
                case VArray(a):
                    var task = args[1];
                    var resArr = [];
                    for (i in 0...a.length) {
                        var res = ctx.call(task, [a[i], VNumber(i)]);
                        if (ctx.isError(res)) return res;
                        if (res != VVoid) resArr.push(a[i]);
                    }
                    VArray(resArr);
                case other: VError(4007, [VString("Array"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("arr_filter")]);
            }
        });

        // map
        tasks.set("map_get", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            return switch (args[0]) {
                case VMap(m):
                    var key = valToString(args[1]);
                    if (m.exists(key)) m.get(key) else VVoid;
                default: VVoid;
            }
        });
        tasks.set("map_set", (args, ctx) -> {
            if (args.length < 3) return VVoid;
            return switch (args[0]) {
                case VMap(m):
                    var key = valToString(args[1]);
                    m.set(key, args[2]);
                    VVoid;
                case other: VError(4007, [VString("Map"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("map_set")]);
            }
        });
        tasks.set("map_remove", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            return switch (args[0]) {
                case VMap(m):
                    var key = valToString(args[1]);
                    if (m.exists(key)) {
                        m.remove(key);
                        VNumber(1.0);
                    } else VVoid;
                case other: VError(4007, [VString("Map"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("map_remove")]);
            }
        });
        tasks.set("map_keys", (args, ctx) -> switch (args[0]) {
            case VMap(m):
                var keys = [];
                for (k in m.keys()) keys.push(VString(k));
                VArray(keys);
            default: VVoid;
        });

        // json
        tasks.set("json_parse", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            try {
                return mapAnyToHank(Json.parse(valToString(args[0])));
            } catch (e:Dynamic) return VVoid;
        });
        tasks.set("json_stringify", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            if (checkOpaque(args[0])) return VVoid;
            try {
                return VString(Json.stringify(mapHankToAny(args[0])));
            } catch (e:Dynamic) return VVoid;
        });

        // regex
        tasks.set("regex_parse", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            var pattern = valToString(args[0]);
            var flags = args.length > 1 ? valToString(args[1]) : "";
            try {
                return VOpaque("RegExp", new EReg(pattern, flags));
            } catch (e:Dynamic) return VVoid;
        });
        tasks.set("regex_match", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            var s = valToString(args[0]);
            return switch (args[1]) {
                case VOpaque("RegExp", re):
                    var ereg:EReg = cast re;
                    ereg.match(s) ? VNumber(1.0) : VVoid;
                default:
                    StringTools.contains(s, valToString(args[1])) ? VNumber(1.0) : VVoid;
            }
        });
        tasks.set("regex_replace", (args, ctx) -> {
            if (args.length < 3) return VVoid;
            var s = valToString(args[0]);
            var repl = valToString(args[2]);
            return switch (args[1]) {
                case VOpaque("RegExp", re):
                    var ereg:EReg = cast re;
                    VString(ereg.replace(s, repl));
                default:
                    VString(StringTools.replace(s, valToString(args[1]), repl));
            }
        });

        // err
        tasks.set("err_code", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            return switch (args[0]) {
                case VError(code, _): VNumber(code);
                case other: VError(4007, [VString("Error"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("err_code")]);
            }
        });
        tasks.set("err_message", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            return switch (args[0]) {
                case VError(code, errArgs):
                    var loc = ctx.getLocalization();
                    var tmpl = loc.exists(code) ? loc.get(code) : "Unknown Error";
                    for (i in 0...errArgs.length) {
                        tmpl = StringTools.replace(tmpl, '{' + i + '}', ValueTools.toString(errArgs[i]));
                    }
                    VString(tmpl);
                case other: VError(4007, [VString("Error"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("err_message")]);
            }
        });
        tasks.set("err_args", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            return switch (args[0]) {
                case VError(c, a): VArray(a);
                case other: VError(4007, [VString("Error"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("err_args")]);
            }
        });

        // regex
        tasks.set("regex_parse", (args, ctx) -> {
            if (args.length == 0) return VVoid;
            var pattern = valToString(args[0]);
            var flags = args.length > 1 ? valToString(args[1]) : "";
            try {
                return VOpaque("RegExp", new EReg(pattern, flags));
            } catch (e:Dynamic) return VVoid;
        });
        tasks.set("regex_match", (args, ctx) -> {
            if (args.length < 2) return VVoid;
            var s = valToString(args[0]);
            return switch (args[1]) {
                case VOpaque("RegExp", re):
                    var ereg:EReg = cast re;
                    ereg.match(s) ? VNumber(1.0) : VVoid;
                default:
                    StringTools.contains(s, valToString(args[1])) ? VNumber(1.0) : VVoid;
            }
        });

        return tasks;
    }
}
