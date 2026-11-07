import std;
import src.calc;

// Tastenfolge: Ziffern , + - * / = ( ) n(negate) q(sqr) r(1/x) s(sqrt) %
fn run(keys: const u8[:], sci: bool) {
    calc::clear_all();
    calc::sci = sci;
    for k in keys {
        if k >= '0' && k <= '9' { calc::digit(k); }
        else if k == ',' { calc::decimal(); }
        else if k == '+' { calc::binary(calc::ADD); }
        else if k == '-' { calc::binary(calc::SUB); }
        else if k == '*' { calc::binary(calc::MUL); }
        else if k == '/' { calc::binary(calc::DIV); }
        else if k == '^' { calc::binary(calc::POW); }
        else if k == '=' { calc::equals(); }
        else if k == '(' { calc::lparen(); }
        else if k == ')' { calc::rparen(); }
        else if k == 'n' { calc::negate(); }
        else if k == 'q' { calc::unary("sqr"); }
        else if k == 'r' { calc::unary("1/"); }
        else if k == 's' { calc::unary("√"); }
        else if k == '%' { calc::percent(); }
        else if k == '!' { calc::unary("fact"); }
        else if k == 'S' { calc::trig("sin", false, false); }
        else if k == 'b' { calc::backspace(); }
    }
    var e: u8[>..] = [];
    calc::expr_text(e);
    var d: u8[>..] = [];
    calc::display_text(d);
    print(keys, if sci { "  [sci]" } else { "" }, "   |", e, "|   ", d);
}

fn main() {
    run("2+3*4=", false);
    run("2+3*4=", true);
    run("2+3==", false);
    run("5+=", false);
    run("5+3q", false);
    run("9s+1=", false);
    run("200+10%=", false);
    run("1/0=", false);
    run("0/0=", false);
    run("(2+3)*4=", true);
    run("2*(3+4", true);
    run("2*(3+4=", true);
    run("2^10=", true);
    run("5!", true);
    run("180S", true);
    run("30S", true);
    run("12,5n", false);
    run("1234b", false);
    run("2+*3=", false);
    run("0,1+0,2=", false);
}
