package hank.ext;

import hank.Types;

class SysExtension implements IExtension {
    public var name(default, null):String = "SysExtension";

    public function new() {}

    public function getModules():Map<String, Map<String, Array<Value>->ExecutionContext->Value>> {
        var valToString = (v:Value) -> ValueTools.toString(v);
        var mods = new Map<String, Map<String, Array<Value>->ExecutionContext->Value>>();

        // --- host ---
        mods.set("host", [
            "cwd" => (args, ctx) -> VString(Sys.getCwd()),
            "isRoot" => (args, ctx) -> {
                #if (linux || macos || bsd)
                try {
                    var p = new sys.io.Process("id", ["-u"]);
                    var out = p.stdout.readAll().toString();
                    p.close();
                    return Std.trim(out) == "0" ? VNumber(1.0) : VVoid;
                } catch (e:Dynamic) return VVoid;
                #else
                return VVoid;
                #end
            },
            "pid" => (args, ctx) -> {
                #if (linux || macos || windows || bsd)
                return VNumber(0); // Placeholder
                #else
                return VVoid;
                #end
            }
        ]);

        // --- os ---
        mods.set("os", [
            "type" => (args, ctx) -> {
                var name = Sys.systemName().toLowerCase();
                if (StringTools.contains(name, "window")) return VString("windows");
                if (StringTools.contains(name, "linux")) return VString("linux");
                if (StringTools.contains(name, "mac") || StringTools.contains(name, "darwin")) return VString("darwin");
                if (StringTools.contains(name, "bsd")) return VString("bsd");
                return VString("unknown");
            },
            "name" => (args, ctx) -> VString(Sys.systemName()),
            "arch" => (args, ctx) -> VString("unknown"),
            "memory" => (args, ctx) -> {
                var map = new Map<String, Value>();
                map.set("total", VNumber(0));
                map.set("free", VNumber(0));
                map.set("used", VNumber(0));
                return VObject(map);
            },
            "cpu" => (args, ctx) -> VNumber(0.0)
        ]);

        // --- fs ---
        mods.set("fs", [
            "exists" => (args, ctx) -> {
                if (args.length == 0) return VVoid;
                var path = "";
                switch (args[0]) {
                    case VString(s): path = s;
                    case other: return VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("fs.exists")]);
                }
                return sys.FileSystem.exists(path) ? VNumber(1.0) : VVoid;
            },
            "isDir" => (args, ctx) -> {
                if (args.length == 0) return VVoid;
                var path = "";
                switch (args[0]) {
                    case VString(s): path = s;
                    case other: return VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("fs.isDir")]);
                }
                return sys.FileSystem.isDirectory(path) ? VNumber(1.0) : VVoid;
            },
            "absPath" => (args, ctx) -> {
                if (args.length == 0) return VVoid;
                var path = "";
                switch (args[0]) {
                    case VString(s): path = s;
                    case other: return VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("fs.absPath")]);
                }
                return VString(sys.FileSystem.fullPath(path));
            },
            "read" => (args, ctx) -> {
                if (args.length == 0) return VVoid;
                var path = "";
                switch (args[0]) {
                    case VString(s): path = s;
                    case other: return VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("fs.read")]);
                }
                try {
                    return VString(sys.io.File.getContent(path));
                } catch (e:Dynamic) return VVoid;
            },
            "write" => (args, ctx) -> {
                if (args.length < 2) return VVoid;
                var path = "";
                var content = "";
                switch (args[0]) {
                    case VString(s): path = s;
                    case other: return VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("fs.write")]);
                }
                switch (args[1]) {
                    case VString(s): content = s;
                    case other: return VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("fs.write")]);
                }
                try {
                    sys.io.File.saveContent(path, content);
                    return VNumber(1.0);
                } catch (e:Dynamic) return VVoid;
            },
            "deleteFile" => (args, ctx) -> {
                if (args.length == 0) return VVoid;
                var path = "";
                switch (args[0]) {
                    case VString(s): path = s;
                    case other: return VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("fs.deleteFile")]);
                }
                try {
                    sys.FileSystem.deleteFile(path);
                    return VNumber(1.0);
                } catch (e:Dynamic) return VVoid;
            },
            "stat" => (args, ctx) -> {
                if (args.length == 0) return VVoid;
                var path = "";
                switch (args[0]) {
                    case VString(s): path = s;
                    case other: return VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("fs.stat")]);
                }
                try {
                    var s = sys.FileSystem.stat(path);
                    var map = new Map<String, Value>();
                    map.set("size", VNumber(s.size));
                    map.set("isDir", sys.FileSystem.isDirectory(path) ? VNumber(1.0) : VVoid);
                    map.set("mtime", VNumber(s.mtime.getTime()));
                    return VObject(map);
                } catch (e:Dynamic) return VVoid;
            }
        ]);

        // --- proc ---
        mods.set("proc", [
            "run" => (args, ctx) -> {
                if (args.length == 0) return VVoid;
                var cmd = "";
                switch (args[0]) {
                    case VString(s): cmd = s;
                    case other: return VError(4007, [VString("String"), VString(ValueTools.typeToString(ValueTools.getType(other))), VString("proc.run")]);
                }
                var cmdArgs:Array<String> = [];
                if (args.length > 1) switch (args[1]) {
                    case VArray(a): cmdArgs = a.map(valToString);
                    default:
                }
                try {
                    var p = new sys.io.Process(cmd, cmdArgs);
                    var stdout = p.stdout.readAll().toString();
                    var stderr = p.stderr.readAll().toString();
                    var code = p.exitCode();
                    p.close();
                    var map = new Map<String, Value>();
                    map.set("code", VNumber(code));
                    map.set("stdout", VString(stdout));
                    map.set("stderr", VString(stderr));
                    return VObject(map);
                } catch (e:Dynamic) return VVoid;
            }
        ]);

        return mods;
    }
}
