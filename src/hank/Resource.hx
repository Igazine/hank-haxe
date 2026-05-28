package hank;

import hank.Types.Expr;

/**
 * A base class for all Hank resources.
 * Encapsulates the unique identity, raw content, and parsed AST of a script.
 * Handles its own hierarchical resolution (e.g., relative paths).
 */
abstract class Resource {
    public var content( default, null ):Null<String>;
    public var id( default, null ):Null<String>;
    public var ast:Expr;

    function new( id:String ) {
        this.id = id;
    }

    /**
     * Fulfills the raw content of the resource from its source.
     */
    abstract public function load():Void;

    /**
     * Resolves a relative identifier into a new Resource instance.
     * @param id The string identifier (e.g., from a @ macro).
     */
    abstract public function resolve( id:String ):Resource;
}
