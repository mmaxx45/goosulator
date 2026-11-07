// Farben, Schriften und Tasten im Stil des Windows-11-Rechners.
import std;
import os;
import gfx;
import ui;

namespace th;

struct Palette {
    bg: ui::Color,
    pane: ui::Color,            // Navigationsleiste, Ausklappmenüs
    num: ui::Color, num_hover: ui::Color, num_press: ui::Color,
    op: ui::Color, op_hover: ui::Color, op_press: ui::Color,
    accent: ui::Color, accent_hover: ui::Color, accent_press: ui::Color, accent_text: ui::Color,
    text: ui::Color, text_dim: ui::Color, text_off: ui::Color,
    flat_hover: ui::Color, flat_press: ui::Color,
    line: ui::Color,
    bar: ui::Color,             // Auswahlbalken in der Navigation
}

fn dark_palette() -> Palette {
    Palette {
        bg: ui::rgb(0x20, 0x20, 0x20),
        pane: ui::rgb(0x2b, 0x2b, 0x2b),
        num: ui::rgb(0x3b, 0x3b, 0x3b), num_hover: ui::rgb(0x32, 0x32, 0x32),
        num_press: ui::rgb(0x28, 0x28, 0x28),
        op: ui::rgb(0x32, 0x32, 0x32), op_hover: ui::rgb(0x3b, 0x3b, 0x3b),
        op_press: ui::rgb(0x28, 0x28, 0x28),
        accent: ui::rgb(0x4c, 0xc2, 0xff), accent_hover: ui::rgb(0x47, 0xb1, 0xe8),
        accent_press: ui::rgb(0x42, 0xa1, 0xd2), accent_text: ui::rgb(0, 0, 0),
        text: ui::rgb(0xff, 0xff, 0xff), text_dim: ui::rgb(0xa8, 0xa8, 0xa8),
        text_off: ui::rgb(0x6e, 0x6e, 0x6e),
        flat_hover: ui::rgb(0x2d, 0x2d, 0x2d), flat_press: ui::rgb(0x29, 0x29, 0x29),
        line: ui::rgb(0x3a, 0x3a, 0x3a),
        bar: ui::rgb(0x4c, 0xc2, 0xff),
    }
}

fn light_palette() -> Palette {
    Palette {
        bg: ui::rgb(0xf3, 0xf3, 0xf3),
        pane: ui::rgb(0xf9, 0xf9, 0xf9),
        num: ui::rgb(0xff, 0xff, 0xff), num_hover: ui::rgb(0xf6, 0xf6, 0xf6),
        num_press: ui::rgb(0xf0, 0xf0, 0xf0),
        op: ui::rgb(0xf9, 0xf9, 0xf9), op_hover: ui::rgb(0xff, 0xff, 0xff),
        op_press: ui::rgb(0xf0, 0xf0, 0xf0),
        accent: ui::rgb(0x00, 0x5f, 0xb8), accent_hover: ui::rgb(0x19, 0x6e, 0xbf),
        accent_press: ui::rgb(0x31, 0x7d, 0xc6), accent_text: ui::rgb(0xff, 0xff, 0xff),
        text: ui::rgb(0x1a, 0x1a, 0x1a), text_dim: ui::rgb(0x60, 0x60, 0x60),
        text_off: ui::rgb(0xa0, 0xa0, 0xa0),
        flat_hover: ui::rgb(0xe9, 0xe9, 0xe9), flat_press: ui::rgb(0xed, 0xed, 0xed),
        line: ui::rgb(0xe0, 0xe0, 0xe0),
        bar: ui::rgb(0x00, 0x5f, 0xb8),
    }
}

var dark = true;
var pal: Palette = dark_palette();

// Schriften: alle in einem Atlas, damit ein Kontext sie alle zeichnen kann.
var atlas: ui::FontAtlas;
var f_text: ui::Font;           // 14: Beschriftungen, Listen
var f_small: ui::Font;          // 12: Überschriften der Navigation
var f_expr: ui::Font;           // 15: Rechenweg
var f_key: ui::Font;            // 17: Funktionstasten
var f_op: ui::Font;             // 24: ÷ × − + =
var f_num: ui::Font;            // 20 halbfett: Ziffern
var f_title: ui::Font;          // 20 halbfett: "Standard"
var f_big: ui::Font;            // 28 halbfett: Werte im Konverter
var f_sym: ui::Font;            // 17 Segoe UI Symbol: ⌊x⌋, ≪
var f_icon: ui::Font;           // 16 Segoe Fluent Icons
var f_icon_s: ui::Font;         // 12
let DISP_SIZES: f32[7] = [46.0, 40.0, 34.0, 30.0, 26.0, 22.0, 18.0];
var f_disp: ui::Font[7];

// Die Zeichen, die der Rechner braucht: Latin-1, hoch- und tiefgestellte
// Ziffern und Buchstaben, Pfeile, mathematische Zeichen.
let TEXT_RANGES: u32[26] = [0x20, 0xFF, 0x100, 0x17F, 0x2B0, 0x2FF, 0x3C0, 0x3C0, 0x400, 0x44F,
                            0xE3F, 0xE3F, 0x1D00, 0x1D7F, 0x20A0, 0x20CF,
                            0x2010, 0x2027, 0x2070, 0x209F, 0x2190, 0x2193,
                            0x2200, 0x22FF, 0x2300, 0x23FF];
let ICON_RANGES: u32[4] = [0xE700, 0xE9FF, 0xEA00, 0xF0FF];

fn font_path(name: const u8[:]) -> u8[>..] {
    var windir: u8[>..] = [];
    if !env("WINDIR", windir) { windir.append("C:\\Windows"); }
    str(windir, "\\Fonts\\", name)
}

fn add(path: const u8[:], size: f32, ranges: const u32[:]) -> ui::Font {
    if file_exists(path) {
        let cfg = ui::FontConfig { oversample_h: 2, fallback_glyph: ranges[0], .. };
        let f = ui::add_font_from_file(atlas, path, size, cfg, ranges);
        if f.id != 0 { return f; }
    }
    ui::add_default_font(atlas, size)
}

fn load_fonts(scale: f32) -> bool {
    atlas = ui::create_font_atlas();
    let regular = font_path("segoeui.ttf");
    let semibold = font_path("seguisb.ttf");
    let symbol = font_path("seguisym.ttf");
    var icons = font_path("SegoeIcons.ttf");
    if !file_exists(icons) { icons = font_path("segmdl2.ttf"); }
    f_text = add(regular, 14.0, TEXT_RANGES);
    f_small = add(semibold, 12.0, TEXT_RANGES);
    f_expr = add(regular, 15.0, TEXT_RANGES);
    f_key = add(regular, 17.0, TEXT_RANGES);
    f_op = add(regular, 24.0, TEXT_RANGES);
    f_num = add(semibold, 20.0, TEXT_RANGES);
    f_title = add(semibold, 20.0, TEXT_RANGES);
    f_big = add(semibold, 28.0, TEXT_RANGES);
    f_sym = add(symbol, 17.0, TEXT_RANGES);
    f_icon = add(icons, 16.0, ICON_RANGES);
    f_icon_s = add(icons, 12.0, ICON_RANGES);
    for i in DISP_SIZES.len { f_disp[i] = add(semibold, DISP_SIZES[i], TEXT_RANGES); }
    ui::bake(atlas, scale)
}

// --- Tastenstile -------------------------------------------------------------------

var s_num: ui::StyleButton;
var s_op: ui::StyleButton;
var s_eq: ui::StyleButton;
var s_flat: ui::StyleButton;
var s_flat_sel: ui::StyleButton;
var s_nav: ui::StyleButton;
var s_nav_sel: ui::StyleButton;
var s_tab: ui::StyleButton;

fn button(base: ui::StyleButton, n: ui::Color, h: ui::Color, a: ui::Color, txt: ui::Color,
          txt_press: ui::Color) -> ui::StyleButton {
    var s = base;
    s.normal = ui::style_item_color(n);
    s.hover = ui::style_item_color(h);
    s.active = ui::style_item_color(a);
    s.border_color = n;
    s.border = 0.0;
    s.rounding = 4.0;
    s.text_background = n;
    s.text_normal = txt;
    s.text_hover = txt;
    s.text_active = txt_press;
    s.padding = float2 { 2.0, 2.0 };
    s.disabled_factor = 0.45;
    s
}

fn apply(ctx: ui::Context) {
    pal = if dark { dark_palette() } else { light_palette() };
    ui::style_default(ctx);
    var st = ui::style(ctx);
    let none = ui::rgba(0, 0, 0, 0);
    st.text.color = pal.text;
    st.window.fixed_background = ui::style_item_color(pal.bg);
    st.window.background = pal.bg;
    st.window.border = 0.0;
    st.window.padding = float2 { 4.0, 2.0 };
    st.window.spacing = float2 { 2.0, 2.0 };
    st.window.group_padding = float2 { 0.0, 0.0 };
    st.window.popup_padding = float2 { 4.0, 4.0 };
    st.window.popup_border = 1.0;
    st.window.popup_border_color = pal.line;
    st.window.group_border = 0.0;
    st.window.scrollbar_size = float2 { 6.0, 6.0 };
    st.window.rounding = 0.0;
    st.window.min_row_height_padding = 0.0;
    st.scrollv.normal = ui::style_item_color(none);
    st.scrollv.hover = ui::style_item_color(none);
    st.scrollv.active = ui::style_item_color(none);
    st.scrollv.cursor_normal = ui::style_item_color(pal.text_off);
    st.scrollv.cursor_hover = ui::style_item_color(pal.text_dim);
    st.scrollv.cursor_active = ui::style_item_color(pal.text_dim);
    st.scrollv.border = 0.0;
    st.scrollv.rounding = 3.0;
    st.scrollv.rounding_cursor = 3.0;
    st.button = button(st.button, pal.op, pal.op_hover, pal.op_press, pal.text, pal.text_dim);
    st.contextual_button = button(st.contextual_button, pal.pane, pal.flat_hover, pal.flat_press,
                                  pal.text, pal.text_dim);
    st.menu_button = st.contextual_button;
    st.combo.normal = ui::style_item_color(pal.num);
    st.combo.hover = ui::style_item_color(pal.num_hover);
    st.combo.active = ui::style_item_color(pal.num_press);
    st.combo.border_color = pal.line;
    st.combo.label_normal = pal.text;
    st.combo.label_hover = pal.text;
    st.combo.label_active = pal.text;
    st.combo.symbol_normal = pal.text;
    st.combo.symbol_hover = pal.text;
    st.combo.symbol_active = pal.text;
    st.combo.rounding = 4.0;
    st.combo.border = 0.0;
    st.combo.sym_normal = ui::SYMBOL_CHEVRON_DOWN;
    st.combo.sym_hover = ui::SYMBOL_CHEVRON_DOWN;
    st.combo.sym_active = ui::SYMBOL_CHEVRON_DOWN;
    st.combo.button = button(st.combo.button, pal.num, pal.num, pal.num, pal.text_dim, pal.text_dim);
    st.combo.button_padding = float2 { 10.0, 11.0 };
    st.combo.content_padding = float2 { 4.0, 4.0 };
    st.window.combo_border_color = pal.line;
    st.window.combo_padding = float2 { 4.0, 4.0 };
    st.selectable.normal = ui::style_item_color(none);
    st.selectable.hover = ui::style_item_color(pal.flat_hover);
    st.selectable.pressed = ui::style_item_color(pal.flat_press);
    st.selectable.normal_active = ui::style_item_color(pal.flat_hover);
    st.selectable.hover_active = ui::style_item_color(pal.flat_hover);
    st.selectable.pressed_active = ui::style_item_color(pal.flat_press);
    st.selectable.text_normal = pal.text;
    st.selectable.text_hover = pal.text;
    st.selectable.text_pressed = pal.text;
    st.selectable.text_normal_active = pal.text;
    st.selectable.text_hover_active = pal.text;
    st.selectable.text_pressed_active = pal.text;
    st.selectable.rounding = 4.0;
    st.option.normal = ui::style_item_color(pal.num);
    st.option.hover = ui::style_item_color(pal.num_hover);
    st.option.active = ui::style_item_color(pal.num);
    st.option.cursor_normal = ui::style_item_color(pal.accent);
    st.option.cursor_hover = ui::style_item_color(pal.accent);
    st.option.text_normal = pal.text;
    st.option.text_hover = pal.text;
    st.option.text_active = pal.text;
    st.option.text_background = pal.bg;
    st.window.tooltip_border_color = pal.line;
    ui::set_style(ctx, st);

    s_num = button(st.button, pal.num, pal.num_hover, pal.num_press, pal.text, pal.text_dim);
    s_op = button(st.button, pal.op, pal.op_hover, pal.op_press, pal.text, pal.text_dim);
    s_eq = button(st.button, pal.accent, pal.accent_hover, pal.accent_press, pal.accent_text,
                  pal.accent_text);
    s_flat = button(st.button, pal.bg, pal.flat_hover, pal.flat_press, pal.text, pal.text_dim);
    s_flat_sel = button(st.button, pal.flat_hover, pal.flat_hover, pal.flat_press, pal.text,
                        pal.text_dim);
    s_nav = button(st.button, pal.pane, pal.flat_hover, pal.flat_press, pal.text, pal.text_dim);
    s_nav.text_alignment = ui::TEXT_LEFT as u32;
    s_nav.padding = float2 { 12.0, 2.0 };
    s_nav_sel = button(st.button, pal.flat_hover, pal.flat_hover, pal.flat_press, pal.text,
                       pal.text_dim);
    s_nav_sel.text_alignment = ui::TEXT_LEFT as u32;
    s_nav_sel.padding = float2 { 12.0, 2.0 };
    s_tab = button(st.button, pal.bg, pal.bg, pal.bg, pal.text, pal.text_dim);
}

// --- Bausteine ---------------------------------------------------------------------

let K_NUM = 0;
let K_OP = 1;
let K_EQ = 2;
let K_FLAT = 3;
let K_FLAT_SEL = 4;

fn style_of(kind: i64) -> ui::StyleButton {
    match kind {
        K_NUM => s_num,
        K_EQ => s_eq,
        K_FLAT => s_flat,
        K_FLAT_SEL => s_flat_sel,
        _ => s_op,
    }
}

// Die Rechenzeichen zeichnet Windows mit eigenen Glyphen, die auch in
// Segoe Fluent Icons stehen; Segoe UIs ÷ und × wären viel zu klein.
fn op_icon(label: const u8[:]) -> u32 {
    if label == "+" { 0xE948 } else if label == "−" { 0xE949 } else if label == "×" { 0xE947 }
    else if label == "÷" { 0xE94A } else if label == "=" { 0xE94E } else if label == "%" { 0xE94C }
    else { 0 }
}

// Eine Taste; gesperrt erscheint sie blass und reagiert nicht.
fn key(ctx: ui::Context, label0: const u8[:], kind: i64, font0: ui::Font, enabled: bool = true) -> bool {
    let ic = op_icon(label0);
    let it = icon_text(ic);
    let label = if ic != 0 { it[..] } else { label0 };
    let font = if ic != 0 { f_icon } else { font0 };
    var s = style_of(kind);
    if !enabled {
        s.text_normal = pal.text_off;
        s.text_hover = pal.text_off;
        s.text_active = pal.text_off;
        s.hover = s.normal;
        s.active = s.normal;
    }
    ui::style_push_font(ctx, font);
    let hit = ui::button_label_styled(ctx, s, label);
    ui::style_pop_font(ctx);
    hit && enabled
}

fn icon_text(cp: u32) -> u8[..8] {
    var s: u8[>..] = [];
    push_utf8(s, cp);
    var t: u8[..8] = [];
    t.append(s);
    t
}

fn icon_key(ctx: ui::Context, cp: u32, kind: i64, enabled: bool = true) -> bool {
    let t = icon_text(cp);
    key(ctx, t, kind, f_icon, enabled)
}

fn text(ctx: ui::Context, s: const u8[:], font: ui::Font, color: ui::Color, align: i64) {
    ui::style_push_font(ctx, font);
    ui::label_colored(ctx, s, align, color);
    ui::style_pop_font(ctx);
}

// Die größte Anzeigeschrift, in der s in die Breite w passt.
fn fit_font(s: const u8[:], w: f32) -> ui::Font {
    for i in DISP_SIZES.len {
        if ui::text_width(f_disp[i], s) <= w { return f_disp[i]; }
    }
    f_disp[DISP_SIZES.len - 1]
}
