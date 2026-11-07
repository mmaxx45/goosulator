// Die Seiten "Standard" und "Wissenschaftlich", mit Verlauf und Speicher.
import std;
import math;
import gfx;
import ui;
import src.numfmt;
import src.calc;
import src.theme;
import src.kit;

namespace cv;

let PANEL_HISTORY = 1;
let PANEL_MEMORY = 2;

var flyout = 0;                 // schmal: Verlauf/Speicher über den Tasten
var tab = PANEL_HISTORY;        // breit: welcher Reiter rechts
var second = false;             // "2nd"
var trig_second = false;
var trig_hyp = false;
var trig_open = false;
var func_open = false;
var hist_scroll = ui::Scroll { 0, 0 };

fn k(ctx: ui::Context, label: const u8[:], kind: i64, enabled: bool = true) -> bool {
    let font = if kind == th::K_NUM { th::f_digit } else { th::f_key };
    th::key(ctx, label, kind, font, enabled)
}

fn ok() -> bool { !calc::is_error() }

// --- Kopf: Rechenweg und Anzeige -------------------------------------------------------

fn display(ctx: ui::Context, w: f32, eh: f32, rh: f32) {
    var e: u8[>..] = [];
    calc::expr_text(e);
    ui::layout_row_dynamic(ctx, eh, 1);
    let st, r = ui::widget(ctx);
    if st != ui::WIDGET_INVALID {
        kit::text_right(ctx, ui::rect(r.x + 12.0, r.y, r.w - 26.0, r.h), e, th::f_expr, th::pal.text_dim);
    }
    var d: u8[>..] = [];
    calc::display_text(d);
    ui::layout_row_dynamic(ctx, rh, 1);
    let st2, r2 = ui::widget(ctx);
    if st2 != ui::WIDGET_INVALID {
        let font = th::fit_font_h(d, r2.w - 26.0, rh * 0.64);
        kit::text_right(ctx, ui::rect(r2.x + 12.0, r2.y, r2.w - 26.0, r2.h), d, font, th::pal.text);
    }
}

fn memory_row(ctx: ui::Context, narrow: bool, mh: f32) {
    // Sechs Spalten zu höchstens 80 px, wie MemoryPanel in Calculator.xaml.
    ui::layout_row_dynamic(ctx, mh, if narrow { 6 } else { 5 });
    let has = calc::memory.len > 0 && ok();
    if th::key(ctx, "MC", th::K_FLAT, th::f_small, has) { calc::mem_clear(); }
    if th::key(ctx, "MR", th::K_FLAT, th::f_small, has) { calc::mem_recall(); }
    if th::key(ctx, "M+", th::K_FLAT, th::f_small, ok()) { calc::mem_add(1.0); }
    if th::key(ctx, "M−", th::K_FLAT, th::f_small, ok()) { calc::mem_add(-1.0); }
    if th::key(ctx, "MS", th::K_FLAT, th::f_small, ok()) { calc::mem_store(); }
    if narrow {
        let sel = flyout == PANEL_MEMORY;
        if th::key(ctx, "M˅", if sel { th::K_FLAT_SEL } else { th::K_FLAT }, th::f_small,
                   calc::memory.len > 0 || sel) {
            flyout = if sel { 0 } else { PANEL_MEMORY };
        }
    }
}

// --- Verlauf und Speicher ---------------------------------------------------------------

fn history_list(ctx: ui::Context, h: f32) {
    ui::layout_row_dynamic(ctx, h, 1);
    if ui::group_begin(ctx, "verlauf", 0) {
        if calc::history.len == 0 {
            kit::gap(ctx, 8.0);
            ui::layout_row_dynamic(ctx, 20.0, 1);
            th::text(ctx, "  Es gibt noch keinen Verlauf.", th::f_text, th::pal.text, ui::TEXT_LEFT);
        }
        var i = calc::history.len;
        var pick = -1;
        while i > 0 {
            i--;
            let it = calc::history[i];
            if kit::two_line_item(ctx, it.expr, it.res, 62.0) { pick = i; }
        }
        if pick >= 0 {
            calc::recall_history(pick);
            flyout = 0;
        }
        ui::group_end(ctx);
    }
}

fn memory_list(ctx: ui::Context, h: f32) {
    ui::layout_row_dynamic(ctx, h, 1);
    if ui::group_begin(ctx, "speicher", 0) {
        if calc::memory.len == 0 {
            kit::gap(ctx, 8.0);
            ui::layout_row_dynamic(ctx, 20.0, 1);
            th::text(ctx, "  Im Speicher ist nichts gespeichert.", th::f_text, th::pal.text, ui::TEXT_LEFT);
        }
        var i = calc::memory.len;
        var pick = -1;
        var del = -1;
        while i > 0 {
            i--;
            let v = nf::num(calc::memory[i]);
            if kit::two_line_item(ctx, "", v, 46.0) { pick = i; }
            // Die kleinen Tasten unter jedem Wert, wie bei Windows beim Zeigen.
            let ratios: f32[4] = [0.52, 0.16, 0.16, 0.16];
            ui::layout_row(ctx, ui::DYNAMIC, 24.0, ratios);
            ui::spacer(ctx);
            if th::key(ctx, "MC", th::K_FLAT, th::f_small) { del = i; }
            if th::key(ctx, "M+", th::K_FLAT, th::f_small, ok()) { calc::memory[i] += calc::cur; }
            if th::key(ctx, "M−", th::K_FLAT, th::f_small, ok()) { calc::memory[i] -= calc::cur; }
        }
        if del >= 0 { remove_at(calc::memory, del); }
        if pick >= 0 {
            calc::mem_recall_at(pick);
            flyout = 0;
        }
        ui::group_end(ctx);
    }
}

// Der Inhalt von Verlauf/Speicher samt Papierkorb unten rechts.
fn panel(ctx: ui::Context, which: i64, h: f32) {
    if which == PANEL_HISTORY { history_list(ctx, h - 42.0); } else { memory_list(ctx, h - 42.0); }
    let ratios: f32[2] = [0.84, 0.16];
    ui::layout_row(ctx, ui::DYNAMIC, 38.0, ratios);
    ui::spacer(ctx);
    let any = if which == PANEL_HISTORY { calc::history.len > 0 } else { calc::memory.len > 0 };
    if th::icon_key(ctx, 0xE74D, th::K_FLAT, any) {
        if which == PANEL_HISTORY { calc::history.clear(); } else { calc::memory.clear(); }
    }
}

// Rechts neben dem Rechner, wenn das Fenster breit genug ist.
fn side_panel(ctx: ui::Context, h: f32) {
    let ratios: f32[3] = [0.3, 0.3, 0.4];
    ui::layout_row(ctx, ui::DYNAMIC, 40.0, ratios);
    if kit::tab(ctx, "Verlauf", tab == PANEL_HISTORY) { tab = PANEL_HISTORY; }
    if kit::tab(ctx, "Speicher", tab == PANEL_MEMORY) { tab = PANEL_MEMORY; }
    ui::spacer(ctx);
    panel(ctx, tab, h - 50.0);
}

// --- Tastenfelder -------------------------------------------------------------------------

fn digits_row(ctx: ui::Context, a: u8, b: u8, c: u8) {
    var t: u8[1] = [a];
    if k(ctx, t, th::K_NUM) { calc::digit(a); }
    t[0] = b;
    if k(ctx, t, th::K_NUM) { calc::digit(b); }
    t[0] = c;
    if k(ctx, t, th::K_NUM) { calc::digit(c); }
}

fn standard_keys(ctx: ui::Context, h: f32) {
    let rh = (h - 6.0 * 2.0) / 6.0;
    ui::layout_row_dynamic(ctx, rh, 4);
    if k(ctx, "%", th::K_OP, ok()) { calc::percent(); }
    if k(ctx, "CE", th::K_OP) { calc::clear_entry(); }
    if k(ctx, "C", th::K_OP) { calc::clear_all(); }
    if k(ctx, "⌫", th::K_OP) { calc::backspace(); }
    ui::layout_row_dynamic(ctx, rh, 4);
    if k(ctx, "¹/ₓ", th::K_OP, ok()) { calc::unary("1/"); }
    if k(ctx, "x²", th::K_OP, ok()) { calc::unary("sqr"); }
    if k(ctx, "²√x", th::K_OP, ok()) { calc::unary("√"); }
    if k(ctx, "÷", th::K_OP, ok()) { calc::binary(calc::DIV); }
    ui::layout_row_dynamic(ctx, rh, 4);
    digits_row(ctx, '7', '8', '9');
    if k(ctx, "×", th::K_OP, ok()) { calc::binary(calc::MUL); }
    ui::layout_row_dynamic(ctx, rh, 4);
    digits_row(ctx, '4', '5', '6');
    if k(ctx, "−", th::K_OP, ok()) { calc::binary(calc::SUB); }
    ui::layout_row_dynamic(ctx, rh, 4);
    digits_row(ctx, '1', '2', '3');
    if k(ctx, "+", th::K_OP, ok()) { calc::binary(calc::ADD); }
    ui::layout_row_dynamic(ctx, rh, 4);
    if k(ctx, "+/-", th::K_NUM, ok()) { calc::negate(); }
    if k(ctx, "0", th::K_NUM) { calc::digit('0'); }
    if k(ctx, ",", th::K_NUM, ok()) { calc::decimal(); }
    if k(ctx, "=", th::K_EQ) { calc::equals(); }
}

fn angle_name() -> const u8[:] {
    match calc::angle { calc::DEG => "DEG", calc::RAD => "RAD", _ => "GRAD" }
}

// Die Zeile über den Tasten: DEG, F-E; darunter Trigonometrie und Funktion.
fn sci_bars(ctx: ui::Context, narrow: bool, ch: f32, mh: f32) {
    ui::layout_row_begin(ctx, ui::STATIC, ch, 2);
    ui::layout_row_push(ctx, 56.0);
    if th::key(ctx, angle_name(), th::K_FLAT, th::f_small) { calc::angle = (calc::angle + 1) % 3; }
    ui::layout_row_push(ctx, 56.0);
    if th::key(ctx, "F-E", if calc::fe { th::K_FLAT_SEL } else { th::K_FLAT }, th::f_small, ok()) {
        calc::fe = !calc::fe;
    }
    ui::layout_row_end(ctx);
    memory_row(ctx, narrow, mh);
    ui::layout_row_begin(ctx, ui::STATIC, 34.0, 2);
    ui::layout_row_push(ctx, 140.0);
    let tb = ui::widget_bounds(ctx);
    if th::key(ctx, "  Trigonometrie  ˅", if trig_open { th::K_FLAT_SEL } else { th::K_FLAT }, th::f_text, ok()) {
        trig_open = !trig_open;
        func_open = false;
    }
    ui::layout_row_push(ctx, 120.0);
    let fb = ui::widget_bounds(ctx);
    if th::key(ctx, "  Funktion  ˅", if func_open { th::K_FLAT_SEL } else { th::K_FLAT }, th::f_text, ok()) {
        func_open = !func_open;
        trig_open = false;
    }
    ui::layout_row_end(ctx);

    let win = ui::window_get_position(ctx);
    if trig_open {
        let r = ui::rect(tb.x - win.x, tb.y - win.y + 36.0, 300.0, 92.0);
        if ui::popup_begin(ctx, ui::POPUP_STATIC, "trig", ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_BORDER, r) {
            let names: const u8[:][6] = ["sin", "cos", "tan", "sec", "csc", "cot"];
            ui::layout_row_dynamic(ctx, 38.0, 4);
            if th::key(ctx, "2nd", if trig_second { th::K_EQ } else { th::K_OP }, th::f_key) {
                trig_second = !trig_second;
            }
            for i in 0..3 { trig_key(ctx, names[i]); }
            ui::layout_row_dynamic(ctx, 38.0, 4);
            if th::key(ctx, "hyp", if trig_hyp { th::K_EQ } else { th::K_OP }, th::f_key) {
                trig_hyp = !trig_hyp;
            }
            for i in 3..6 { trig_key(ctx, names[i]); }
            ui::popup_end(ctx);
        } else {
            trig_open = false;
        }
    }
    if func_open {
        let r = ui::rect(fb.x - win.x, fb.y - win.y + 36.0, 240.0, 92.0);
        if ui::popup_begin(ctx, ui::POPUP_STATIC, "func", ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_BORDER, r) {
            ui::layout_row_dynamic(ctx, 38.0, 3);
            if th::key(ctx, "|x|", th::K_OP, th::f_key) { calc::unary("abs"); func_open = false; }
            if th::key(ctx, "⌊x⌋", th::K_OP, th::f_sym) { calc::unary("floor"); func_open = false; }
            if th::key(ctx, "⌈x⌉", th::K_OP, th::f_sym) { calc::unary("ceil"); func_open = false; }
            ui::layout_row_dynamic(ctx, 38.0, 3);
            if th::key(ctx, "rand", th::K_OP, th::f_key) { calc::random(); func_open = false; }
            if th::key(ctx, "→dms", th::K_OP, th::f_key) { calc::unary("dms"); func_open = false; }
            if th::key(ctx, "→deg", th::K_OP, th::f_key) { calc::unary("degrees"); func_open = false; }
            ui::popup_end(ctx);
        } else {
            func_open = false;
        }
    }
}

fn trig_key(ctx: ui::Context, name: const u8[:]) {
    var label: u8[>..] = [];
    label.append(name);
    if trig_hyp { label.push('h'); }
    if trig_second { label.append("⁻¹"); }
    if th::key(ctx, label, th::K_OP, th::f_key) {
        calc::trig(name, trig_second, trig_hyp);
        trig_open = false;
    }
}

fn sci_keys(ctx: ui::Context, h: f32) {
    let rh = (h - 7.0 * 2.0) / 7.0;
    let clear_label = if calc::entering || calc::operand_set { "CE" } else { "C" };
    ui::layout_row_dynamic(ctx, rh, 5);
    if th::key(ctx, "2nd", if second { th::K_EQ } else { th::K_OP }, th::f_key) { second = !second; }
    if k(ctx, "π", th::K_OP) { calc::constant(PI); }
    if k(ctx, "e", th::K_OP) { calc::constant(E); }
    if k(ctx, clear_label, th::K_OP) {
        if clear_label == "CE" { calc::clear_entry(); } else { calc::clear_all(); }
    }
    if k(ctx, "⌫", th::K_OP) { calc::backspace(); }

    ui::layout_row_dynamic(ctx, rh, 5);
    if second {
        if k(ctx, "x³", th::K_OP, ok()) { calc::unary("cube"); second = false; }
    } else {
        if k(ctx, "x²", th::K_OP, ok()) { calc::unary("sqr"); }
    }
    if k(ctx, "¹/ₓ", th::K_OP, ok()) { calc::unary("1/"); }
    if k(ctx, "|x|", th::K_OP, ok()) { calc::unary("abs"); }
    if k(ctx, "exp", th::K_OP, ok()) { calc::exp_key(); }
    if k(ctx, "mod", th::K_OP, ok()) { calc::binary(calc::MOD); }

    ui::layout_row_dynamic(ctx, rh, 5);
    if second {
        if k(ctx, "³√x", th::K_OP, ok()) { calc::unary("cuberoot"); second = false; }
    } else {
        if k(ctx, "²√x", th::K_OP, ok()) { calc::unary("√"); }
    }
    if k(ctx, "(", th::K_OP, ok()) { calc::lparen(); }
    if k(ctx, ")", th::K_OP, ok() && calc::depth > 0) { calc::rparen(); }
    if k(ctx, "n!", th::K_OP, ok()) { calc::unary("fact"); }
    if k(ctx, "÷", th::K_OP, ok()) { calc::binary(calc::DIV); }

    ui::layout_row_dynamic(ctx, rh, 5);
    if second {
        if k(ctx, "ʸ√x", th::K_OP, ok()) { calc::binary(calc::ROOT); second = false; }
    } else {
        if k(ctx, "xʸ", th::K_OP, ok()) { calc::binary(calc::POW); }
    }
    digits_row(ctx, '7', '8', '9');
    if k(ctx, "×", th::K_OP, ok()) { calc::binary(calc::MUL); }

    ui::layout_row_dynamic(ctx, rh, 5);
    if second {
        if k(ctx, "2ˣ", th::K_OP, ok()) { calc::unary("2^"); second = false; }
    } else {
        if k(ctx, "10ˣ", th::K_OP, ok()) { calc::unary("10^"); }
    }
    digits_row(ctx, '4', '5', '6');
    if k(ctx, "−", th::K_OP, ok()) { calc::binary(calc::SUB); }

    ui::layout_row_dynamic(ctx, rh, 5);
    if second {
        if k(ctx, "logᵧx", th::K_OP, ok()) { calc::binary(calc::LOGY); second = false; }
    } else {
        if k(ctx, "log", th::K_OP, ok()) { calc::unary("log"); }
    }
    digits_row(ctx, '1', '2', '3');
    if k(ctx, "+", th::K_OP, ok()) { calc::binary(calc::ADD); }

    ui::layout_row_dynamic(ctx, rh, 5);
    if second {
        if k(ctx, "eˣ", th::K_OP, ok()) { calc::unary("e^"); second = false; }
    } else {
        if k(ctx, "ln", th::K_OP, ok()) { calc::unary("ln"); }
    }
    if k(ctx, "+/-", th::K_NUM, ok()) { calc::negate(); }
    if k(ctx, "0", th::K_NUM) { calc::digit('0'); }
    if k(ctx, ",", th::K_NUM, ok()) { calc::decimal(); }
    if k(ctx, "=", th::K_EQ) { calc::equals(); }
}

// Alles unterhalb der Kopfzeile. used: was die Kopfzeile schon belegt.
// Zeilenhöhen wie in Calculator.xaml: unter der 48 px hohen Kopfzeile teilen
// sich Rechenweg, Ergebnis, (DEG/F-E,) Speicherleiste und Tasten den Rest
// im Verhältnis 22 : 72 : (32 :) 32 : 308 bzw. 276.
fn draw(ctx: ui::Context, w: f32, h: f32, used: f32, narrow: bool, scientific: bool) {
    calc::sci = scientific;
    let unit = (h - used - 3.0) / 434.0;
    display(ctx, w, 22.0 * unit - 2.0, 72.0 * unit - 2.0);
    if scientific {
        sci_bars(ctx, narrow, 32.0 * unit - 2.0, 32.0 * unit - 2.0);
    } else {
        memory_row(ctx, narrow, 32.0 * unit - 2.0);
    }
    let rest = kit::remaining(ctx, h);
    if narrow && flyout != 0 {
        panel(ctx, flyout, rest);
        return;
    }
    if scientific { sci_keys(ctx, rest); } else { standard_keys(ctx, rest); }
}

// --- Tastatur -----------------------------------------------------------------------------

fn on_char(c: u32, scientific: bool) {
    if c >= '0' && c <= '9' { calc::digit(c as! u8); return; }
    match c {
        ',', '.' => calc::decimal(),
        '+' => calc::binary(calc::ADD),
        '-' => calc::binary(calc::SUB),
        '*' => calc::binary(calc::MUL),
        '/' => calc::binary(calc::DIV),
        '=' => calc::equals(),
        '%' => if scientific { calc::binary(calc::MOD); } else { calc::percent(); },
        'r', 'R' => calc::unary("1/"),
        '@' => calc::unary("√"),
        'q', 'Q' => calc::unary("sqr"),
        '(' => if scientific { calc::lparen(); },
        ')' => if scientific { calc::rparen(); },
        '^', 'y', 'Y' => if scientific { calc::binary(calc::POW); },
        '!' => if scientific { calc::unary("fact"); },
        's', 'S' => if scientific { calc::trig("sin", false, false); },
        'o', 'O' => if scientific { calc::trig("cos", false, false); },
        't', 'T' => if scientific { calc::trig("tan", false, false); },
        'n', 'N' => if scientific { calc::unary("ln"); },
        'l', 'L' => if scientific { calc::unary("log"); },
        'p', 'P' => if scientific { calc::constant(PI); },
        'x', 'X' => if scientific { calc::exp_key(); },
        '|' => if scientific { calc::unary("abs"); },
        _ => {},
    }
}

fn on_key(e: gfx::Event, scientific: bool) {
    let ctrl = (e.mods & gfx::MOD_CTRL) != 0;
    let name = gfx::key_name(e.scancode);
    if ctrl {
        if name == "M" { calc::mem_store(); }
        else if name == "P" { calc::mem_add(1.0); }
        else if name == "Q" { calc::mem_add(-1.0); }
        else if name == "R" { calc::mem_recall(); }
        else if name == "L" { calc::mem_clear(); }
        else if name == "H" { flyout = if flyout == PANEL_HISTORY { 0 } else { PANEL_HISTORY }; }
        else if name == "C" {
            var t: u8[>..] = [];
            calc::copy_text(t);
            gfx::set_clipboard(t);
        } else if name == "V" { calc::paste(gfx::clipboard()); }
        else if name == "Shift" {}
        return;
    }
    if name == "Return" || name == "Keypad Enter" { calc::equals(); }
    else if name == "Backspace" { calc::backspace(); }
    else if name == "Escape" { calc::clear_all(); }
    else if name == "Delete" { calc::clear_entry(); }
    else if name == "F9" { calc::negate(); }
}
