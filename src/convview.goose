// Die Konverter: Währung (Kurse von frankfurter.dev), Volumen, Länge,
// Gewicht und Masse, Temperatur, Energie, Fläche, Geschwindigkeit, Zeit,
// Leistung, Daten, Druck, Winkel.
import std;
import math;
import os;
import json;
import gfx;
import ui;
import src.numfmt;
import src.theme;
import src.kit;
import src.fx;

namespace conv;

let C_CURRENCY = 0;
let C_VOLUME = 1;
let C_LENGTH = 2;
let C_WEIGHT = 3;
let C_TEMP = 4;
let C_ENERGY = 5;
let C_AREA = 6;
let C_SPEED = 7;
let C_TIME = 8;
let C_POWER = 9;
let C_DATA = 10;
let C_PRESSURE = 11;
let C_ANGLE = 12;
let CAT_COUNT = 13;

struct Unit { name: u8[..48], code: u8[..8], factor: f64 }

var cat = C_LENGTH;
var units: Unit[>..<];
var sel_from: i64[13] = [0; 13];
var sel_to: i64[13] = [0; 13];
var defaults_set = false;

var active = 0;                 // 0: oberer Wert wird eingegeben, 1: unterer
var entry: u8[..40];
var value: f64 = 0.0;           // der eingegebene Wert
var fresh = true;               // die nächste Ziffer ersetzt den Wert

fn u(name: const u8[:], factor: f64) {
    var x = Unit { name: [], code: [], factor: factor };
    x.name.append(name);
    units.push(x);
}

// Faktor: wie viele Basiseinheiten eine Einheit ist.
fn load_units(c: i64) {
    units.clear();
    match c {
        C_VOLUME => {
            u("Milliliter", 1.0); u("Kubikzentimeter", 1.0); u("Liter", 1000.0);
            u("Kubikmeter", 1.0e6); u("Teelöffel (US)", 4.92892159375);
            u("Esslöffel (US)", 14.78676478125); u("Flüssigunzen (US)", 29.5735295625);
            u("Tassen (US)", 236.5882365); u("Pints (US)", 473.176473);
            u("Quarts (US)", 946.352946); u("Gallonen (US)", 3785.411784);
            u("Kubikzoll", 16.387064); u("Kubikfuß", 28316.846592);
            u("Kubikyard", 764554.857984); u("Teelöffel (UK)", 5.919388020833333);
            u("Esslöffel (UK)", 17.758164062499999); u("Flüssigunzen (UK)", 28.4130625);
            u("Pints (UK)", 568.26125); u("Quarts (UK)", 1136.5225); u("Gallonen (UK)", 4546.09);
        },
        C_LENGTH => {
            u("Nanometer", 1.0e-9); u("Mikrometer", 1.0e-6); u("Millimeter", 0.001);
            u("Zentimeter", 0.01); u("Meter", 1.0); u("Kilometer", 1000.0); u("Zoll", 0.0254);
            u("Fuß", 0.3048); u("Yard", 0.9144); u("Meilen", 1609.344); u("Seemeilen", 1852.0);
        },
        C_WEIGHT => {
            u("Karat", 0.0002); u("Milligramm", 1.0e-6); u("Zentigramm", 1.0e-5);
            u("Dezigramm", 1.0e-4); u("Gramm", 0.001); u("Dekagramm", 0.01);
            u("Hektogramm", 0.1); u("Kilogramm", 1.0); u("Tonnen (metrisch)", 1000.0);
            u("Unzen", 0.028349523125); u("Pfund", 0.45359237); u("Stone", 6.35029318);
            u("Short Tons (US)", 907.18474); u("Long Tons (UK)", 1016.0469088);
        },
        C_TEMP => { u("Celsius", 0.0); u("Fahrenheit", 0.0); u("Kelvin", 0.0); },
        C_ENERGY => {
            u("Elektronenvolt", 1.602176634e-19); u("Joule", 1.0); u("Kilojoule", 1000.0);
            u("Thermische Kalorien", 4.184); u("Lebensmittelkalorien", 4184.0);
            u("Fußpfund", 1.3558179483314004); u("British Thermal Units", 1055.05585262);
            u("Kilowattstunden", 3.6e6);
        },
        C_AREA => {
            u("Quadratmillimeter", 1.0e-6); u("Quadratzentimeter", 1.0e-4);
            u("Quadratmeter", 1.0); u("Hektar", 1.0e4); u("Quadratkilometer", 1.0e6);
            u("Quadratzoll", 0.00064516); u("Quadratfuß", 0.09290304);
            u("Quadratyard", 0.83612736); u("Acres", 4046.8564224);
            u("Quadratmeilen", 2589988.110336);
        },
        C_SPEED => {
            u("Zentimeter pro Sekunde", 0.01); u("Meter pro Sekunde", 1.0);
            u("Kilometer pro Stunde", 1.0 / 3.6); u("Fuß pro Sekunde", 0.3048);
            u("Meilen pro Stunde", 0.44704); u("Knoten", 1852.0 / 3600.0); u("Mach", 340.3);
        },
        C_TIME => {
            u("Mikrosekunden", 1.0e-6); u("Millisekunden", 0.001); u("Sekunden", 1.0);
            u("Minuten", 60.0); u("Stunden", 3600.0); u("Tage", 86400.0);
            u("Wochen", 604800.0); u("Jahre", 31536000.0);
        },
        C_POWER => {
            u("Watt", 1.0); u("Kilowatt", 1000.0); u("Pferdestärken (US)", 745.69987158227022);
            u("Fußpfund pro Minute", 0.022596965805523); u("BTUs pro Minute", 17.584264210333);
        },
        C_DATA => {
            u("Bits", 1.0); u("Bytes", 8.0); u("Kilobits", 1.0e3); u("Kibibits", 1024.0);
            u("Kilobytes", 8.0e3); u("Kibibytes", 8192.0); u("Megabits", 1.0e6);
            u("Mebibits", 1048576.0); u("Megabytes", 8.0e6); u("Mebibytes", 8388608.0);
            u("Gigabits", 1.0e9); u("Gibibits", 1073741824.0); u("Gigabytes", 8.0e9);
            u("Gibibytes", 8589934592.0); u("Terabits", 1.0e12); u("Tebibits", 1099511627776.0);
            u("Terabytes", 8.0e12); u("Tebibytes", 8796093022208.0); u("Petabits", 1.0e15);
            u("Pebibits", 1125899906842624.0); u("Petabytes", 8.0e15);
            u("Pebibytes", 9007199254740992.0); u("Exabits", 1.0e18);
            u("Exbibits", 1152921504606846976.0); u("Exabytes", 8.0e18);
            u("Exbibytes", 9223372036854775808.0);
        },
        C_PRESSURE => {
            u("Atmosphären", 101325.0); u("Bar", 1.0e5); u("Kilopascal", 1000.0);
            u("Millimeter Quecksilbersäule", 133.322387415); u("Pascal", 1.0);
            u("Pfund pro Quadratzoll", 6894.757293168361);
        },
        C_ANGLE => { u("Grad", 1.0); u("Radiant", 180.0 / PI); u("Gon", 0.9); },
        _ => fill_currency(),
    }
}

// Die Währungen aus den geladenen Kursen, nach Namen sortiert.
fn fill_currency() {
    for code, i in fx::codes {
        var x = Unit { name: [], code: [], factor: 1.0 / fx::rates[i] };
        x.name.append(fx::name_of(code));
        x.code.append(code);
        units.push(x);
    }
    var i = 1;
    while i < units.len {
        var j = i;
        while j > 0 && compare(units[j - 1].name, units[j].name) > 0 {
            let t = units[j];
            units[j] = units[j - 1];
            units[j - 1] = t;
            j--;
        }
        i++;
    }
}

fn reload_currency() {
    var a: u8[..8] = [];
    var b: u8[..8] = [];
    if units.len > 0 {
        a.append(units[sel_from[C_CURRENCY]].code);
        b.append(units[sel_to[C_CURRENCY]].code);
    } else {
        a.append("EUR");
        b.append("USD");
    }
    load_units(C_CURRENCY);
    sel_from[C_CURRENCY] = max(index_of(a), 0);
    sel_to[C_CURRENCY] = max(index_of(b), 0);
}

fn index_of(code: const u8[:]) -> i64 {
    for x, i in units { if x.code == code { return i; } }
    -1
}

fn set_defaults() {
    if defaults_set { return; }
    defaults_set = true;
    // Wie bei Windows beim ersten Öffnen.
    let from: i64[13] = [0, 0, 3, 7, 0, 4, 2, 2, 4, 1, 12, 0, 0];
    let to: i64[13] = [0, 7, 6, 10, 1, 2, 6, 4, 3, 2, 8, 1, 1];
    sel_from = from;
    sel_to = to;
}

fn enter(c: i64) {
    set_defaults();
    cat = c;
    load_units(c);
    if c == C_CURRENCY {
        fx::start();
        if fx::changed { fx::changed = false; reload_currency(); }
        else if units.len > 0 && sel_from[c] == sel_to[c] {
            sel_from[c] = max(index_of("EUR"), 0);
            sel_to[c] = max(index_of("USD"), 0);
        }
    }
    sel_from[c] = clamp(sel_from[c], 0, max(units.len - 1, 0));
    sel_to[c] = clamp(sel_to[c], 0, max(units.len - 1, 0));
    active = 0;
    entry.resize(0);
    entry.push(if c == C_CURRENCY { '1' } else { '1' });
    value = 1.0;
    fresh = true;
    if c == C_TEMP { entry.resize(0); entry.push('0'); value = 0.0; }
}

// --- Umrechnen ----------------------------------------------------------------------------------

fn to_celsius(i: i64, v: f64) -> f64 {
    match i { 1 => (v - 32.0) * 5.0 / 9.0, 2 => v - 273.15, _ => v }
}

fn from_celsius(i: i64, c: f64) -> f64 {
    match i { 1 => c * 9.0 / 5.0 + 32.0, 2 => c + 273.15, _ => c }
}

fn convert(v: f64, a: i64, b: i64) -> f64 {
    if units.len == 0 { return 0.0; }
    if cat == C_TEMP { return from_celsius(b, to_celsius(a, v)); }
    v * units[a].factor / units[b].factor
}

fn other_value() -> f64 {
    let a = if active == 0 { sel_from[cat] } else { sel_to[cat] };
    let b = if active == 0 { sel_to[cat] } else { sel_from[cat] };
    convert(value, a, b)
}

fn show(out: u8[>..]&, v: f64) {
    if cat == C_CURRENCY {
        // Geld: zwei Nachkommastellen, kleine Beträge genauer.
        let a = abs(v);
        let r = if a >= 1.0 || a == 0.0 { round(v * 100.0) / 100.0 } else { nf::round_sig(v, 4) };
        if a >= 1.0 {
            var raw: u8[>..] = [];
            format_flt(raw, r, 2);
            nf::de_text(out, raw);
        } else {
            nf::format_num(out, r);
        }
        return;
    }
    nf::format_num(out, nf::round_sig(v, 12));
}

// --- Eingabe ------------------------------------------------------------------------------------

fn refresh() {
    var t: u8[..48] = [];
    t.append(entry);
    if t.len == 0 || t[t.len - 1] == '.' || t == "-" { t.push('0'); }
    let v, ok = parse_flt(t);
    value = if ok { v } else { 0.0 };
}

fn digit(d: u8) {
    if fresh { entry.resize(0); fresh = false; }
    var n = 0;
    for c in entry { if ascii::is_digit(c) { n++; } }
    if n >= 16 { return; }
    if entry == "0" { entry.resize(0); }
    if entry == "-0" { entry.resize(1); }
    entry.push(d);
    refresh();
}

fn decimal() {
    if fresh { entry.resize(0); fresh = false; }
    if find(entry, ".") >= 0 { return; }
    if entry.len == 0 { entry.push('0'); }
    entry.push('.');
    refresh();
}

fn backspace() {
    fresh = false;
    if entry.len > 0 { entry.resize(entry.len - 1); }
    if entry.len == 0 || entry == "-" { entry.resize(0); entry.push('0'); }
    refresh();
}

fn clear_entry() {
    entry.resize(0);
    entry.push('0');
    refresh();
}

fn negate() {
    if entry.len > 0 && entry[0] == '-' {
        var t: u8[..40] = [];
        t.append(entry[1..]);
        entry = t;
    } else if entry != "0" {
        var t: u8[..40] = [];
        t.push('-');
        t.append(entry);
        entry = t;
    }
    refresh();
}

// Den anderen Wert anklicken: der wird nun eingegeben, mit seinem Wert.
fn activate(i: i64) {
    if i == active { return; }
    let v = other_value();
    active = i;
    entry.resize(0);
    var t: u8[>..] = [];
    show(t, v);
    for c in t {
        if c == ',' { entry.push('.'); }
        else if c != '.' && entry.len < 39 { entry.push(c); }
    }
    if find(t, "e") >= 0 { entry.resize(0); format_flt_into(v); }
    fresh = true;
    refresh();
}

fn format_flt_into(v: f64) {
    var raw: u8[>..] = [];
    format_flt(raw, v, 6);
    entry.append(nf::trimmed(raw)[..min(raw.len, 39)]);
}

// --- Oberfläche -------------------------------------------------------------------------------

fn unit_combo(ctx: ui::Context, sel: i64&, w: f32) {
    if units.len == 0 { return; }
    ui::layout_row_static(ctx, 32.0, min(w - 16.0, 260.0) as! i64, 1);
    var label: u8[>..] = [];
    label.append("  ");
    if cat == C_CURRENCY { format(label, units[sel].name, " - ", units[sel].code); }
    else { label.append(units[sel].name); }
    if ui::combo_begin_label(ctx, label, float2 { min(w - 16.0, 260.0), 300.0 }) {
        ui::layout_row_dynamic(ctx, 30.0, 1);
        for x, i in units {
            var t: u8[>..] = [];
            t.append("  ");
            if cat == C_CURRENCY { format(t, x.name, " - ", x.code); } else { t.append(x.name); }
            if ui::combo_item_label(ctx, t, ui::TEXT_LEFT) {
                sel = i;
                refresh();
            }
        }
        ui::combo_end(ctx);
    }
}

fn value_line(ctx: ui::Context, i: i64, w: f32) {
    var t: u8[>..] = [];
    if cat == C_CURRENCY && units.len > 0 {
        let idx = if i == 0 { sel_from[cat] } else { sel_to[cat] };
        format(t, fx::symbol(units[idx].code), " ");
    }
    if i == active { nf::de_text(t, entry); } else { show(t, other_value()); }
    let font = if i == active { th::f_disp[1] } else { th::f_disp[1] };
    if kit::value_field(ctx, t, font, i == active, 56.0) { activate(i); }
}

fn k(ctx: ui::Context, label: const u8[:], kind: i64, enabled: bool = true) -> bool {
    th::key(ctx, label, kind, if kind == th::K_NUM { th::f_num } else { th::f_key }, enabled)
}

fn digits(ctx: ui::Context, a: u8, b: u8, c: u8) {
    var t: u8[1] = [a];
    if k(ctx, t, th::K_NUM) { digit(a); }
    t[0] = b;
    if k(ctx, t, th::K_NUM) { digit(b); }
    t[0] = c;
    if k(ctx, t, th::K_NUM) { digit(c); }
}

fn keypad(ctx: ui::Context, h: f32) {
    let rh = (h - 5.0 * 2.0) / 5.0;
    ui::layout_row_dynamic(ctx, rh, 3);
    ui::spacer(ctx);
    if k(ctx, "CE", th::K_OP) { clear_entry(); }
    if th::icon_key(ctx, 0xE750, th::K_OP) { backspace(); }
    ui::layout_row_dynamic(ctx, rh, 3);
    digits(ctx, '7', '8', '9');
    ui::layout_row_dynamic(ctx, rh, 3);
    digits(ctx, '4', '5', '6');
    ui::layout_row_dynamic(ctx, rh, 3);
    digits(ctx, '1', '2', '3');
    ui::layout_row_dynamic(ctx, rh, 3);
    // Vorzeichen nur, wo es negative Werte gibt.
    if cat == C_TEMP {
        if k(ctx, "+/-", th::K_NUM) { negate(); }
    } else {
        ui::spacer(ctx);
    }
    if k(ctx, "0", th::K_NUM) { digit('0'); }
    if k(ctx, ",", th::K_NUM) { decimal(); }
}

fn draw(ctx: ui::Context, w: f32, h: f32, used: f32) {
    if cat == C_CURRENCY {
        fx::poll();
        if fx::changed { fx::changed = false; reload_currency(); }
    }
    kit::gap(ctx, 6.0);
    if cat == C_CURRENCY && units.len == 0 {
        ui::layout_row_dynamic(ctx, 40.0, 1);
        th::text(ctx, str("  ", fx::status), th::f_text, th::pal.text_dim, ui::TEXT_LEFT);
        ui::layout_row_static(ctx, 32.0, 200, 1);
        if th::key(ctx, "Kurse aktualisieren", th::K_NUM, th::f_text, fx::state != fx::LOADING) {
            fx::request();
        }
        return;
    }
    value_line(ctx, 0, w);
    unit_combo(ctx, sel_from[cat], w);
    kit::gap(ctx, 10.0);
    value_line(ctx, 1, w);
    unit_combo(ctx, sel_to[cat], w);
    if cat == C_CURRENCY {
        kit::gap(ctx, 6.0);
        let a = units[sel_from[cat]];
        let b = units[sel_to[cat]];
        var line: u8[>..] = [];
        format(line, "  1 ", a.code, " = ");
        nf::format_num(line, nf::round_sig(a.factor / b.factor, 6));
        format(line, " ", b.code);
        ui::layout_row_dynamic(ctx, 20.0, 1);
        th::text(ctx, line, th::f_text, th::pal.text_dim, ui::TEXT_LEFT);
        ui::layout_row_dynamic(ctx, 20.0, 1);
        th::text(ctx, str("  ", fx::status), th::f_text, th::pal.text_dim, ui::TEXT_LEFT);
        ui::layout_row_static(ctx, 26.0, 150, 1);
        var link = th::s_flat;
        link.text_normal = th::pal.accent;
        link.text_hover = th::pal.accent;
        link.text_alignment = ui::TEXT_LEFT as u32;
        ui::style_push_font(ctx, th::f_text);
        if ui::button_label_styled(ctx, link, "  Kurse aktualisieren") && fx::state != fx::LOADING {
            fx::request();
        }
        ui::style_pop_font(ctx);
    }
    keypad(ctx, max(kit::remaining(ctx, h), 160.0));
}

fn on_char(c: u32) {
    if c >= '0' && c <= '9' { digit(c as! u8); return; }
    match c {
        ',', '.' => decimal(),
        '-' => if cat == C_TEMP { negate(); },
        _ => {},
    }
}

fn on_key(e: gfx::Event) {
    let name = gfx::key_name(e.scancode);
    if name == "Backspace" { backspace(); }
    else if name == "Escape" || name == "Delete" { clear_entry(); }
    else if name == "Tab" || name == "Up" || name == "Down" { activate(1 - active); }
    else if name == "F9" && cat == C_TEMP { negate(); }
}
