// Rechner: der Windows-11-Rechner, nachgebaut in Goose.
//
//   goose rechner.goose                     starten
//   goose build rechner.goose               rechner.exe bauen
//
// Zum Testen: --mode N, --size BxH, --keys "12+3=", --frames N, --shot datei.png
import std;
import math;
import os;
import gfx;
import ui;
import src.numfmt;
import src.calc;
import src.theme;
import src.kit;
import src.calcview;
import src.progview;
import src.dateview;
import src.convview;

let M_STANDARD = 0;
let M_SCI = 1;
let M_PROG = 2;
let M_DATE = 3;
let M_CURRENCY = 4;
let M_VOLUME = 5;
let M_LENGTH = 6;
let M_WEIGHT = 7;
let M_TEMP = 8;
let M_ENERGY = 9;
let M_AREA = 10;
let M_SPEED = 11;
let M_TIME = 12;
let M_POWER = 13;
let M_DATA = 14;
let M_PRESSURE = 15;
let M_ANGLE = 16;
let M_SETTINGS = 17;
let MODE_COUNT = 18;

let MODE_NAMES: const u8[:][18] = [
    "Standard", "Wissenschaftlich", "Programmierer", "Datumsberechnung",
    "Währung", "Volumen", "Länge", "Gewicht und Masse", "Temperatur", "Energie",
    "Fläche", "Geschwindigkeit", "Zeit", "Leistung", "Daten", "Druck", "Winkel",
    "Einstellungen",
];

// Die Symbole aus NavCategory.cs, in der Schrift des Windows-Rechners.
let MODE_ICONS: u32[18] = [
    0xE8EF, 0xF196, 0xECCE, 0xE787,
    0xEB0D, 0xF1AA, 0xECC6, 0xF4C1, 0xE7A3, 0xECAD,
    0xE809, 0xEADA, 0xE917, 0xE945, 0xF20F, 0xEC4A, 0xF515,
    0xE713,
];

var mode = M_STANDARD;
var nav_open = false;
var nav_fresh = false;           // erst in diesem Bild geöffnet
var nav_scroll = 0.0;
var dpi: f32 = 1.0;

fn is_calc(m: i64) -> bool { m == M_STANDARD || m == M_SCI }
fn is_converter(m: i64) -> bool { m >= M_CURRENCY && m <= M_ANGLE }

fn set_mode(m: i64) {
    if m == mode { return; }
    if is_calc(m) && !is_calc(mode) { calc::clear_all(); }
    if is_calc(m) && is_calc(mode) { calc::clear_all(); }
    mode = m;
    cv::flyout = 0;
    cv::trig_open = false;
    cv::func_open = false;
    if is_converter(m) { conv::enter(m - M_CURRENCY); }
}

// --- Kopfzeile -------------------------------------------------------------------------

fn top_bar(ctx: ui::Context, w: f32, history_button: bool) {
    let title = MODE_NAMES[mode];
    let tw = ui::text_width(th::f_title, title) + 16.0;
    // HamburgerHeight = 48 in App.xaml
    ui::layout_row_dynamic(ctx, 4.0, 1);
    ui::spacer(ctx);
    ui::layout_row_begin(ctx, ui::STATIC, 40.0, 4);
    ui::layout_row_push(ctx, 46.0);
    if th::icon_key(ctx, 0xE700, th::K_FLAT) {
        nav_open = !nav_open;
        // Derselbe Klick darf das Menü nicht gleich wieder schließen: Nuklear
        // löst beim Drücken aus, und der Knopf im Menü liegt genau hier.
        nav_fresh = nav_open;
    }
    ui::layout_row_push(ctx, tw);
    th::text(ctx, title, th::f_title, th::pal.text, ui::TEXT_LEFT);
    let rest = w - 6.0 - 46.0 - tw - 46.0 - 6.0 - 6.0;
    ui::layout_row_push(ctx, max(rest, 0.0));
    ui::spacer(ctx);
    ui::layout_row_push(ctx, 46.0);
    if history_button {
        let sel = cv::flyout == cv::PANEL_HISTORY;
        if th::key(ctx, "", if sel { th::K_FLAT_SEL } else { th::K_FLAT }, th::f_calc) {
            cv::flyout = if sel { 0 } else { cv::PANEL_HISTORY };
        }
    } else {
        ui::spacer(ctx);
    }
    ui::layout_row_end(ctx);
}

// --- Navigation --------------------------------------------------------------------------

// Wie bei Windows 11: ein schwebendes Panel mit runden Ecken über dem
// Rechner, ohne Abdunkelung; ein Klick daneben schließt es.
let NAV_X = 6.0;
let NAV_W = 256.0;

fn nav(ctx: ui::Context, w: f32, h: f32) {
    let fresh = nav_fresh;
    nav_fresh = false;
    let saved = ui::style(ctx);
    var st = saved;
    st.window.fixed_background = ui::style_item_hide();
    st.window.padding = float2 { NAV_X + 4.0, 4.0 };
    st.window.spacing = float2 { 0.0, 0.0 };
    st.window.group_padding = float2 { 0.0, 0.0 };
    st.window.scrollbar_size = float2 { 2.0, 2.0 };
    st.scrollv.cursor_normal = ui::style_item_color(th::pal.text_off);
    ui::set_style(ctx, st);
    let pw = min(NAV_W, w - NAV_X * 2.0);
    let inner = pw - 8.0;
    if ui::begin(ctx, "nav", ui::rect(0, 0, w, h), ui::WINDOW_NO_SCROLLBAR) {
        let panel = ui::rect(NAV_X, 2.0, pw, h - 2.0 - NAV_X);
        ui::fill_rect(ctx, panel, 8.0, th::pal.pane);
        ui::stroke_rect(ctx, panel, 8.0, 1.0, th::pal.line);
        ui::layout_row_static(ctx, 4.0, 1, 1);
        ui::spacer(ctx);
        ui::layout_row_begin(ctx, ui::STATIC, 32.0, 1);
        ui::layout_row_push(ctx, 40.0);
        if th::key(ctx, th::icon_text(0xE700), th::K_NAV_SEL, th::f_icon) && !fresh { nav_open = false; }
        ui::layout_row_end(ctx);
        let list_h = h - NAV_X - 4.0 - 32.0 - 10.0 - 1.0 - 44.0 - 4.0;
        ui::layout_row_static(ctx, list_h, inner as! i64, 1);
        if ui::group_begin(ctx, "navliste", 0) {
            header(ctx, "Rechner", inner);
            for m in M_STANDARD..M_CURRENCY { nav_row(ctx, m, inner); }
            header(ctx, "Konverter", inner);
            for m in M_CURRENCY..M_SETTINGS { nav_row(ctx, m, inner); }
            ui::group_end(ctx);
        }
        ui::layout_row_static(ctx, 5.0, 1, 1);
        ui::spacer(ctx);
        // Trennlinie über "Einstellungen", über die ganze Breite des Panels.
        ui::layout_row_static(ctx, 1.0, inner as! i64, 1);
        let st1, r1 = ui::widget(ctx);
        if st1 != ui::WIDGET_INVALID {
            ui::fill_rect(ctx, ui::rect(NAV_X + 1.0, r1.y, pw - 2.0, 1.0), 0.0, th::pal.line);
        }
        ui::layout_row_static(ctx, 4.0, 1, 1);
        ui::spacer(ctx);
        nav_row(ctx, M_SETTINGS, inner);
    }
    ui::end(ctx);
    ui::set_style(ctx, saved);
    let m = gfx::mouse_pos();
    let inside = m.x / dpi >= NAV_X && m.x / dpi <= NAV_X + pw;
    if !fresh && gfx::mouse_pressed(gfx::MOUSE_LEFT) && !inside { nav_open = false; }
}

fn header(ctx: ui::Context, s: const u8[:], inner: f32) {
    ui::layout_row_static(ctx, 40.0, inner as! i64, 1);
    let st, r = ui::widget(ctx);
    if st != ui::WIDGET_INVALID {
        kit::text_left(ctx, ui::rect(r.x + 12.0, r.y + 4.0, r.w - 12.0, r.h - 4.0), s, th::f_head, th::pal.text);
    }
}

fn nav_row(ctx: ui::Context, m: i64, inner: f32) {
    ui::layout_row_static(ctx, 40.0, inner as! i64, 1);
    if kit::nav_item(ctx, MODE_ICONS[m], MODE_NAMES[m], m == mode) {
        set_mode(m);
        nav_open = false;
    }
}

// --- Einstellungen ---------------------------------------------------------------------------

fn settings(ctx: ui::Context, w: f32) {
    kit::gap(ctx, 12.0);
    ui::layout_row_dynamic(ctx, 26.0, 1);
    th::text(ctx, "  Darstellung", th::f_small, th::pal.text, ui::TEXT_LEFT);
    ui::layout_row_dynamic(ctx, 22.0, 1);
    th::text(ctx, "  App-Design", th::f_text, th::pal.text, ui::TEXT_LEFT);
    ui::layout_row_dynamic(ctx, 28.0, 1);
    if ui::option_label(ctx, "Hell", !th::dark) && th::dark { th::dark = false; th::apply(ctx); }
    ui::layout_row_dynamic(ctx, 28.0, 1);
    if ui::option_label(ctx, "Dunkel", th::dark) && !th::dark { th::dark = true; th::apply(ctx); }
    kit::gap(ctx, 18.0);
    ui::layout_row_dynamic(ctx, 26.0, 1);
    th::text(ctx, "  Info", th::f_small, th::pal.text, ui::TEXT_LEFT);
    ui::layout_row_dynamic(ctx, 20.0, 1);
    th::text(ctx, "  Rechner, geschrieben in Goose", th::f_text, th::pal.text, ui::TEXT_LEFT);
    ui::layout_row_dynamic(ctx, 20.0, 1);
    th::text(ctx, "  Wechselkurse: frankfurter.dev", th::f_text, th::pal.text_dim, ui::TEXT_LEFT);
    ui::layout_row_dynamic(ctx, 20.0, 1);
    th::text(ctx, "  (Referenzkurse der EZB)", th::f_text, th::pal.text_dim, ui::TEXT_LEFT);
    ui::layout_row_dynamic(ctx, 20.0, 1);
    th::text(ctx, "  Design und Symbole: microsoft/calculator (MIT)", th::f_text, th::pal.text_dim,
             ui::TEXT_LEFT);
}

// --- Tastatur ----------------------------------------------------------------------------------

fn handle_input(ctx: ui::Context) {
    for e in gfx::events() {
        if e.kind == gfx::EVENT_TEXT {
            if nav_open { continue; }
            if is_calc(mode) { cv::on_char(e.codepoint, mode == M_SCI); }
            else if mode == M_PROG { pv::on_char(e.codepoint); }
            else if mode == M_DATE { dv::on_char(e.codepoint); }
            else if is_converter(mode) { conv::on_char(e.codepoint); }
        } else if e.kind == gfx::EVENT_KEY && e.down {
            let name = gfx::key_name(e.scancode);
            if name == "Escape" && nav_open { nav_open = false; continue; }
            if (e.mods & gfx::MOD_ALT) != 0 {
                // Alt+1 … Alt+5 wie bei Windows: Standard, Wissenschaftlich, …
                if name == "1" { set_mode(M_STANDARD); }
                else if name == "2" { set_mode(M_SCI); }
                else if name == "3" { set_mode(M_PROG); }
                else if name == "4" { set_mode(M_PROG); }
                else if name == "5" { set_mode(M_DATE); }
                continue;
            }
            if nav_open { continue; }
            if is_calc(mode) { cv::on_key(e, mode == M_SCI); }
            else if mode == M_PROG { pv::on_key(e); }
            else if mode == M_DATE { dv::on_key(e); }
            else if is_converter(mode) { conv::on_key(e); }
        }
    }
}

fn scripted(keys: const u8[:]) {
    for c in keys {
        if c == 'E' && is_calc(mode) { calc::equals(); continue; }
        if c == 'B' { calc::backspace(); continue; }
        if is_calc(mode) { cv::on_char(c, mode == M_SCI); }
        else if mode == M_PROG { pv::on_char(c); }
        else if mode == M_DATE { dv::on_char(c); }
        else if is_converter(mode) { conv::on_char(c); }
    }
}

// --- main ----------------------------------------------------------------------------------------

fn main() {
    var frames = -1;
    var shot: u8[>..] = [];
    var keys: u8[>..] = [];
    var clicks: u8[>..] = [];       // "x,y;x,y": je ein Klick ab Bild 2, alle 3 Bilder
    var win_w = 336;  // wie das Windows-Fenster ohne Titelleiste
    var win_h = 509;
    let argv = args();
    var i = 1;
    while i + 1 < argv.len {
        let a = argv[i];
        let v = argv[i + 1];
        if a == "--frames" { let n, ok = parse_int(v); if ok { frames = n; } }
        else if a == "--shot" { shot.append(v); }
        else if a == "--keys" { keys.append(v); }
        else if a == "--mode" { let n, ok = parse_int(v); if ok { mode = clamp(n, 0, MODE_COUNT - 1); } }
        else if a == "--nav" { nav_open = v == "1"; }
        else if a == "--click" { clicks.append(v); }
        else if a == "--light" { th::dark = v != "1"; }
        else if a == "--open" {
            // Zum Testen: ein Ausklappmenü gleich offen zeigen.
            if v == "trig" { cv::trig_open = true; }
            else if v == "func" { cv::func_open = true; }
            else if v == "hist" { cv::flyout = cv::PANEL_HISTORY; }
            else if v == "mem" { cv::flyout = cv::PANEL_MEMORY; }
            else if v == "bitweise" { pv::bitwise_open = true; }
            else if v == "schieben" { pv::shift_open = true; }
            else if v == "bits" { pv::bit_pad = true; }
            else if v == "kalender" { dv::picker = 1; dv::view_y = 2026; dv::view_m = 11; }
            else if v == "addieren" { dv::mode = dv::MODE_ADD; }
        }
        else if a == "--size" {
            let ws, hs, found = split_once(v, 'x');
            if found {
                let pw, okw = parse_int(ws);
                let ph, okh = parse_int(hs);
                if okw && okh { win_w = pw; win_h = ph; }
            }
        }
        i += 2;
    }

    guard gfx::open("Rechner", win_w, win_h, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }
    defer gfx::close();
    let sz0 = gfx::screen_size();
    dpi = max(sz0.x as f32 / win_w, 1.0);
    kit::scale = dpi;
    if !th::load_fonts(dpi) {
        write_stderr(str("ui: ", ui::error(), "\n"));
        return;
    }
    let ctx = ui::create_context(th::f_text);
    guard ctx.id != 0 else {
        write_stderr(str("ui: ", ui::error(), "\n"));
        return;
    }
    defer ui::destroy(ctx);
    ui::set_scale(ctx, dpi);
    th::apply(ctx);
    if is_converter(mode) { conv::enter(mode - M_CURRENCY); }

    var drawn = 0;
    while gfx::frame() {
        ui::input_from_gfx(ctx);
        handle_input(ctx);
        if drawn == 1 && keys.len > 0 { scripted(keys); }
        if clicks.len > 0 && drawn >= 2 && (drawn - 2) % 3 < 2 {
            let n = (drawn - 2) / 3;
            let parts = split(clicks, ';');
            if n < parts.len {
                let xs, ys, found = split_once(parts[n], ',');
                let x, okx = parse_int(xs);
                let y, oky = parse_int(ys);
                if found && okx && oky {
                    gfx::inject_mouse(x * dpi, y * dpi, gfx::MOUSE_LEFT, (drawn - 2) % 3 == 0);
                }
            }
        }

        let sz = gfx::screen_size();
        let w = sz.x / dpi;
        let h = sz.y / dpi;
        // DockVisible in Calculator.xaml: ab 560 px Verlauf/Speicher daneben,
        // Spalten im Verhältnis 320 : 240.
        let wide = is_calc(mode) && w >= 560.0;
        let main_w = if wide { floor(w * 320.0 / 560.0) } else { w };
        if !wide && cv::flyout == 0 {}

        if ui::begin(ctx, "main", ui::rect(0, 0, main_w, h), ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_BACKGROUND) {
            top_bar(ctx, main_w, is_calc(mode) && !wide);
            let used = 48.0;
            if is_calc(mode) { cv::draw(ctx, main_w, h, used, !wide, mode == M_SCI); }
            else if mode == M_PROG { pv::draw(ctx, main_w, h, used); }
            else if mode == M_DATE { dv::draw(ctx, main_w, h, used); }
            else if is_converter(mode) { conv::draw(ctx, main_w, h, used); }
            else { settings(ctx, main_w); }
        }
        ui::end(ctx);
        if wide {
            if cv::flyout != 0 { cv::flyout = 0; }
            if ui::begin(ctx, "seite", ui::rect(main_w, 0, w - main_w, h), ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_BACKGROUND) {
                cv::side_panel(ctx, h);
            }
            ui::end(ctx);
        }
        if nav_open { nav(ctx, w, h); }

        let bg = th::pal.bg;
        gfx::begin_screen(float4 { bg.r / 255.0, bg.g / 255.0, bg.b / 255.0, 1.0 });
        gfx::end_pass();
        ui::render(ctx);
        drawn++;
        if drawn == frames { break; }
    }
    if shot.len > 0 { gfx::screenshot(shot); }
}
