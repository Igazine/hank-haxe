package;

import hank.*;
import hank.ext.*;
import hank.Types;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

class Main {
    static function main() {
        var args = Sys.args();
        var current = Sys.getCwd();
        
        // Robust submodule discovery
        var workspaceRoot = "";
        var checkPaths = [
            Path.join([current, "vendor/hank"]),
            Path.join([current, "hank-haxe/vendor/hank"]),
            Path.join([current, "../../vendor/hank"])
        ];

        for (p in checkPaths) {
            var norm = Path.normalize(p);
            if (FileSystem.exists(norm) && FileSystem.isDirectory(norm)) {
                workspaceRoot = norm;
                break;
            }
        }

        if (workspaceRoot == "") {
            Sys.stderr().writeString("Error: Could not find vendor/hank submodule.\n");
            Sys.exit(1);
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
                case VError(code, args):
                    var loc = runner.localization;
                    var tmpl = loc.exists(code) ? loc.get(code) : "Unknown Error";
                    for (i in 0...args.length) {
                        tmpl = StringTools.replace(tmpl, '{' + i + '}', ValueTools.toString(args[i]));
                    }
                    Sys.stderr().writeString('Error $code: $tmpl\n');
                    Sys.exit(1);
                case VNumber(n): Sys.exit(Std.int(n));
                default: Sys.exit(0);
            }
        } catch (e:Dynamic) {
            handleError(e);
            Sys.exit(1);
        }
    }

    static function handleError(e:Dynamic) {
        if (Reflect.hasField(e, "message")) {
            Sys.stderr().writeString(Reflect.field(e, "message") + "\n");
        } else {
            Sys.stderr().writeString(Std.string(e) + "\n");
        }
    }

    static function createRunner():Runner {
        var runner = new Runner();

        // 0. Register Localization
        runner.registerLocalization([
            4001 => "Target is not a function: {0}",
            4007 => "Type Mismatch: Expected {0}, got {1} in {2}",
            4005 => "Value exceeds safe integer bounds: {0} in {1}"
        ]);

        // Register Extensions (Batteries included, but disconnected)
        runner.registerExtension(new StdLib());
        runner.registerExtension(new PlatformExtension());
        runner.registerExtension(new SysExtension());

        return runner;
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
            "test/conformance/15_logic_eq.hank",
            "test/conformance/16_chained_assign.hank",
            "test/conformance/17_num_module.hank",
            "test/conformance/18_runtime_module.hank",
            "test/conformance/19_error_handling.hank",
            "test/conformance/20_grammar_hardening.hank",
        ];

        for (t in tests) {
            Sys.println('--- Running Conformance: $t ---');
            var runner = createRunner();
            var path = Path.normalize(Path.join([workspaceRoot, t]));
            var resource = FileResource.create(path);
            var args:Array<Value> = [];
            if (StringTools.endsWith(t, "08_host_args.hank")) {
                args.push(VString("Tamas"));
            }
            try {
                var res = runner.run(resource, args);
                switch (res) {
                    case VError(code, errArgs):
                        var loc = runner.localization;
                        var tmpl = loc.exists(code) ? loc.get(code) : "Unknown Error";
                        for (i in 0...errArgs.length) {
                            tmpl = StringTools.replace(tmpl, '{' + i + '}', ValueTools.toString(errArgs[i]));
                        }
                        Sys.stderr().writeString('Error $code: $tmpl\n');
                    default:
                }
            } catch (e:Dynamic) {
                handleError(e);
            }
            Sys.println('--------------------\n');
        }

        // Run Extension Tests
        var extTests = [
            "test/extensions/sys.hank",
            "test/extensions/platform_bin.hank"
        ];

        for (t in extTests) {
            Sys.println('--- Running Extension Test: $t ---');
            var runner = createRunner();
            var path = Path.normalize(Path.join([workspaceRoot, t]));
            var resource = FileResource.create(path);
            try {
                runner.run(resource, []);
            } catch (e:Dynamic) {
                handleError(e);
            }
            Sys.println('--------------------\n');
        }
    }
}
