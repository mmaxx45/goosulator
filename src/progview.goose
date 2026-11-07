// "Programmierer": ganze Zahlen in HEX, DEC, OCT und BIN, Wortbreiten von
// QWORD bis BYTE, Bitoperationen, Verschiebungen und das Bit-Tastenfeld.
import std;
import gfx;
import ui;
import src.numfmt;
import src.theme;
import src.kit;

namespace pv;

let ADD = 1;
let SUB = 2;
let MUL = 3;
let DIV = 4;
let MOD = 5;
let AND = 6;
let OR = 7;
let XOR = 8;
let NAND = 9;
let NOR = 10;
let LSH = 11;
let RSH = 12;
let LPAREN = 100;

let SHIFT_ARITH = 0;
let SHIFT_LOGIC = 1;
let SHIFT_ROT = 2;
let SHIFT_ROT_CARRY = 3;

var radix = 10;
var bits = 64;
var shift_mode = SHIFT_ARITH;
var carry = false;

var vals: i64[>..<];
var ops: i64[>..<];
var toks: u8[..120][>..<];
var depth = 0;
var last_was_op = false;

var cur: i64 = 0;
var entry: u8[..80];
var entering = false;
var operand: u8[..120];
var operand_set = false;
var has_cur = false;
var after_eq = false;
var eq_line: u8[..300];
var err: u8[..80];
var memory: i64[>..<];

var bit_pad = false;            // Bit-Tastenfeld statt Zifferntasten
var bitwise_open = false;
var shift_open = false;
var mem_open = false;

// --- Zahlen und Wortbreite ----------------------------------------------------------------

fn mask() -> u64 { if bits == 64 { 0xFFFFFFFFFFFFFFFF } else { (1 << bits) - 1 } }

// Auf die Wortbreite kürzen und vorzeichenrichtig erweitern.
fn norm(v: u64) -> i64 {
    if bits == 64 { return v as! i64; }
    let m = mask();
    var x = v & m;
    if (x & (1 << (bits - 1))) != 0 { x |= ~m; }
    x as! i64
}

fn unsigned(v: i64) -> u64 { (v as! u64) & mask() }

// Zahl in einer Basis, mit Gruppen: HEX/BIN in Vierern mit Leerzeichen,
// OCT in Dreiern, DEC mit Tausenderpunkten.
fn format_in(out: u8[>..]&, v: i64, base: i64, group: bool = true) {
    if base == 10 {
        var raw: u8[>..] = [];
        format(raw, v);
        if group { nf::de_text(out, raw); } else { out.append(raw); }
        return;
    }
    var raw: u8[>..] = [];
    format_uint(raw, unsigned(v), base, 0, '0');
    let g = if base == 8 { 3 } else { 4 };
    for c, i in raw {
        out.push(if c >= 'a' && c <= 'z' { c - 32 } else { c });
        let left = raw.len - i - 1;
        if group && left > 0 && left % g == 0 { out.push(' '); }
    }
}

fn text_of(v: i64) -> u8[>..] {
    var s: u8[>..] = [];
    format_in(s, v, radix);
    s
}

fn digit_ok(d: u8) -> bool {
    let v = if d >= '0' && d <= '9' { (d - '0') as i64 } else if d >= 'A' && d <= 'F' { (d - 'A' + 10) as i64 } else { 99 };
    v < radix
}

// Passt die Eingabe noch in die Wortbreite?
fn entry_fits(t: const u8[:]) -> bool {
    if radix == 10 {
        let v, ok = parse_int(t);
        if !ok { return false; }
        if bits == 64 { return true; }
        let lim: i64 = 1 << (bits - 1);
        v >= -lim && v < lim
    } else {
        let v, ok = parse_uint(t, radix);
        if !ok { return false; }
        bits == 64 || v <= mask()
    }
}

fn entry_value() -> i64 {
    if entry.len == 0 { return 0; }
    if radix == 10 {
        let v, ok = parse_int(entry);
        if ok { norm(v as! u64) } else { 0 }
    } else {
        let v, ok = parse_uint(entry, radix);
        if ok { norm(v) } else { 0 }
    }
}

// --- Rechnen ------------------------------------------------------------------------------

fn prec(op: i64) -> i64 {
    match op {
        MUL, DIV, MOD => 5,
        ADD, SUB => 4,
        LSH, RSH => 3,
        AND, NAND => 2,
        XOR => 1,
        _ => 0,
    }
}

fn op_text(op: i64) -> const u8[:] {
    match op {
        ADD => "+", SUB => "−", MUL => "×", DIV => "÷", MOD => "%",
        AND => "AND", OR => "OR", XOR => "XOR", NAND => "NAND", NOR => "NOR",
        LSH => "Lsh", RSH => "Rsh",
        _ => "?",
    }
}

fn set_err(m: const u8[:]) { err.resize(0); err.append(m); }
fn ok() -> bool { err.len == 0 }

fn binop(op: i64, a: i64, b: i64) -> i64 {
    let ua = a as! u64;
    let ub = b as! u64;
    match op {
        ADD => norm(ua + ub),
        SUB => norm(ua - ub),
        MUL => norm(ua * ub),
        DIV => block {
            if b == 0 { set_err("Division durch Null nicht möglich"); break 0; }
            if b == -1 { break norm(0 - ua); }
            norm((a / b) as! u64)
        },
        MOD => block {
            if b == 0 { set_err("Division durch Null nicht möglich"); break 0; }
            if b == -1 { break 0; }
            rem(a, b)
        },
        AND => norm(ua & ub),
        OR => norm(ua | ub),
        XOR => norm(ua ^ ub),
        NAND => norm(~(ua & ub)),
        NOR => norm(~(ua | ub)),
        LSH => block {
            if b < 0 || b >= bits { break 0; }
            norm(ua << b)
        },
        RSH => block {
            if b < 0 { break 0; }
            if shift_mode == SHIFT_LOGIC {
                if b >= bits { break 0; }
                break norm(unsigned(a) >> b);
            }
            if b >= 64 { break if a < 0 { -1 } else { 0 }; }
            a >> b
        },
        _ => 0,
    }
}

fn apply_top() {
    let op = ops.pop();
    let b = vals.pop();
    let a = vals.pop();
    vals.push(binop(op, a, b));
}

fn reduce(p: i64) {
    while ops.len > 0 && ok() {
        let top = ops[ops.len - 1];
        if top == LPAREN || prec(top) < p { break; }
        apply_top();
    }
}

fn label_of_cur(out: u8[>..]&) {
    if operand_set { out.append(operand); } else { format_in(out, cur, radix); }
}

fn commit() {
    vals.push(cur);
    var t: u8[>..] = [];
    label_of_cur(t);
    toks.push(t[..min(t.len, 120)]);
    last_was_op = false;
}

fn reset_expr() {
    vals.clear();
    ops.clear();
    toks.clear();
    depth = 0;
    last_was_op = false;
}

fn clear_all() {
    reset_expr();
    cur = 0;
    entry.resize(0);
    entering = false;
    operand.resize(0);
    operand_set = false;
    has_cur = false;
    after_eq = false;
    eq_line.resize(0);
    err.resize(0);
}

fn leave_eq() {
    if after_eq {
        reset_expr();
        eq_line.resize(0);
        after_eq = false;
    }
}

fn digit(d: u8) {
    var c = d;
    if c >= 'a' && c <= 'f' { c -= 32; }
    if !digit_ok(c) { return; }
    if !ok() { clear_all(); }
    leave_eq();
    if !entering {
        entry.resize(0);
        entering = true;
        operand_set = false;
        has_cur = true;
    }
    var t: u8[..80] = [];
    if entry != "0" && entry != "-0" { t.append(entry); } else if entry == "-0" { t.push('-'); }
    t.push(c);
    if t.len > 70 || !entry_fits(t) { return; }
    entry = t;
    cur = entry_value();
}

fn backspace() {
    if !ok() { clear_all(); return; }
    if after_eq { eq_line.resize(0); return; }
    if !entering { return; }
    entry.resize(entry.len - 1);
    if entry.len == 0 || entry == "-" { entry.resize(0); entry.push('0'); }
    cur = entry_value();
}

fn clear_entry() {
    if !ok() || after_eq { clear_all(); return; }
    cur = 0;
    entry.resize(0);
    entering = false;
    operand_set = false;
    has_cur = true;
}

fn unary_result(r: i64, name: const u8[:]) {
    var t: u8[>..] = [];
    t.append(name);
    t.push('(');
    label_of_cur(t);
    t.push(')');
    leave_eq();
    cur = r;
    operand.resize(0);
    operand.append(t[..min(t.len, 120)]);
    operand_set = true;
    entering = false;
    has_cur = true;
}

fn negate() {
    if !ok() { return; }
    if entering && radix == 10 {
        if entry.len > 0 && entry[0] == '-' {
            var t: u8[..80] = [];
            t.append(entry[1..]);
            entry = t;
        } else if entry != "0" {
            var t: u8[..80] = [];
            t.push('-');
            t.append(entry);
            if !entry_fits(t) { return; }
            entry = t;
        }
        cur = entry_value();
        return;
    }
    unary_result(norm(0 - (cur as! u64)), "negate");
}

fn not() {
    if !ok() { return; }
    unary_result(norm(~(cur as! u64)), "NOT");
}

// Rundschiebung um ein Bit, wie die Tasten RoL/RoR.
fn rotate(left: bool) {
    if !ok() { return; }
    let u = unsigned(cur);
    let top: u64 = 1 << (bits - 1);
    var r: u64 = 0;
    if shift_mode == SHIFT_ROT {
        r = if left { (u << 1) | (if (u & top) != 0 { 1 } else { 0 }) }
            else { (u >> 1) | (if (u & 1) != 0 { top } else { 0 }) };
    } else {
        let c: u64 = if carry { 1 } else { 0 };
        if left {
            carry = (u & top) != 0;
            r = (u << 1) | c;
        } else {
            carry = (u & 1) != 0;
            r = (u >> 1) | (if c != 0 { top } else { 0 });
        }
    }
    unary_result(norm(r), if left { "RoL" } else { "RoR" });
}

fn binary(op: i64) {
    if !ok() { return; }
    if after_eq {
        reset_expr();
        eq_line.resize(0);
        after_eq = false;
        has_cur = true;
    }
    if !has_cur && last_was_op {
        ops[ops.len - 1] = op;
        toks[toks.len - 1] = op_text(op);
        return;
    }
    commit();
    reduce(prec(op));
    ops.push(op);
    toks.push(op_text(op));
    last_was_op = true;
    if !ok() { return; }
    cur = vals[vals.len - 1];
    entering = false;
    has_cur = false;
    operand_set = false;
}

fn lparen() {
    if !ok() { return; }
    leave_eq();
    ops.push(LPAREN);
    toks.push("(");
    depth++;
    cur = 0;
    entering = false;
    has_cur = false;
    operand_set = false;
    last_was_op = false;
}

fn join(out: u8[>..]&) {
    for t, i in toks {
        if i > 0 && toks[i - 1] != "(" && t != ")" { out.push(' '); }
        out.append(t);
    }
}

fn rparen() {
    if !ok() || depth == 0 { return; }
    commit();
    reduce(0);
    if !ok() { return; }
    ops.pop();
    depth--;
    let r = vals.pop();
    var i = toks.len - 1;
    while i >= 0 && toks[i] != "(" { i--; }
    var t: u8[>..] = [];
    t.push('(');
    for k in i + 1..toks.len {
        if k > i + 1 && toks[k - 1] != "(" { t.push(' '); }
        t.append(toks[k]);
    }
    t.push(')');
    toks.pop_n(toks.len - i);
    cur = r;
    operand.resize(0);
    operand.append(t[..min(t.len, 120)]);
    operand_set = true;
    entering = false;
    has_cur = true;
    last_was_op = toks.len > 0;
}

fn equals() {
    if !ok() { clear_all(); return; }
    if after_eq { return; }
    commit();
    while depth > 0 && ok() {
        reduce(0);
        ops.pop();
        depth--;
        toks.push(")");
    }
    reduce(0);
    if !ok() { return; }
    let r = vals[vals.len - 1];
    var line: u8[>..] = [];
    join(line);
    line.append(" =");
    reset_expr();
    eq_line.resize(0);
    eq_line.append(line[..min(line.len, 300)]);
    cur = r;
    entering = false;
    operand_set = false;
    has_cur = true;
    after_eq = true;
}

fn set_radix(r: i64) {
    if r == radix { return; }
    radix = r;
    entering = false;
    // Die Eingabe der alten Basis gilt nicht in der neuen.
    for c in entry { if !digit_ok(c) {} }
}

fn set_bits(b: i64) {
    bits = b;
    cur = norm(cur as! u64);
    for &v in vals { v = norm(v as! u64); }
    entering = false;
}

fn toggle_bit(i: i64) {
    if !ok() { clear_all(); }
    leave_eq();
    cur = norm((cur as! u64) ^ (1 << i));
    entering = false;
    operand_set = false;
    has_cur = true;
}

// --- Anzeige ------------------------------------------------------------------------------

fn expr_text(out: u8[>..]&) {
    if after_eq { out.append(eq_line); return; }
    join(out);
    if operand_set {
        if toks.len > 0 && toks[toks.len - 1] != "(" { out.push(' '); }
        out.append(operand);
    }
}

fn display_text(out: u8[>..]&) {
    if !ok() { out.append(err); return; }
    format_in(out, cur, radix);
}

fn word_name() -> const u8[:] {
    match bits { 64 => "QWORD", 32 => "DWORD", 16 => "WORD", _ => "BYTE" }
}

fn radix_row(ctx: ui::Context, name: const u8[:], r: i64) {
    ui::layout_row_dynamic(ctx, 24.0, 1);
    let st, rect = ui::widget(ctx);
    if st == ui::WIDGET_INVALID { return; }
    let hot = st == ui::WIDGET_VALID && kit::hovered(ctx, rect);
    if hot { ui::fill_rect(ctx, rect, 4.0, th::pal.flat_hover); }
    if radix == r {
        ui::fill_rect(ctx, ui::rect(rect.x + 2.0, rect.y + 5.0, 3.0, rect.h - 10.0), 1.5, th::pal.bar);
    }
    let font = if radix == r { th::f_small } else { th::f_text };
    kit::text_left(ctx, ui::rect(rect.x + 14.0, rect.y, 48.0, rect.h), name, font, th::pal.text);
    var v: u8[>..] = [];
    if ok() { format_in(v, cur, r); }
    kit::text_left(ctx, ui::rect(rect.x + 64.0, rect.y, rect.w - 70.0, rect.h), v, th::f_text, th::pal.text);
    if hot && kit::clicked(ctx, rect) { set_radix(r); }
}

fn k(ctx: ui::Context, label: const u8[:], kind: i64, enabled: bool = true) -> bool {
    let big = label == "÷" || label == "×" || label == "−" || label == "+" || label == "=";
    let font = if kind == th::K_NUM { th::f_num } else if big { th::f_op } else { th::f_key };
    th::key(ctx, label, kind, font, enabled)
}

fn dk(ctx: ui::Context, d: u8) {
    let t: u8[1] = [d];
    if k(ctx, t, th::K_NUM, digit_ok(d)) { digit(d); }
}

fn hk(ctx: ui::Context, d: u8) {
    let t: u8[1] = [d];
    if k(ctx, t, th::K_OP, digit_ok(d)) { digit(d); }
}

fn keypad(ctx: ui::Context, h: f32) {
    let rh = (h - 6.0 * 2.0) / 6.0;
    let e = ok();
    let rot = shift_mode == SHIFT_ROT || shift_mode == SHIFT_ROT_CARRY;
    ui::layout_row_dynamic(ctx, rh, 5);
    hk(ctx, 'A');
    if rot {
        if k(ctx, "RoL", th::K_OP, e) { rotate(true); }
        if k(ctx, "RoR", th::K_OP, e) { rotate(false); }
    } else {
        ui::style_push_font(ctx, th::f_sym);
        if th::key(ctx, "≪", th::K_OP, th::f_sym, e) { binary(LSH); }
        if th::key(ctx, "≫", th::K_OP, th::f_sym, e) { binary(RSH); }
        ui::style_pop_font(ctx);
    }
    let clear_label = if entering || operand_set { "CE" } else { "C" };
    if k(ctx, clear_label, th::K_OP) { if clear_label == "CE" { clear_entry(); } else { clear_all(); } }
    if th::icon_key(ctx, 0xE750, th::K_OP) { backspace(); }

    ui::layout_row_dynamic(ctx, rh, 5);
    hk(ctx, 'B');
    if k(ctx, "(", th::K_OP, e) { lparen(); }
    if k(ctx, ")", th::K_OP, e && depth > 0) { rparen(); }
    if k(ctx, "%", th::K_OP, e) { binary(MOD); }
    if k(ctx, "÷", th::K_OP, e) { binary(DIV); }

    ui::layout_row_dynamic(ctx, rh, 5);
    hk(ctx, 'C');
    dk(ctx, '7'); dk(ctx, '8'); dk(ctx, '9');
    if k(ctx, "×", th::K_OP, e) { binary(MUL); }

    ui::layout_row_dynamic(ctx, rh, 5);
    hk(ctx, 'D');
    dk(ctx, '4'); dk(ctx, '5'); dk(ctx, '6');
    if k(ctx, "−", th::K_OP, e) { binary(SUB); }

    ui::layout_row_dynamic(ctx, rh, 5);
    hk(ctx, 'E');
    dk(ctx, '1'); dk(ctx, '2'); dk(ctx, '3');
    if k(ctx, "+", th::K_OP, e) { binary(ADD); }

    ui::layout_row_dynamic(ctx, rh, 5);
    hk(ctx, 'F');
    if k(ctx, "+/-", th::K_NUM, e) { negate(); }
    dk(ctx, '0');
    if k(ctx, ",", th::K_NUM, false) {}
    if k(ctx, "=", th::K_EQ) { equals(); }
}

// 64 Bits in vier Zeilen zu je vier Vierergruppen, mit Bitnummern darunter.
fn bit_keypad(ctx: ui::Context, h: f32) {
    let u = cur as! u64;
    let rh = min((h - 8.0) / 4.0 - 18.0, 30.0);
    for line in 4 {
        ui::layout_row_dynamic(ctx, rh, 4);
        for g in 4 {
            let hi = 63 - line * 16 - g * 4;
            if ui::group_begin(ctx, str("bits", line, "_", g), ui::WINDOW_NO_SCROLLBAR) {
                ui::layout_row_dynamic(ctx, rh - 2.0, 4);
                for b in 4 {
                    let i = hi - b;
                    let on = ((u >> i) & 1) != 0;
                    let t = if on { "1" } else { "0" };
                    var s = th::s_flat;
                    s.text_normal = if i < bits { if on { th::pal.text } else { th::pal.text_dim } } else { th::pal.text_off };
                    s.padding = float2 { 0.0, 0.0 };
                    ui::style_push_font(ctx, th::f_num);
                    let hit = ui::button_label_styled(ctx, s, t);
                    ui::style_pop_font(ctx);
                    if hit && i < bits { toggle_bit(i); }
                }
                ui::group_end(ctx);
            }
        }
        ui::layout_row_dynamic(ctx, 16.0, 4);
        for g in 4 {
            let lo = 60 - line * 16 - g * 4;
            th::text(ctx, str(lo), th::f_small, th::pal.text_dim, ui::TEXT_LEFT);
        }
    }
}

fn draw(ctx: ui::Context, w: f32, h: f32, used: f32) {
    var e: u8[>..] = [];
    expr_text(e);
    ui::layout_row_dynamic(ctx, 22.0, 1);
    let st, r = ui::widget(ctx);
    if st != ui::WIDGET_INVALID {
        kit::text_right(ctx, ui::rect(r.x + 8.0, r.y, r.w - 16.0, r.h), e, th::f_expr, th::pal.text_dim);
    }
    var d: u8[>..] = [];
    display_text(d);
    ui::layout_row_dynamic(ctx, 56.0, 1);
    let st2, r2 = ui::widget(ctx);
    if st2 != ui::WIDGET_INVALID {
        kit::text_right(ctx, ui::rect(r2.x + 8.0, r2.y, r2.w - 16.0, r2.h), d,
                        th::fit_font(d, r2.w - 16.0), th::pal.text);
    }
    radix_row(ctx, "HEX", 16);
    radix_row(ctx, "DEC", 10);
    radix_row(ctx, "OCT", 8);
    radix_row(ctx, "BIN", 2);

    // Symbolleiste: Tastenfeld, Bit-Tastenfeld, Wortbreite, Speicher.
    ui::layout_row_begin(ctx, ui::STATIC, 32.0, 5);
    ui::layout_row_push(ctx, 40.0);
    if th::icon_key(ctx, 0xE8EF, if !bit_pad { th::K_FLAT_SEL } else { th::K_FLAT }) { bit_pad = false; }
    ui::layout_row_push(ctx, 40.0);
    if th::icon_key(ctx, 0xE80A, if bit_pad { th::K_FLAT_SEL } else { th::K_FLAT }) { bit_pad = true; }
    ui::layout_row_push(ctx, max(w - 8.0 - 80.0 - 96.0 - 8.0, 60.0));
    if th::key(ctx, word_name(), th::K_FLAT, th::f_small) {
        set_bits(match bits { 64 => 32, 32 => 16, 16 => 8, _ => 64 });
    }
    ui::layout_row_push(ctx, 48.0);
    if th::key(ctx, "MS", th::K_FLAT, th::f_small, ok()) { memory.push(cur); }
    ui::layout_row_push(ctx, 48.0);
    if th::key(ctx, "M˅", if mem_open { th::K_FLAT_SEL } else { th::K_FLAT }, th::f_small,
               memory.len > 0 || mem_open) {
        mem_open = !mem_open;
    }
    ui::layout_row_end(ctx);

    ui::layout_row_begin(ctx, ui::STATIC, 32.0, 2);
    ui::layout_row_push(ctx, 120.0);
    let bb = ui::widget_bounds(ctx);
    if th::key(ctx, "  Bitweise  ˅", if bitwise_open { th::K_FLAT_SEL } else { th::K_FLAT }, th::f_text, ok()) {
        bitwise_open = !bitwise_open;
        shift_open = false;
    }
    ui::layout_row_push(ctx, 160.0);
    let sb = ui::widget_bounds(ctx);
    if th::key(ctx, "  Bitverschiebung  ˅", if shift_open { th::K_FLAT_SEL } else { th::K_FLAT }, th::f_text) {
        shift_open = !shift_open;
        bitwise_open = false;
    }
    ui::layout_row_end(ctx);

    let win = ui::window_get_position(ctx);
    if bitwise_open {
        let pr = ui::rect(bb.x - win.x, bb.y - win.y + 34.0, 260.0, 92.0);
        if ui::popup_begin(ctx, ui::POPUP_STATIC, "bitweise", ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_BORDER, pr) {
            ui::layout_row_dynamic(ctx, 38.0, 3);
            if th::key(ctx, "AND", th::K_OP, th::f_key) { binary(AND); bitwise_open = false; }
            if th::key(ctx, "OR", th::K_OP, th::f_key) { binary(OR); bitwise_open = false; }
            if th::key(ctx, "NOT", th::K_OP, th::f_key) { not(); bitwise_open = false; }
            ui::layout_row_dynamic(ctx, 38.0, 3);
            if th::key(ctx, "NAND", th::K_OP, th::f_key) { binary(NAND); bitwise_open = false; }
            if th::key(ctx, "NOR", th::K_OP, th::f_key) { binary(NOR); bitwise_open = false; }
            if th::key(ctx, "XOR", th::K_OP, th::f_key) { binary(XOR); bitwise_open = false; }
            ui::popup_end(ctx);
        } else { bitwise_open = false; }
    }
    if shift_open {
        let pr = ui::rect(sb.x - win.x, sb.y - win.y + 34.0, 280.0, 140.0);
        if ui::popup_begin(ctx, ui::POPUP_STATIC, "schieben", ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_BORDER, pr) {
            let names: const u8[:][4] = ["Arithmetische Verschiebung", "Logische Verschiebung",
                                         "Rundschiebung", "Rundschiebung durch Übertrag"];
            for i in 4 {
                ui::layout_row_dynamic(ctx, 30.0, 1);
                if ui::option_label(ctx, names[i], shift_mode == i) && shift_mode != i {
                    shift_mode = i;
                    shift_open = false;
                }
            }
            ui::popup_end(ctx);
        } else { shift_open = false; }
    }

    let rest = kit::remaining(ctx, h);
    if mem_open {
        memory_list(ctx, rest);
        return;
    }
    if bit_pad { bit_keypad(ctx, rest); } else { keypad(ctx, rest); }
}

fn memory_list(ctx: ui::Context, h: f32) {
    ui::layout_row_dynamic(ctx, h - 42.0, 1);
    var pick = -1;
    if ui::group_begin(ctx, "pspeicher", 0) {
        var i = memory.len;
        while i > 0 {
            i--;
            if kit::two_line_item(ctx, "", text_of(memory[i]), 46.0) { pick = i; }
        }
        ui::group_end(ctx);
    }
    if pick >= 0 {
        leave_eq();
        cur = memory[pick];
        entering = false;
        operand_set = false;
        has_cur = true;
        mem_open = false;
    }
    let ratios: f32[2] = [0.84, 0.16];
    ui::layout_row(ctx, ui::DYNAMIC, 38.0, ratios);
    ui::spacer(ctx);
    if th::icon_key(ctx, 0xE74D, th::K_FLAT, memory.len > 0) { memory.clear(); mem_open = false; }
}

// --- Tastatur ------------------------------------------------------------------------------

fn on_char(c: u32) {
    if (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') {
        digit(c as! u8);
        return;
    }
    match c {
        '+' => binary(ADD),
        '-' => binary(SUB),
        '*' => binary(MUL),
        '/' => binary(DIV),
        '%' => binary(MOD),
        '&' => binary(AND),
        '|' => binary(OR),
        '^' => binary(XOR),
        '~' => not(),
        '<' => binary(LSH),
        '>' => binary(RSH),
        '(' => lparen(),
        ')' => rparen(),
        '=' => equals(),
        _ => {},
    }
}

fn on_key(e: gfx::Event) {
    let name = gfx::key_name(e.scancode);
    if (e.mods & gfx::MOD_CTRL) != 0 {
        if name == "C" {
            var t: u8[>..] = [];
            format_in(t, cur, radix, false);
            gfx::set_clipboard(t);
        }
        return;
    }
    if name == "Return" || name == "Keypad Enter" { equals(); }
    else if name == "Backspace" { backspace(); }
    else if name == "Escape" { clear_all(); }
    else if name == "Delete" { clear_entry(); }
    else if name == "F9" { negate(); }
    else if name == "F5" { set_radix(16); }
    else if name == "F6" { set_radix(10); }
    else if name == "F7" { set_radix(8); }
    else if name == "F8" { set_radix(2); }
}

fn enter(i: i64) {}
