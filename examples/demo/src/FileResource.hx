package;

import hank.Resource;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class FileResource extends Resource {
    static public function create( path:String ):FileResource {
        return new FileResource( path );
    }

    function new( id:String ) {
        super( id );
    }

    public function load() {
        this.content = File.getContent(this.id);
    }

    public function resolve( id:String ):Resource {
        var path = id;
        if (!Path.isAbsolute(path)) {
            var baseDir = Path.directory(this.id);
            path = Path.join([baseDir, path]);
        }
        
        if (Path.extension(path) == "") {
            if (FileSystem.exists(path + ".hank")) path = path + ".hank";
        }
        
        return FileResource.create(Path.normalize(path));
    }
}
