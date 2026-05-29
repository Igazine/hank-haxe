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
            // "test/conformance/14_syslib_hank.hank", // MOVED to extensions
            "test/conformance/15_logic_eq.hank",
            "test/conformance/16_chained_assign.hank",
            "test/conformance/17_num_module.hank",
            "test/conformance/18_runtime_module.hank",
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
                runner.run(resource, args);
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
