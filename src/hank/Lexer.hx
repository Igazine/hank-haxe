package hank;

import hank.Types;

enum TokenType {
    Identifier;
    Number;
    String;
    
    Assign;    // =
    Question;  // ?
    Colon;     // :
    Rescue;    // ~
    At;        // @
    Hash;      // #
    Not;       // !
    Caret;     // ^
    Dot;       // .
    Comma;     // ,
    
    LParen;    // (
    RParen;    // )
    LBrace;    // {
    RBrace;    // }
    LBracket;  // [
    RBracket;  // ]
    
    Newline;
    EOF;
    Error;
}

typedef Token = {
    var type:TokenType;
    var literal:String;
    var line:Int;
    var lineText:String;
}

class Lexer {
    var input:String;
    var pos:Int = 0;
    var line:Int = 1;
    var lineStart:Int = 0;
    var tokens:Array<Token> = [];

    public function new(input:String) {
        this.input = input;
    }

    public function tokenize():Array<Token> {
        while (pos < input.length) {
            var char = input.charAt(pos);

            if (isWhitespace(char)) {
                if (char == "\n") {
                    addToken(Newline, "\n");
                    line++;
                    pos++;
                    lineStart = pos;
                } else {
                    pos++;
                }
                continue;
            }

            if (char == "/" && input.charAt(pos + 1) == "/") {
                skipComment();
                continue;
            }

            if (char == "-" && isDigit(input.charAt(pos + 1))) {
                readNumber();
                continue;
            }

            if (isDigit(char)) {
                readNumber();
                continue;
            }

            if (isAlpha(char) || char == "_") {
                readIdentifier();
                continue;
            }

            if (char == '"' || char == "'") {
                readString(char);
                continue;
            }

            switch (char) {
                case '=': addToken(Assign, "=");
                case '?': addToken(Question, "?");
                case ':': addToken(Colon, ":");
                case '~': addToken(Rescue, "~");
                case '@': addToken(At, "@");
                case '#': addToken(Hash, "#");
                case '!': addToken(Not, "!");
                case '^': addToken(Caret, "^");
                case '.': addToken(Dot, ".");
                case ',': addToken(Comma, ",");
                case '(': addToken(LParen, "(");
                case ')': addToken(RParen, ")");
                case '{': addToken(LBrace, "{");
                case '}': addToken(RBrace, "}");
                case '[': addToken(LBracket, "[");
                case ']': addToken(RBracket, "]");
                default:
                    addToken(Error, HankErrorRegistry.create(UnexpectedCharacter, [char]).message);
            }
            pos++;
        }
        addToken(EOF, "");
        return tokens;
    }

    function addToken(type:TokenType, literal:String) {
        tokens.push({
            type: type,
            literal: literal,
            line: line,
            lineText: getCurrentLineText()
        });
    }

    function skipComment() {
        while (pos < input.length && input.charAt(pos) != "\n") {
            pos++;
        }
    }

    function readNumber() {
        var start = pos;
        if (input.charAt(pos) == "-") pos++;
        while (pos < input.length && (isDigit(input.charAt(pos)) || input.charAt(pos) == ".")) {
            pos++;
        }
        addToken(Number, input.substring(start, pos));
    }

    function readIdentifier() {
        var start = pos;
        pos++;
        while (pos < input.length && (isAlphaNumeric(input.charAt(pos)) || input.charAt(pos) == "_")) {
            pos++;
        }
        addToken(Identifier, input.substring(start, pos));
    }

    function readString(quote:String) {
        pos++; // skip quote
        var val = "";
        while (pos < input.length && input.charAt(pos) != quote) {
            if (input.charAt(pos) == "\\") {
                pos++;
                switch (input.charAt(pos)) {
                    case "n": val += "\n";
                    case "t": val += "\t";
                    default: val += input.charAt(pos);
                }
            } else {
                val += input.charAt(pos);
            }
            pos++;
        }
        if (pos >= input.length) {
            addToken(Error, HankErrorRegistry.create(UnclosedStringLiteral).message);
            return;
        }
        pos++; // skip quote
        addToken(String, val);
    }

    function getCurrentLineText():String {
        var end = pos;
        while (end < input.length && input.charAt(end) != "\n") {
            end++;
        }
        return input.substring(lineStart, end);
    }

    function isWhitespace(c:String):Bool return c == " " || c == "\t" || c == "\n" || c == "\r";
    function isDigit(c:String):Bool return c >= "0" && c <= "9";
    function isAlpha(c:String):Bool return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z");
    function isAlphaNumeric(c:String):Bool return isAlpha(c) || isDigit(c);
}
