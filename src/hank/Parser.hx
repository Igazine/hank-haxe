package hank;

import hank.Lexer;
import hank.Types;

class Parser {
    var tokens:Array<Token>;
    var pos:Int = 0;
    var filename:String;
    var macroResolver:(String)->Expr;

    public function new(tokens:Array<Token>, filename:String, macroResolver:(String)->Expr) {
        this.tokens = tokens;
        this.filename = filename;
        this.macroResolver = macroResolver;
    }

    public function parse():Expr {
        skipNewlines();
        var stmts:Array<Expr> = [];

        // 1. Consume Macro Includes
        while (!isEof() && peek().type == At) {
            stmts.push(parseInclude());
            skipNewlines();
        }

        if (isEof()) throw error(EmptyScript);

        // 2. Parse exactly ONE TaskDef (FuncDef or Block)
        var mainTask:Expr = null;
        if (peek().type == LParen && isFuncDefStart()) {
            mainTask = parseFuncDef();
        } else if (peek().type == LBrace) {
            mainTask = parseBlock();
        } else {
            throw error(ExpectedMainTask);
        }
        stmts.push(mainTask);

        // 3. Assert EOF
        skipNewlines();
        if (!isEof()) {
            throw error(UnexpectedCodeOutsideMainTask);
        }

        if (stmts.length == 1) return stmts[0];
        return EBlock(stmts, ExprTools.getTd(stmts[0]));
    }

    function parseStatement():Expr {
        skipNewlines();
        var t = peek();
        return switch (t.type) {
            case Question: parseFlowControl();
            case Caret: parseReturn();
            case At: parseInclude();
            default: parseExpression();
        }
    }

    function parseFlowControl():Expr {
        var t = consume(Question);
        var tdRoot = { line: t.line, lineText: t.lineText };
        
        var condition:Expr;
        if (peek().type == LParen) {
            consume(LParen);
            condition = parseExpression();
            consume(RParen);
        } else {
            condition = parseExpression();
        }
        
        var success = parseBlock();
        
        var fallback:Expr = null;
        var rescue:Expr = null;
        var catchVar:String = null;
        
        var savedPos = pos;
        skipNewlines();
        if (peek().type == Colon) {
            consume(Colon);
            fallback = parseBlock();
            savedPos = pos;
            skipNewlines();
        } else {
            pos = savedPos;
        }
        
        if (peek().type == Rescue) {
            consume(Rescue);
            if (peek().type == LParen) {
                consume(LParen);
                catchVar = consumeIdentifier();
                consume(RParen);
            }
            rescue = parseBlock();
        } else {
            pos = savedPos;
        }
        
        return EFlowControl(condition, success, fallback, rescue, catchVar, tdRoot);
    }

    function parseExpression():Expr {
        return parseAssignment();
    }

    function parseAssignment():Expr {
        var expr = parsePrimary();

        if (peek().type == Assign) {
            switch (expr) {
                case EIdent(name, false, td):
                    consume(Assign);
                    var value = parseExpression();
                    return EAssign(name, value, td);
                default:
                    throw error(InvalidAssignmentTarget);
            }
        }

        return expr;
    }

    function parsePrimary():Expr {
        var t = peek();
        var tdRoot = { line: t.line, lineText: t.lineText };
        
        var expr:Expr = switch (t.type) {
            case At: parseInclude();
            case LParen:
                if (isFuncDefStart()) {
                    parseFuncDef();
                } else {
                    pos++;
                    var e = parseExpression();
                    consume(RParen);
                    e;
                }
            case LBrace: 
                parseBlock();
            case LBracket: parseCollectionLiteral();
            case Not:
                pos++;
                EUnOp("!", parsePrimary(), tdRoot);
            case Hash:
                pos++;
                EIdent(consumeIdentifier(), true, tdRoot);
            case Identifier:
                EIdent(consumeIdentifier(), false, tdRoot);
            case String:
                pos++;
                ELiteral(VString(t.literal), tdRoot);
            case Number:
                pos++;
                ELiteral(VNumber(Std.parseFloat(t.literal)), tdRoot);
            case Caret:
                parseReturn();
            default:
                throw error(UnexpectedToken, [t.type, t.literal]);
        }

        return finishPrimary(expr);
    }

    function finishPrimary(expr:Expr):Expr {
        while (true) {
            var t = peek();
            var tdRoot = { line: t.line, lineText: t.lineText };
            if (t.type == Dot) {
                consume(Dot);
                expr = EField(expr, consumeIdentifier(), tdRoot);
            } else if (t.type == LParen) {
                expr = EFuncCall(expr, parseArgList(), tdRoot);
            } else break;
        }
        return expr;
    }

    function isFuncDefStart():Bool {
        var p = pos + 1;
        var depth = 1;
        while (p < tokens.length && depth > 0) {
            if (tokens[p].type == LParen) depth++;
            if (tokens[p].type == RParen) depth--;
            p++;
        }
        while (p < tokens.length && tokens[p].type == Newline) p++;
        return p < tokens.length && tokens[p].type == LBrace;
    }

    function parseFuncDef():Expr {
        var tdRoot = td();
        consume(LParen);
        var params:Array<Param> = [];
        if (peek().type != RParen) {
            params.push(parseParam());
            while (peek().type == Comma) {
                consume(Comma);
                params.push(parseParam());
            }
        }
        consume(RParen);
        var body = parseBlock();
        return EFuncDef(params, body, tdRoot);
    }

    function parseParam():Param {
        var isOptional = false;
        if (peek().type == Question) {
            consume(Question);
            isOptional = true;
        }
        var name = consumeIdentifier();
        var defaultValue:Expr = null;
        if (peek().type == Assign) {
            consume(Assign);
            defaultValue = parseExpression();
            isOptional = true;
        }
        return { name: name, isOptional: isOptional, defaultValue: defaultValue };
    }

    function parseBlock():Expr {
        var t = consume(LBrace);
        var tdRoot = { line: t.line, lineText: t.lineText };
        var stmts:Array<Expr> = [];
        while (peek().type != RBrace && !isEof()) {
            skipNewlines();
            if (peek().type == RBrace) break;
            stmts.push(parseStatement());
        }
        consume(RBrace);
        return EBlock(stmts, tdRoot);
    }

    function parseCollectionLiteral():Expr {
        var t = consume(LBracket);
        var tdRoot = { line: t.line, lineText: t.lineText };
        skipNewlines();

        // 1. Handle [:]
        if (peek().type == Colon) {
            consume(Colon);
            consume(RBracket);
            return EMap(new Map(), tdRoot);
        }

        // 2. Handle []
        if (peek().type == RBracket) {
            consume(RBracket);
            return EArray([], tdRoot);
        }

        // 3. Parse first element
        var first = parseExpression();
        skipNewlines();

        if (peek().type == Colon) {
            // This is a Map
            consume(Colon);
            var val = parseExpression();
            var fields = new Map<String, Expr>();
            fields.set(getStaticKey(first), val);

            while (true) {
                skipNewlines();
                if (peek().type == Comma) {
                    consume(Comma);
                    skipNewlines();
                    if (peek().type == RBracket) break;
                    var keyExpr = parseExpression();
                    consume(Colon);
                    var valExpr = parseExpression();
                    fields.set(getStaticKey(keyExpr), valExpr);
                } else break;
            }
            consume(RBracket);
            return EMap(fields, tdRoot);
        } else {
            // This is an Array
            var items = [first];
            while (true) {
                skipNewlines();
                if (peek().type == Comma) {
                    consume(Comma);
                    skipNewlines();
                    if (peek().type == RBracket) break;
                    items.push(parseExpression());
                } else break;
            }
            consume(RBracket);
            return EArray(items, tdRoot);
        }
    }

    function getStaticKey(e:Expr):String {
        return switch (e) {
            case ELiteral(VString(s), _): s;
            case EIdent(name, false, _): name;
            default: throw error(ExpectedIdentifier, [peek().type]); // Technically it should be a more specific error
        }
    }

    function parseArgList():Array<Expr> {
        consume(LParen);
        var args:Array<Expr> = [];
        skipNewlines();
        if (peek().type != RParen) {
            args.push(parseExpression());
            while (true) {
                skipNewlines();
                if (!isEof() && peek().type == Comma) {
                    consume(Comma);
                    skipNewlines();
                    args.push(parseExpression());
                } else break;
            }
        }
        skipNewlines();
        consume(RParen);
        return args;
    }

    function parseReturn():Expr {
        var t = consume(Caret);
        var tdRoot = { line: t.line, lineText: t.lineText };
        var val:Expr = ELiteral(VVoid, tdRoot);
        if (!isEof()) {
            var next = peek().type;
            if (next != Newline && next != RBrace && next != RBracket && next != Comma && next != RParen) {
                val = parseExpression();
            }
        }
        return EUnOp("^", val, tdRoot);
    }

    function parseInclude():Expr {
        var t = consume(At);
        var tdRoot = { line: t.line, lineText: t.lineText };
        var rawPath = '';
        if (peek().type == String) {
            rawPath = consume(String).literal;
        } else {
            throw error(MacroRequiresString);
        }

        var taskAst = macroResolver(rawPath);
        var taskName = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(rawPath));

        return EAssign(taskName, taskAst, tdRoot);
    }

    function consumeIdentifier():String {
        var t = peek();
        if (t.type == Identifier) {
            pos++;
            return t.literal;
        }
        throw error(ExpectedIdentifier, [t.type]);
    }

    function consume(type:TokenType):Token {
        var t = peek();
        if (t.type == type) {
            pos++;
            return t;
        }
        throw error(UnexpectedToken, [type, t.type]);
    }

    function peek():Token {
        if (pos >= tokens.length) return tokens[tokens.length - 1];
        return tokens[pos];
    }

    function td():TokenData {
        var t = peek();
        return { line: t.line, lineText: t.lineText };
    }

    function skipNewlines() {
        while (pos < tokens.length && tokens[pos].type == Newline) {
            pos++;
        }
    }

    function isEof():Bool {
        return pos >= tokens.length || tokens[pos].type == EOF;
    }

    function error(code:HankError, ?args:Array<Dynamic>):HankErrorValue {
        var t = peek();
        return HankErrorRegistry.create(code, args, filename, t.line, t.lineText);
    }
}
