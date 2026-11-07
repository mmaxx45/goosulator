// Die Rechenlogik von "Standard" und "Wissenschaftlich".
//
// Standard rechnet sofort von links nach rechts (2 + 3 × 4 = 20),
// Wissenschaftlich mit Punkt-vor-Strich und Klammern (2 + 3 × 4 = 14).
// Beides ist derselbe Shunting-Yard-Automat: im Standardmodus haben alle
// Operatoren denselben Rang, also wird bei jedem Operator sofort gerechnet.
import std;
import math;
import os;
import src.numfmt;

namespace calc;

let ADD = 1;
let SUB = 2;
let MUL = 3;
let DIV = 4;
let MOD = 5;
let POW = 6;
let ROOT = 7;
let LOGY = 8;
let LPAREN = 100;

// Was zuletzt in den Rechenweg kam.
let TOK_NONE = 0;
let TOK_OPERAND = 1;
let TOK_OP = 2;
let TOK_LPAREN = 3;

let DEG = 0;
let RAD = 1;
let GRAD = 2;

struct HistItem { expr: u8[..400], res: u8[..80], val: f64 }

var sci = false;                // Punkt vor Strich, Klammern
var vals: f64[>..<];
var ops: i64[>..<];
var toks: u8[..200][>..<];      // der Rechenweg, Stück für Stück
var last_tok = TOK_NONE;
var depth = 0;                  // offene Klammern

var cur: f64 = 0.0;             // der angezeigte Wert
var entry: u8[..48];            // was gerade getippt wird, mit '.' als Dezimalpunkt
var entering = false;
var operand: u8[..200];         // cur als Ausdruck, etwa "sqr(5)"
var operand_set = false;
var has_cur = false;            // seit dem letzten Operator kam ein Operand

var after_eq = false;
var eq_line: u8[..400];
var last_op = 0;
var last_rhs: f64 = 0.0;

var err: u8[..80];              // nicht leer: Fehlerzustand
var angle = DEG;
var fe = false;

var history: HistItem[>..<];
var memory: f64[>..<];
var rng_state = rng { 0 };
var rng_ready = false;

// --- Hilfen --------------------------------------------------------------------

fn prec(op: i64) -> i64 {
    if !sci { return 1; }
    match op {
        ADD, SUB => 1,
        MUL, DIV, MOD => 2,
        _ => 3,
    }
}

fn right_assoc(op: i64) -> bool { sci && (op == POW || op == ROOT) }

fn op_text(op: i64) -> const u8[:] {
    match op {
        ADD => "+",
        SUB => "−",
        MUL => "×",
        DIV => "÷",
        MOD => "Mod",
        POW => "^",
        ROOT => "yroot",
        LOGY => "log base",
        _ => "?",
    }
}

fn is_error() -> bool { err.len > 0 }

fn set_err(msg: const u8[:]) {
    err.resize(0);
    err.append(msg);
}

fn entry_value() -> f64 {
    var t: u8[..56] = [];
    t.append(entry);
    if t.len == 0 || t[t.len - 1] == '.' || t[t.len - 1] == '+' || t[t.len - 1] == '-' ||
       t[t.len - 1] == 'e' {
        t.push('0');
    }
    let v, ok = parse_flt(t);
    if ok { v } else { 0.0 }
}

// cur als Text für den Rechenweg.
fn cur_label(out: u8[>..]&) {
    if operand_set { out.append(operand); } else { nf::format_num(out, cur, fe); }
}

fn reset_expr() {
    vals.clear();
    ops.clear();
    toks.clear();
    last_tok = TOK_NONE;
    depth = 0;
}

fn clear_all() {
    reset_expr();
    cur = 0.0;
    entry.resize(0);
    entering = false;
    operand.resize(0);
    operand_set = false;
    has_cur = false;
    after_eq = false;
    eq_line.resize(0);
    last_op = 0;
    err.resize(0);
}

// Nach "=" beginnt eine Eingabe von vorn, ein Operator rechnet mit dem
// Ergebnis weiter.
fn leave_eq() {
    if after_eq {
        reset_expr();
        eq_line.resize(0);
        after_eq = false;
    }
}

fn check_result(r: f64) -> bool {
    if is_nan(r) {
        set_err("Ungültige Eingabe");
        return false;
    }
    if is_inf(r) || abs(r) >= 1.0e300 {
        set_err("Überlauf");
        return false;
    }
    true
}

// --- binäre Rechnung -----------------------------------------------------------

fn binop(op: i64, a: f64, b: f64) -> f64 {
    match op {
        ADD => a + b,
        SUB => a - b,
        MUL => a * b,
        DIV => block {
            if b == 0.0 {
                if a == 0.0 { set_err("Ergebnis undefiniert"); } else {
                    set_err("Division durch Null nicht möglich");
                }
                break 0.0;
            }
            a / b
        },
        MOD => block {
            if b == 0.0 { set_err("Division durch Null nicht möglich"); break 0.0; }
            a % b
        },
        POW => block {
            if a == 0.0 && b < 0.0 { set_err("Division durch Null nicht möglich"); break 0.0; }
            power(a, b)
        },
        ROOT => block {
            // y-te Wurzel aus a; ungerade Wurzeln aus negativen Zahlen gehen.
            if b == 0.0 { set_err("Ungültige Eingabe"); break 0.0; }
            if a < 0.0 {
                let bi = round(b);
                if bi == b && abs(bi % 2.0) == 1.0 { break -pow(-a, 1.0 / b); }
                set_err("Ungültige Eingabe");
                break 0.0;
            }
            pow(a, 1.0 / b)
        },
        LOGY => block {
            if a <= 0.0 || b <= 0.0 || b == 1.0 { set_err("Ungültige Eingabe"); break 0.0; }
            log(a) / log(b)
        },
        _ => 0.0,
    }
}

fn power(a: f64, b: f64) -> f64 {
    if a < 0.0 && round(b) != b {
        // (-8)^(1/3): Windows rechnet ungerade Wurzeln reell.
        let inv = 1.0 / b;
        let ri = round(inv);
        if abs(inv - ri) < 1.0e-9 && abs(ri % 2.0) == 1.0 { return -pow(-a, b); }
        return 0.0 / 0.0;
    }
    pow(a, b)
}

fn apply_top() {
    let op = ops.pop();
    let b = vals.pop();
    let a = vals.pop();
    let r = binop(op, a, b);
    last_op = op;
    last_rhs = b;
    if !is_error() { check_result(r); }
    vals.push(r);
}

fn reduce(p: i64, right: bool) {
    while ops.len > 0 && !is_error() {
        let top = ops[ops.len - 1];
        if top == LPAREN { break; }
        let tp = prec(top);
        if tp > p || (tp == p && !right) { apply_top(); } else { break; }
    }
}

fn commit() {
    vals.push(cur);
    var label: u8[>..] = [];
    cur_label(label);
    toks.push(str(label));
    last_tok = TOK_OPERAND;
}

fn after_value() {
    entering = false;
    has_cur = false;
    operand.resize(0);
    operand_set = false;
}

// --- Tasten --------------------------------------------------------------------

fn digit(d: u8) {
    if is_error() { clear_all(); }
    leave_eq();
    if !entering {
        entry.resize(0);
        entering = true;
        operand_set = false;
        operand.resize(0);
        has_cur = true;
    }
    let epos = find(entry, "e");
    if epos >= 0 {
        // Ziffern des Exponenten: höchstens vier, eine führende 0 wird ersetzt.
        let exp_digits = entry.len - epos - 2;
        if exp_digits == 1 && entry[entry.len - 1] == '0' { entry.resize(entry.len - 1); }
        else if exp_digits >= 4 { return; }
        entry.push(d);
    } else {
        var n = 0;
        for c in entry { if ascii::is_digit(c) { n++; } }
        if n >= 16 { return; }
        if entry == "0" { entry.resize(0); }
        if entry == "-0" { entry.resize(1); }
        entry.push(d);
    }
    cur = entry_value();
}

fn decimal() {
    if is_error() { clear_all(); }
    leave_eq();
    if !entering {
        entry.resize(0);
        entry.append("0");
        entering = true;
        operand_set = false;
        has_cur = true;
    }
    if find(entry, ".") < 0 && find(entry, "e") < 0 { entry.push('.'); }
    cur = entry_value();
}

// "exp": Eingabe in Exponentialschreibweise.
fn exp_key() {
    if is_error() { return; }
    leave_eq();
    if !entering {
        entry.resize(0);
        var t: u8[>..] = [];
        nf::format_num(t, cur, false, false);
        for c in t { if c == ',' { entry.push('.'); } else if c != '.' { entry.push(c); } }
        if find(entry, "e") >= 0 { entry.resize(0); entry.append("0"); }
        entering = true;
        operand_set = false;
        has_cur = true;
    }
    if find(entry, "e") >= 0 { return; }
    if find(entry, ".") < 0 { entry.push('.'); }
    entry.append("e+");
    cur = entry_value();
}

fn backspace() {
    if is_error() { clear_all(); return; }
    if after_eq {
        eq_line.resize(0);
        return;
    }
    if !entering { return; }
    var n = entry.len;
    let ends_exp = n >= 2 && (entry[n - 1] == '+' || entry[n - 1] == '-') && entry[n - 2] == 'e';
    if ends_exp {
        // "1.e+" verliert den ganzen Exponenten.
        n -= 2;
    } else {
        n -= 1;
    }
    entry.resize(max(n, 0));
    if entry.len == 0 || entry == "-" { entry.resize(0); entry.append("0"); }
    cur = entry_value();
}

fn clear_entry() {
    if is_error() || after_eq { clear_all(); return; }
    cur = 0.0;
    entry.resize(0);
    entering = false;
    operand.resize(0);
    operand_set = false;
    has_cur = true;
}

fn negate() {
    if is_error() { return; }
    if entering {
        let epos = find(entry, "e");
        if epos >= 0 {
            entry[epos + 1] = if entry[epos + 1] == '+' { '-' } else { '+' };
        } else if entry.len > 0 && entry[0] == '-' {
            var t: u8[..48] = [];
            t.append(entry[1..]);
            entry = t;
        } else if entry != "0" {
            var t: u8[..48] = [];
            t.push('-');
            t.append(entry);
            entry = t;
        }
        cur = entry_value();
        return;
    }
    unary_result(-cur, "negate");
}

// Das Ergebnis einer einstelligen Funktion wird der aktuelle Operand,
// im Rechenweg als name(operand).
fn unary_result(r: f64, name: const u8[:]) {
    var label: u8[>..] = [];
    label.append(name);
    label.push('(');
    cur_label(label);
    label.push(')');
    if after_eq {
        reset_expr();
        eq_line.resize(0);
        after_eq = false;
    }
    if !check_result(r) { return; }
    cur = if r == 0.0 { 0.0 } else { r };
    operand.resize(0);
    operand.append(label[..min(label.len, 200)]);
    operand_set = true;
    entering = false;
    has_cur = true;
}

fn unary(name: const u8[:]) {
    if is_error() { return; }
    let x = cur;
    var r = 0.0;
    var label = name;
    if name == "sqr" { r = x * x; }
    else if name == "cube" { r = x * x * x; }
    else if name == "√" {
        if x < 0.0 { set_err("Ungültige Eingabe"); return; }
        r = sqrt(x);
    }
    else if name == "cuberoot" { r = cbrt(x); }
    else if name == "1/" {
        if x == 0.0 { set_err("Division durch Null nicht möglich"); return; }
        r = 1.0 / x;
    }
    else if name == "abs" { r = abs(x); }
    else if name == "10^" { r = pow(10.0, x); }
    else if name == "2^" { r = pow(2.0, x); }
    else if name == "e^" { r = exp(x); }
    else if name == "log" || name == "ln" {
        if x <= 0.0 { set_err("Ungültige Eingabe"); return; }
        r = if name == "log" { log10(x) } else { log(x) };
    }
    else if name == "fact" {
        if x < 0.0 && round(x) == x { set_err("Ungültige Eingabe"); return; }
        r = factorial(x);
    }
    else if name == "floor" { r = floor(x); }
    else if name == "ceil" { r = ceil(x); }
    else if name == "dms" { r = to_dms(x); }
    else if name == "degrees" { r = from_dms(x); }
    else { return; }
    unary_result(r, label);
}

// --- Trigonometrie ---------------------------------------------------------------

fn unit_suffix() -> const u8[:] {
    match angle { DEG => "₀", RAD => "ᵣ", _ => "₉" }
}

fn to_rad(x: f64) -> f64 {
    match angle { DEG => x * PI / 180.0, RAD => x, _ => x * PI / 200.0 }
}

fn from_rad(x: f64) -> f64 {
    match angle { DEG => x * 180.0 / PI, RAD => x, _ => x * 200.0 / PI }
}

// Winkel im Kreis auf Vielfache einer Achtel- bzw. Zwölfteldrehung prüfen,
// damit sin(180°) wirklich 0 ist und tan(90°) ein Fehler.
fn turns(x: f64) -> f64 {
    match angle { DEG => x / 360.0, RAD => x / TAU, _ => x / 400.0 }
}

fn clean(r: f64) -> f64 { if abs(r) < 1.0e-15 { 0.0 } else { r } }

// name: sin cos tan sec csc cot; inv: Umkehrfunktion; hyp: hyperbolisch.
fn trig(name: const u8[:], inv: bool, hyp: bool) {
    if is_error() { return; }
    let x = cur;
    var r = 0.0;
    var label: u8[..32] = [];
    label.append(name);
    if hyp { label.push('h'); }
    if !hyp { label.append(unit_suffix()); }
    if inv { label.append("⁻¹"); }
    if hyp {
        if !inv {
            if name == "sin" { r = sinh(x); }
            else if name == "cos" { r = cosh(x); }
            else if name == "tan" { r = tanh(x); }
            else if name == "sec" { r = 1.0 / cosh(x); }
            else if name == "csc" {
                if x == 0.0 { set_err("Ungültige Eingabe"); return; }
                r = 1.0 / sinh(x);
            } else {
                if x == 0.0 { set_err("Ungültige Eingabe"); return; }
                r = 1.0 / tanh(x);
            }
        } else {
            if name == "sin" { r = log(x + sqrt(x * x + 1.0)); }
            else if name == "cos" {
                if x < 1.0 { set_err("Ungültige Eingabe"); return; }
                r = log(x + sqrt(x * x - 1.0));
            } else if name == "tan" {
                if abs(x) >= 1.0 { set_err("Ungültige Eingabe"); return; }
                r = 0.5 * log((1.0 + x) / (1.0 - x));
            } else if name == "sec" {
                if x <= 0.0 || x > 1.0 { set_err("Ungültige Eingabe"); return; }
                r = log((1.0 + sqrt(1.0 - x * x)) / x);
            } else if name == "csc" {
                if x == 0.0 { set_err("Ungültige Eingabe"); return; }
                r = log(1.0 / x + sqrt(1.0 / (x * x) + 1.0));
            } else {
                if abs(x) <= 1.0 { set_err("Ungültige Eingabe"); return; }
                r = 0.5 * log((x + 1.0) / (x - 1.0));
            }
        }
    } else if !inv {
        let t = turns(x);
        let frac = t - floor(t);
        let quarter = abs(frac * 4.0 - round(frac * 4.0)) < 1.0e-12;
        let q = (round(frac * 4.0) as! i64) % 4;      // 0: 0°, 1: 90°, 2: 180°, 3: 270°
        let a = to_rad(x);
        var s = sin(a);
        var c = cos(a);
        if quarter {
            s = match q { 1 => 1.0, 3 => -1.0, _ => 0.0 };
            c = match q { 0 => 1.0, 2 => -1.0, _ => 0.0 };
        }
        s = clean(s);
        c = clean(c);
        if name == "sin" { r = s; }
        else if name == "cos" { r = c; }
        else if name == "tan" {
            if c == 0.0 { set_err("Ungültige Eingabe"); return; }
            r = s / c;
        } else if name == "sec" {
            if c == 0.0 { set_err("Ungültige Eingabe"); return; }
            r = 1.0 / c;
        } else if name == "csc" {
            if s == 0.0 { set_err("Ungültige Eingabe"); return; }
            r = 1.0 / s;
        } else {
            if s == 0.0 { set_err("Ungültige Eingabe"); return; }
            r = c / s;
        }
        r = nf::round_sig(clean(r), 15);
    } else {
        if name == "sin" || name == "cos" {
            if abs(x) > 1.0 { set_err("Ungültige Eingabe"); return; }
            r = from_rad(if name == "sin" { asin(x) } else { acos(x) });
        } else if name == "tan" { r = from_rad(atan(x)); }
        else if name == "sec" {
            if abs(x) < 1.0 { set_err("Ungültige Eingabe"); return; }
            r = from_rad(acos(1.0 / x));
        } else if name == "csc" {
            if abs(x) < 1.0 { set_err("Ungültige Eingabe"); return; }
            r = from_rad(asin(1.0 / x));
        } else {
            r = from_rad(if x == 0.0 { PI / 2.0 } else if x > 0.0 { atan(1.0 / x) } else { atan(1.0 / x) + PI });
        }
        // Gerundet wird in der Anzeige; 30,000000000000004 wird so 30.
        let rr = round(r * 1.0e10) / 1.0e10;
        if abs(rr - r) < 1.0e-12 { r = rr; }
    }
    unary_result(r, label);
}

// --- Fakultät, Grad-Minuten-Sekunden ----------------------------------------------

// Gamma nach Lanczos, für nicht ganzzahlige n!.
recursive fn gamma(x: f64) -> f64 {
    if x < 0.5 { return PI / (sin(PI * x) * gamma(1.0 - x)); }
    let g = 7.0;
    let c: f64[9] = [0.99999999999980993, 676.5203681218851, -1259.1392167224028,
                     771.32342877765313, -176.61502916214059, 12.507343278686905,
                     -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];
    let y = x - 1.0;
    var a = c[0];
    let t = y + g + 0.5;
    for i in 1..9 { a += c[i] / (y + i); }
    nf::round_sig(sqrt(TAU) * pow(t, y + 0.5) * exp(-t) * a, 15)
}

fn factorial(x: f64) -> f64 {
    if round(x) == x && x >= 0.0 {
        if x > 170.0 { return 1.0 / 0.0; }
        var r = 1.0;
        var i = 2.0;
        while i <= x { r *= i; i += 1.0; }
        return r;
    }
    gamma(x + 1.0)
}

// 1,5° -> 1,3 (1° 30'), wie die Windows-Taste "→dms".
fn to_dms(x: f64) -> f64 {
    let neg = x < 0.0;
    let a = abs(x);
    let d = floor(a);
    let m_all = (a - d) * 60.0;
    let m = floor(m_all + 1.0e-9);
    let s = (m_all - m) * 60.0;
    let r = d + m / 100.0 + s / 10000.0;
    if neg { -r } else { r }
}

fn from_dms(x: f64) -> f64 {
    let neg = x < 0.0;
    let a = abs(x);
    let d = floor(a);
    let rest = (a - d) * 100.0;
    let m = floor(rest + 1.0e-9);
    let s = (rest - m) * 100.0;
    let r = d + m / 60.0 + s / 3600.0;
    if neg { -r } else { r }
}

// --- Konstanten, Zufall ------------------------------------------------------------

fn constant(v: f64) {
    if is_error() { clear_all(); }
    leave_eq();
    cur = v;
    entering = false;
    operand_set = false;
    operand.resize(0);
    has_cur = true;
}

fn random() {
    if !rng_ready {
        rng_state = rng { random_seed() };
        rng_ready = true;
    }
    constant(rng_state.rand_flt());
}

// --- Operatoren, Klammern, "=" --------------------------------------------------------

fn binary(op: i64) {
    if is_error() { return; }
    if after_eq {
        reset_expr();
        eq_line.resize(0);
        after_eq = false;
        has_cur = true;
    }
    if !has_cur && last_tok == TOK_OP {
        // Ein zweiter Operator ersetzt den ersten.
        ops[ops.len - 1] = op;
        toks[toks.len - 1] = op_text(op);
        return;
    }
    commit();
    reduce(prec(op), right_assoc(op));
    ops.push(op);
    toks.push(op_text(op));
    last_tok = TOK_OP;
    if is_error() { return; }
    cur = vals[vals.len - 1];
    after_value();
}

// "%" im Standardmodus.
fn percent() {
    if is_error() { return; }
    leave_eq();
    var r = 0.0;
    if ops.len > 0 && vals.len > 0 {
        let op = ops[ops.len - 1];
        let a = vals[vals.len - 1];
        r = if op == ADD || op == SUB { a * cur / 100.0 } else { cur / 100.0 };
    }
    cur = r;
    operand.resize(0);
    var t: u8[>..] = [];
    nf::format_num(t, r);
    operand.append(t[..min(t.len, 200)]);
    operand_set = true;
    entering = false;
    has_cur = true;
}

fn lparen() {
    if is_error() { return; }
    leave_eq();
    if depth >= 25 { return; }
    ops.push(LPAREN);
    toks.push("(");
    last_tok = TOK_LPAREN;
    depth++;
    cur = 0.0;
    after_value();
}

fn rparen() {
    if is_error() || depth == 0 { return; }
    commit();
    reduce(0, false);
    if is_error() { return; }
    ops.pop();     // die "("
    depth--;
    let r = vals.pop();
    // Den Inhalt der Klammer zu einem Operanden zusammenfassen.
    var i = toks.len - 1;
    while i >= 0 && toks[i] != "(" { i--; }
    var label: u8[>..] = [];
    label.push('(');
    for k in i + 1..toks.len {
        if k > i + 1 && toks[k - 1] != "(" && toks[k] != ")" { label.push(' '); }
        label.append(toks[k]);
    }
    label.push(')');
    toks.pop_n(toks.len - i);
    last_tok = if toks.len > 0 { TOK_OP } else { TOK_NONE };
    cur = r;
    operand.resize(0);
    operand.append(label[..min(label.len, 200)]);
    operand_set = true;
    entering = false;
    has_cur = true;
}

// Teile des Rechenwegs mit Leerzeichen, aber "(3 + 4)" ohne innere.
fn join_toks(out: u8[>..]&) {
    for t, i in toks {
        if i > 0 && toks[i - 1] != "(" && t != ")" { out.push(' '); }
        out.append(t);
    }
}

fn expr_text(out: u8[>..]&) {
    if after_eq {
        out.append(eq_line);
        return;
    }
    join_toks(out);
    if operand_set {
        if toks.len > 0 && toks[toks.len - 1] != "(" { out.push(' '); }
        out.append(operand);
    }
}

fn add_history(expr: const u8[:], v: f64) {
    var item = HistItem { expr: [], res: [], val: v };
    item.expr.append(expr[..min(expr.len, 400)]);
    var t: u8[>..] = [];
    nf::format_num(t, v, fe);
    item.res.append(t[..min(t.len, 80)]);
    history.push(item);
}

fn equals() {
    if is_error() { clear_all(); return; }
    if after_eq {
        // Nochmal "=": die letzte Rechnung wiederholen.
        if last_op == 0 { return; }
        var line: u8[>..] = [];
        nf::format_num(line, cur, fe);
        format(line, " ", op_text(last_op), " ");
        nf::format_num(line, last_rhs, fe);
        line.append(" =");
        let r = binop(last_op, cur, last_rhs);
        if is_error() || !check_result(r) { return; }
        eq_line.resize(0);
        eq_line.append(line[..min(line.len, 400)]);
        cur = r;
        add_history(eq_line, r);
        return;
    }
    let had_ops = ops.len > 0;
    commit();
    while depth > 0 && !is_error() {
        reduce(0, false);
        ops.pop();
        depth--;
        toks.push(")");
    }
    reduce(0, false);
    if is_error() { return; }
    let r = vals[vals.len - 1];
    if !had_ops { last_op = 0; }
    var line: u8[>..] = [];
    join_toks(line);
    line.append(" =");
    reset_expr();
    eq_line.resize(0);
    eq_line.append(line[..min(line.len, 400)]);
    cur = r;
    after_value();
    has_cur = true;
    after_eq = true;
    add_history(eq_line, r);
}

// --- Speicher, Verlauf --------------------------------------------------------------

fn mem_store() {
    if is_error() { return; }
    memory.push(cur);
    entering = false;
}

fn mem_add(sign: f64) {
    if is_error() { return; }
    if memory.len == 0 { memory.push(0.0); }
    memory[memory.len - 1] += sign * cur;
    entering = false;
}

fn mem_recall_at(i: i64) {
    if i < 0 || i >= memory.len { return; }
    constant(memory[i]);
}

fn mem_recall() { mem_recall_at(memory.len - 1); }

fn mem_clear() { memory.clear(); }

fn recall_history(i: i64) {
    if i < 0 || i >= history.len { return; }
    clear_all();
    eq_line.append(history[i].expr);
    cur = history[i].val;
    after_eq = true;
    has_cur = true;
}

// --- Anzeige ------------------------------------------------------------------------

fn display_text(out: u8[>..]&) {
    if is_error() {
        out.append(err);
        return;
    }
    if entering {
        nf::de_text(out, entry);
        return;
    }
    nf::format_num(out, cur, fe);
}

// Text für die Zwischenablage (Strg+C): ohne Tausendertrenner.
fn copy_text(out: u8[>..]&) {
    if is_error() { out.append(err); return; }
    nf::format_num(out, cur, fe, false);
}

// Strg+V: eine Zahl einfügen, "1.234,5" wie "1234.5".
fn paste(text: const u8[:]) {
    var t: u8[..48] = [];
    let s = trim(text);
    let has_comma = find(s, ",") >= 0;
    for c in s {
        if ascii::is_digit(c) || c == '-' || c == 'e' || c == 'E' || c == '+' {
            if t.len < 47 { t.push(if c == 'E' { 'e' } else { c }); }
        } else if c == ',' || (c == '.' && !has_comma) {
            if t.len < 47 { t.push('.'); }
        }
    }
    let v, ok = parse_flt(t);
    if !ok { return; }
    constant(v);
}
