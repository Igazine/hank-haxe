package;

import hank.*;
import hank.Types;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

class Main {
    static function main() {
        var args = Sys.args();
        var current = Sys.getCwd();
        
        // Submodule is at vendor/hank relative to the hank-haxe root.
        var workspaceRoot = Path.normalize(Path.join([current, "vendor/hank"]));
        if (!FileSystem.exists(workspaceRoot)) {
            workspaceRoot = Path.normalize(Path.join([current, "../../vendor/hank"]));
        }

        if (args.length == 0) {
            runConformance(workspaceRoot);
            return;
        }

        var runner = createRunner();
        var scriptPath = Path.isAbsolute(args[0]) ? args[0] : Path.join([current, args[0]]);
        var resource = FileResource.create(Path.normalize(scriptPath));

        var hankArgs:Array<Value> = [];
        for (i in 1...args.length) {
            hankArgs.push(VString(args[i]));
        }

        try {
            var res = runner.run(resource, hankArgs);
            switch (res) {
                case VNumber(n): Sys.exit(Std.int(n));
                default: Sys.exit(0);
            }
        } catch (e:Dynamic) {
            Sys.stderr().writeString(Std.string(e) + "\n");
            Sys.exit(1);
        }
    }

    static function createRunner():Runner {
        var runner = new Runner();

        // 1. Register StdLib
        var std = StdLib.getModules();
        for (name => tasks in std) {
            runner.registerModule(name, tasks);
        }

        // 2. Register SysLib (Basic implementation for Conformance)
        registerSyslib(runner);

        return runner;
    }

    static function registerSyslib(runner:Runner) {
        runner.registerModule("os", [
            "name" => (args, ctx) -> VString(Sys.systemName()),
            "type" => (args, ctx) -> {
                var s = Sys.systemName().toLowerCase();
                if (s.indexOf("mac") != -1) return VString("darwin");
                if (s.indexOf("window") != -1) return VString("windows");
                if (s.indexOf("linux") != -1) return VString("linux");
                if (s.indexOf("bsd") != -1) return VString("bsd");
                return VString("unknown");
            },
            "arch" => (args, ctx) -> VString("universal"),
            "memory" => (args, ctx) -> {
                var map = new Map<String, Value>();
                map.set("total", VNumber(16 * 1024 * 1024 * 1024.0)); // Stub
                map.set("free", VNumber(8 * 1024 * 1024 * 1024.0));
                map.set("used", VNumber(8 * 1024 * 1024 * 1024.0));
                return VObject(map);
            },
            "cpu" => (args, ctx) -> VNumber(10.0) // Stub
        ]);

        runner.registerModule("host", [
            "cwd" => (args, ctx) -> VString(Sys.getCwd()),
            "isRoot" => (args, ctx) -> VVoid, // Stub
            "pid" => (args, ctx) -> VNumber(0)
        ]);

        runner.registerModule("fs", [
            "exists" => (args, ctx) -> {
                var path = switch (args[0]) { case VString(s): s; default: ""; };
                return FileSystem.exists(path) ? VNumber(1) : VVoid;
            },
            "read" => (args, ctx) -> {
                var path = switch (args[0]) { case VString(s): s; default: ""; };
                try {
                    return VString(File.getContent(path));
                } catch (e:Dynamic) { return VVoid; }
            },
            "write" => (args, ctx) -> {
                var path = switch (args[0]) { case VString(s): s; default: ""; };
                var content = switch (args[1]) { case VString(s): s; default: ""; };
                try {
                    File.saveContent(path, content);
                    return VNumber(1);
                } catch (e:Dynamic) { return VVoid; }
            },
            "deleteFile" => (args, ctx) -> {
                var path = switch (args[0]) { case VString(s): s; default: ""; };
                try {
                    FileSystem.deleteFile(path);
                    return VNumber(1);
                } catch (e:Dynamic) { return VVoid; }
            },
            "stat" => (args, ctx) -> {
                var path = switch (args[0]) { case VString(s): s; default: ""; };
                try {
                    var s = FileSystem.stat(path);
                    var map = new Map<String, Value>();
                    map.set("size", VNumber(s.size));
                    map.set("mtime", VNumber(s.mtime.getTime()));
                    map.set("isDir", s.size == 0 && FileSystem.isDirectory(path) ? VNumber(1) : VVoid);
                    return VObject(map);
                } catch (e:Dynamic) { return VVoid; }
            }
        ]);

        runner.registerModule("proc", [
            "run" => (args, ctx) -> {
                var cmd = switch (args[0]) { case VString(s): s; default: ""; };
                var procArgs:Array<String> = [];
                if (args.length > 1) {
                    switch (args[1]) {
                        case VArray(arr): for (v in arr) switch (v) { case VString(s): procArgs.push(s); default: }
                        default:
                    }
                }
                try {
                    var p = new Process(cmd, procArgs);
                    var stdout = p.stdout.readAll().toString();
                    var stderr = p.stderr.readAll().toString();
                    var code = p.exitCode();
                    p.close();

                    var map = new Map<String, Value>();
                    map.set("code", VNumber(code));
                    map.set("stdout", VString(stdout));
                    map.set("stderr", VString(stderr));
                    return VObject(map);
                } catch (e:Dynamic) {
                    var map = new Map<String, Value>();
                    map.set("code", VNumber(1));
                    map.set("stdout", VString(""));
                    map.set("stderr", VString(Std.string(e)));
                    return VObject(map);
                }
            }
        ]);
    }

    static function runConformance(workspaceRoot:String) {
        var tests = [
            "test/conformance/01_literals.hank",
            "test/conformance/02_gates.hank",
            "test/conformance/03_scoping.hank",
            "test/conformance/04_hoisting.hank",
            "test/conformance/05_params.hank",
            "test/conformance/06_macros.hank",
            "test/conformance/07_returns.hank",
            "test/conformance/08_host_args.hank",
            "test/conformance/09_deep_nesting.hank",
            "test/conformance/10_edge_cases.hank",
            "test/conformance/11_regex_parse.hank",
            "test/conformance/12_data_advanced.hank",
            "test/conformance/13_logic_module.hank",
            "test/conformance/14_syslib_hank.hank",
            "test/conformance/15_logic_eq.hank",
            "test/conformance/16_chained_assign.hank",
            "test/conformance/17_num_module.hank",
        ];

        for (t in tests) {
            Sys.println('--- Running: $t ---');
            var runner = createRunner();
            var path = Path.normalize(Path.join([workspaceRoot, t]));
            var resource = FileResource.create(path);
            var args:Array<Value> = [];
            if (StringTools.endsWith(t, "08_host_args.hank")) {
                args.push(VString("Tamas"));
            }
            try {
                runner.run(resource, args);
            } catch (e:Dynamic) {
                Sys.println('Test Failed: $e');
            }
            Sys.println('--------------------\n');
        }
    }
}
