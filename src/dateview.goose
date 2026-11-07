// "Datumsberechnung": Abstand zweier Daten, oder Tage, Monate und Jahre
// zu einem Datum addieren bzw. davon abziehen.
import std;
import os;
import gfx;
import ui;
import src.numfmt;
import src.theme;
import src.kit;

namespace dv;

struct Date { y: i64, m: i64, d: i64 }

let MONTHS: const u8[:][12] = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
                               "August", "September", "Oktober", "November", "Dezember"];
let WEEKDAYS: const u8[:][7] = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag",
                                "Samstag", "Sonntag"];
let WD_SHORT: const u8[:][7] = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];

// Tage seit 1970-01-01 (Howard Hinnants Algorithmus).
fn days_from_civil(dt: Date) -> i64 {
    let y = if dt.m <= 2 { dt.y - 1 } else { dt.y };
    let era = div_euclid(y, 400);
    let yoe = y - era * 400;
    let mp = (dt.m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + dt.d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

fn civil_from_days(z0: i64) -> Date {
    let z = z0 + 719468;
    let era = div_euclid(z, 146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + (if m <= 2 { 1 } else { 0 });
    Date { y: y, m: m, d: d }
}

fn is_leap(y: i64) -> bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

fn month_len(y: i64, m: i64) -> i64 {
    match m {
        2 => if is_leap(y) { 29 } else { 28 },
        4, 6, 9, 11 => 30,
        _ => 31,
    }
}

// 0 = Montag
fn weekday(dt: Date) -> i64 { (days_from_civil(dt) + 3) % 7 }

fn today() -> Date { civil_from_days(floor_div(time() as! i64, 86400)) }

fn floor_div(a: i64, b: i64) -> i64 { div_euclid(a, b) }

fn add_months(dt: Date, months: i64) -> Date {
    let total = dt.y * 12 + (dt.m - 1) + months;
    let y = div_euclid(total, 12);
    let m = total % 12 + 1;
    Date { y: y, m: m, d: min(dt.d, month_len(y, m)) }
}

fn format_date(out: u8[>..]&, dt: Date) {
    format(out, dt.d, ". ", MONTHS[dt.m - 1], " ", dt.y);
}

fn format_long(out: u8[>..]&, dt: Date) {
    format(out, WEEKDAYS[weekday(dt)], ", ");
    format_date(out, dt);
}

fn less(a: Date, b: Date) -> bool { days_from_civil(a) < days_from_civil(b) }

// --- Zustand -------------------------------------------------------------------------------------

let MODE_DIFF = 0;
let MODE_ADD = 1;

var mode = MODE_DIFF;
var started = false;
var from: Date;
var to: Date;
var add_from: Date;
var subtract = false;
var years = 0;
var months = 0;
var days = 0;

var picker = 0;                 // welches Datum gerade gewählt wird: 1 von, 2 bis, 3 Startdatum
var view_y = 2026;
var view_m = 1;

fn init() {
    if started { return; }
    started = true;
    from = today();
    to = from;
    add_from = from;
}

fn plural(out: u8[>..]&, n: i64, one: const u8[:], many: const u8[:]) {
    if out.len > 0 { out.append(", "); }
    format(out, n, " ", if n == 1 { one } else { many });
}

// Abstand wie bei Windows: Jahre, Monate, Wochen, Tage.
fn difference(out: u8[>..]&, a0: Date, b0: Date) -> i64 {
    var a = a0;
    var b = b0;
    if less(b, a) { swap(a, b); }
    let total = days_from_civil(b) - days_from_civil(a);
    if total == 0 { return 0; }
    var y = b.y - a.y;
    while y > 0 && less(b, add_months(a, y * 12)) { y--; }
    let after_y = add_months(a, y * 12);
    var m = (b.y - after_y.y) * 12 + (b.m - after_y.m);
    while m > 0 && less(b, add_months(after_y, m)) { m--; }
    while !less(b, add_months(after_y, m + 1)) { m++; }
    let after_m = add_months(after_y, m);
    let rest = days_from_civil(b) - days_from_civil(after_m);
    if y > 0 { plural(out, y, "Jahr", "Jahre"); }
    if m > 0 { plural(out, m, "Monat", "Monate"); }
    if rest / 7 > 0 { plural(out, rest / 7, "Woche", "Wochen"); }
    if rest % 7 > 0 { plural(out, rest % 7, "Tag", "Tage"); }
    total
}

// --- Oberfläche ------------------------------------------------------------------------------

fn caption(ctx: ui::Context, s: const u8[:]) {
    ui::layout_row_dynamic(ctx, 24.0, 1);
    th::text(ctx, str("  ", s), th::f_text, th::pal.text_dim, ui::TEXT_LEFT);
}

// Ein Datumsfeld mit Kalendersymbol; ein Klick öffnet den Kalender.
fn date_button(ctx: ui::Context, which: i64, dt: Date) {
    ui::layout_row_static(ctx, 34.0, 220, 1);
    let b = ui::widget_bounds(ctx);
    var t: u8[>..] = [];
    t.append("  ");
    format_date(t, dt);
    var s = th::s_num;
    s.text_alignment = ui::TEXT_LEFT as u32;
    ui::style_push_font(ctx, th::f_text);
    if ui::button_label_styled(ctx, s, t) {
        picker = if picker == which { 0 } else { which };
        view_y = dt.y;
        view_m = dt.m;
    }
    ui::style_pop_font(ctx);
    let icon = th::icon_text(0xE787);
    kit::text_center(ctx, ui::rect(b.x + b.w - 32.0, b.y, 28.0, b.h), icon, th::f_icon, th::pal.text);
    if picker == which { calendar(ctx, b, which); }
}

fn calendar(ctx: ui::Context, b: ui::Rect, which: i64) {
    let win = ui::window_get_position(ctx);
    let r = ui::rect(b.x - win.x, b.y - win.y + b.h + 2.0, 300.0, 320.0);
    if !ui::popup_begin(ctx, ui::POPUP_STATIC, "kalender", ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_BORDER, r) {
        picker = 0;
        return;
    }
    ui::layout_row_begin(ctx, ui::STATIC, 34.0, 3);
    ui::layout_row_push(ctx, 200.0);
    th::text(ctx, str("  ", MONTHS[view_m - 1], " ", view_y), th::f_small, th::pal.text, ui::TEXT_LEFT);
    ui::layout_row_push(ctx, 40.0);
    if th::icon_key(ctx, 0xE70E, th::K_FLAT) {
        view_m--;
        if view_m < 1 { view_m = 12; view_y--; }
    }
    ui::layout_row_push(ctx, 40.0);
    if th::icon_key(ctx, 0xE70D, th::K_FLAT) {
        view_m++;
        if view_m > 12 { view_m = 1; view_y++; }
    }
    ui::layout_row_end(ctx);
    ui::layout_row_dynamic(ctx, 26.0, 7);
    for i in 7 { th::text(ctx, WD_SHORT[i], th::f_text, th::pal.text, ui::TEXT_CENTERED); }
    let first = Date { y: view_y, m: view_m, d: 1 };
    let start = days_from_civil(first) - weekday(first);
    let now = days_from_civil(today());
    let sel = days_from_civil(if which == 1 { from } else if which == 2 { to } else { add_from });
    var picked = -1;
    for row in 6 {
        ui::layout_row_dynamic(ctx, 36.0, 7);
        for col in 7 {
            let day = start + row * 7 + col;
            let dt = civil_from_days(day);
            let st, cell = ui::widget(ctx);
            if st == ui::WIDGET_INVALID { continue; }
            let hot = st == ui::WIDGET_VALID && kit::hovered(ctx, cell);
            let c = ui::rect(cell.x + (cell.w - 32.0) * 0.5, cell.y + 2.0, 32.0, 32.0);
            if day == now { ui::fill_rect(ctx, c, 16.0, th::pal.accent); }
            else if hot { ui::fill_rect(ctx, c, 16.0, th::pal.flat_hover); }
            if day == sel { ui::stroke_rect(ctx, c, 16.0, 1.5, th::pal.accent); }
            let color = if day == now { th::pal.accent_text } else if dt.m == view_m { th::pal.text } else { th::pal.text_off };
            kit::text_center(ctx, cell, str(dt.d), th::f_text, color);
            if hot && kit::clicked(ctx, cell) { picked = day; }
        }
    }
    if picked >= 0 {
        let dt = civil_from_days(picked);
        if which == 1 { from = dt; } else if which == 2 { to = dt; } else { add_from = dt; }
        picker = 0;
        ui::popup_close(ctx);
    }
    ui::popup_end(ctx);
}

// Eine Auswahlliste 0 … 999 wie bei Windows.
fn number_combo(ctx: ui::Context, v: i64&) {
    if ui::combo_begin_label(ctx, str("  ", v), float2 { 90.0, 240.0 }) {
        ui::layout_row_dynamic(ctx, 26.0, 1);
        for i in 1000 {
            if ui::combo_item_label(ctx, str(i), ui::TEXT_LEFT) { v = i; }
        }
        ui::combo_end(ctx);
    }
}

fn draw(ctx: ui::Context, w: f32, h: f32, used: f32) {
    init();
    kit::gap(ctx, 4.0);
    ui::layout_row_static(ctx, 34.0, min(300.0, w - 16.0) as! i64, 1);
    let names: const u8[:][2] = ["  Differenz zwischen Datumsangaben", "  Tage addieren oder subtrahieren"];
    if ui::combo_begin_label(ctx, names[mode], float2 { 300.0, 90.0 }) {
        ui::layout_row_dynamic(ctx, 32.0, 1);
        if ui::combo_item_label(ctx, names[0], ui::TEXT_LEFT) { mode = MODE_DIFF; picker = 0; }
        if ui::combo_item_label(ctx, names[1], ui::TEXT_LEFT) { mode = MODE_ADD; picker = 0; }
        ui::combo_end(ctx);
    }
    kit::gap(ctx, 10.0);
    if mode == MODE_DIFF {
        caption(ctx, "Von");
        date_button(ctx, 1, from);
        kit::gap(ctx, 6.0);
        caption(ctx, "Bis");
        date_button(ctx, 2, to);
        kit::gap(ctx, 14.0);
        caption(ctx, "Differenz");
        var parts: u8[>..] = [];
        let total = difference(parts, from, to);
        ui::layout_row_dynamic(ctx, 36.0, 1);
        if total == 0 {
            th::text(ctx, "  Gleiche Datumsangaben", th::f_title, th::pal.text, ui::TEXT_LEFT);
        } else {
            th::text(ctx, str("  ", parts), th::f_title, th::pal.text, ui::TEXT_LEFT);
            var n: u8[>..] = [];
            n.append("  ");
            nf::format_int_de(n, total);
            n.append(if total == 1 { " Tag" } else { " Tage" });
            ui::layout_row_dynamic(ctx, 22.0, 1);
            th::text(ctx, n, th::f_text, th::pal.text_dim, ui::TEXT_LEFT);
        }
    } else {
        caption(ctx, "Von");
        date_button(ctx, 3, add_from);
        kit::gap(ctx, 8.0);
        ui::layout_row_static(ctx, 28.0, 140, 2);
        if ui::option_label(ctx, "Hinzufügen", !subtract) { subtract = false; }
        if ui::option_label(ctx, "Subtrahieren", subtract) { subtract = true; }
        kit::gap(ctx, 8.0);
        ui::layout_row_static(ctx, 22.0, 96, 3);
        th::text(ctx, "  Jahre", th::f_text, th::pal.text_dim, ui::TEXT_LEFT);
        th::text(ctx, "  Monate", th::f_text, th::pal.text_dim, ui::TEXT_LEFT);
        th::text(ctx, "  Tage", th::f_text, th::pal.text_dim, ui::TEXT_LEFT);
        ui::layout_row_static(ctx, 32.0, 90, 3);
        number_combo(ctx, years);
        number_combo(ctx, months);
        number_combo(ctx, days);
        kit::gap(ctx, 14.0);
        caption(ctx, "Datum");
        let sign = if subtract { -1 } else { 1 };
        let r = civil_from_days(days_from_civil(add_months(add_from, sign * (years * 12 + months))) + sign * days);
        var t: u8[>..] = [];
        t.append("  ");
        format_long(t, r);
        ui::layout_row_dynamic(ctx, 36.0, 1);
        th::text(ctx, t, th::f_title, th::pal.text, ui::TEXT_LEFT);
    }
}

fn on_char(c: u32) {}
fn on_key(e: gfx::Event) {
    if gfx::key_name(e.scancode) == "Escape" { picker = 0; }
}
fn enter(i: i64) {}
