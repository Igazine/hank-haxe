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
        consume(LParen);
        var condition = parseExpression();
        consume(RParen);
        
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
                if (isObjectLiteral()) {
                    parseObjectLiteral();
                } else {
                    parseBlock();
                }
            case LBracket: parseArrayLiteral();
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

    function isObjectLiteral():Bool {
        var p = pos + 1;
        while (p < tokens.length && tokens[p].type == Newline) p++;
        if (p >= tokens.length) return false;
        if (tokens[p].type == RBrace) return true;
        if (tokens[p].type == Identifier) {
            var next = p + 1;
            while (next < tokens.length && tokens[next].type == Newline) next++;
            return next < tokens.length && tokens[next].type == Colon;
        }
        return false;
    }

    function parseObjectLiteral():Expr {
        var t = consume(LBrace);
        var tdRoot = { line: t.line, lineText: t.lineText };
        var fields:Map<String, Expr> = new Map();
        while (peek().type != RBrace && !isEof()) {
            skipNewlines();
            if (peek().type == RBrace) break;
            var key = consumeIdentifier();
            consume(Colon);
            var val = parseExpression();
            fields.set(key, val);
            if (peek().type == Comma) consume(Comma);
        }
        consume(RBrace);
        return EObject(fields, tdRoot);
    }

    function parseArrayLiteral():Expr {
        var t = consume(LBracket);
        var tdRoot = { line: t.line, lineText: t.lineText };
        var items:Array<Expr> = [];
        while (peek().type != RBracket && !isEof()) {
            skipNewlines();
            if (peek().type == RBracket) break;
            items.push(parseExpression());
            if (peek().type == Comma) consume(Comma);
        }
        consume(RBracket);
        return EArray(items, tdRoot);
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
