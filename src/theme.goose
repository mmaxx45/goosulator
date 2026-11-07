// Farben, Schriften und Tasten im Stil des Windows-11-Rechners.
import std;
import os;
import gfx;
import ui;
import src.sys;

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
    bar: ui::Color,
    nav_sel: ui::Color, nav_hover: ui::Color,             // Auswahlbalken in der Navigation
}

// Die Farben stammen aus App.xaml des Windows-Rechners
// (github.com/microsoft/calculator): Tasten sind halbtransparentes Weiß
// über dem Mica-Hintergrund, Ziffern 12,5 %, Operatoren 8,5 % usw. Mica
// selbst tönt Windows nach dem Hintergrundbild; hier steht seine neutrale
// Grundfarbe. Die Akzentfarbe kommt wie beim Original aus den
// Windows-Einstellungen.
fn mix(x: u8, y: u8, a: f64) -> i64 { (x + (y - x as f64) * a + 0.5) as! i64 }

fn over(bg: ui::Color, fg: ui::Color, a: f64) -> ui::Color {
    ui::rgb(mix(bg.r, fg.r, a), mix(bg.g, fg.g, a), mix(bg.b, fg.b, a))
}

fn accent_or(index: i64, fallback: ui::Color) -> ui::Color {
    var c: u8[4] = [0; 4];
    if sys::accent(index, c) { ui::rgb(c[0], c[1], c[2]) } else { fallback }
}

fn dark_palette() -> Palette {
    let bg = ui::rgb(0x20, 0x20, 0x20);
    let white = ui::rgb(255, 255, 255);
    let pane = ui::rgb(0x2c, 0x2c, 0x2c);
    let acc = accent_or(1, ui::rgb(0x60, 0xcd, 0xff));      // SystemAccentColorLight2
    Palette {
        bg: bg,
        pane: pane,
        num: over(bg, white, 0.125), num_hover: over(bg, white, 0.0852),
        num_press: over(bg, white, 0.0359),
        op: over(bg, white, 0.0852), op_hover: over(bg, white, 0.1256),
        op_press: over(bg, white, 0.0852),
        accent: acc, accent_hover: over(bg, acc, 0.9), accent_press: over(bg, acc, 0.8),
        accent_text: ui::rgb(0, 0, 0),
        text: white, text_dim: over(bg, white, 0.786), text_off: over(bg, white, 0.363),
        flat_hover: over(bg, white, 0.0605), flat_press: over(bg, white, 0.0419),
        line: over(pane, white, 0.0837),
        bar: acc,
        nav_sel: over(pane, white, 0.0605), nav_hover: over(pane, white, 0.0419),
    }
}

fn light_palette() -> Palette {
    let bg = ui::rgb(0xf3, 0xf3, 0xf3);
    let white = ui::rgb(255, 255, 255);
    let black = ui::rgb(0, 0, 0);
    let pane = ui::rgb(0xfc, 0xfc, 0xfc);
    let acc = accent_or(4, ui::rgb(0x00, 0x5f, 0xb8));      // SystemAccentColorDark1
    Palette {
        bg: bg,
        pane: pane,
        num: white, num_hover: over(bg, white, 0.75), num_press: over(bg, white, 0.5),
        op: over(bg, white, 0.5), op_hover: over(bg, white, 0.25), op_press: over(bg, white, 0.125),
        accent: acc, accent_hover: over(bg, acc, 0.9), accent_press: over(bg, acc, 0.8),
        accent_text: white,
        text: over(bg, black, 0.894), text_dim: over(bg, black, 0.62), text_off: over(bg, black, 0.361),
        flat_hover: over(bg, black, 0.0373), flat_press: over(bg, black, 0.0241),
        line: over(pane, black, 0.0803),
        bar: acc,
        nav_sel: over(pane, black, 0.0373), nav_hover: over(pane, black, 0.0241),
    }
}

var dark = !sys::light_theme();
var pal: Palette = dark_palette();

// Schriften: alle in einem Atlas, damit ein Kontext sie alle zeichnen kann.
var atlas: ui::FontAtlas;
var f_text: ui::Font;           // 14: Beschriftungen, Listen
var f_small: ui::Font;          // 12: kleine Tasten
var f_head: ui::Font;           // 15 halbfett: Überschriften der Navigation
var f_item: ui::Font;           // 15: Einträge der Navigation
var f_expr: ui::Font;           // 15: Rechenweg
var f_key: ui::Font;            // 17: Funktionstasten
var f_op: ui::Font;             // 24: ÷ × − + =
var f_num: ui::Font;            // 20 halbfett: Ziffern
var f_title: ui::Font;          // 20 halbfett: "Standard"
var f_big: ui::Font;            // 28 halbfett: Werte im Konverter
var f_sym: ui::Font;            // 17 Segoe UI Symbol: ⌊x⌋, ≪
var f_icon: ui::Font;           // 16 Segoe Fluent Icons
var f_icon_s: ui::Font;         // 12
var f_calc: ui::Font;           // 16 Calculator Fluent Icons: Rechenzeichen
var f_calc_s: ui::Font;         // 14: MC MR M+ M− MS M˅
var f_digit: ui::Font;          // 20 normal: Ziffern, wie NumericButtonStyle

// Die Symbolschrift des Windows-Rechners (MIT, github.com/microsoft/calculator).
let CALC_ICONS: const u8[:] = embed_file("../data/CalculatorIcons.ttf");
let CALC_RANGES: u32[2] = [0xE600, 0xF8FF];
let DISP_SIZES: f32[9] = [72.0, 58.0, 46.0, 40.0, 34.0, 30.0, 26.0, 22.0, 18.0];   // em; Results.MaxFontSize 72/46/26
var f_disp: ui::Font[9];

// Die Zeichen, die der Rechner braucht: Latin-1, hoch- und tiefgestellte
// Ziffern und Buchstaben, Pfeile, mathematische Zeichen.
let TEXT_RANGES: u32[26] = [0x20, 0xFF, 0x100, 0x17F, 0x2B0, 0x2FF, 0x3C0, 0x3C0, 0x400, 0x44F,
                            0xE3F, 0xE3F, 0x1D00, 0x1D7F, 0x20A0, 0x20CF,
                            0x2010, 0x2027, 0x2070, 0x209F, 0x2190, 0x2193,
                            0x2200, 0x22FF, 0x2300, 0x23FF];
let ICON_RANGES: u32[2] = [0xE700, 0xF8FF];

fn font_path(name: const u8[:]) -> u8[>..] {
    var windir: u8[>..] = [];
    if !env("WINDIR", windir) { windir.append("C:\\Windows"); }
    str(windir, "\\Fonts\\", name)
}

// Nuklear misst eine Schrift über ihre Zeilenhöhe (Ober- plus Unterlänge),
// XAML über das Geviert (em). Bei Segoe UI ist die Zeile 1,3301 em hoch;
// size ist hier wie in XAML in em angegeben.
let SEGOE_LINE: f32 = 1.3301;

fn add(path: const u8[:], em: f32, ranges: const u32[:]) -> ui::Font {
    let size = if ranges[0] >= 0xE000 { em } else { em * SEGOE_LINE };
    if file_exists(path) {
        let cfg = ui::FontConfig { oversample_h: 2, fallback_glyph: ranges[0], .. };
        let f = ui::add_font_from_file(atlas, path, size, cfg, ranges);
        if f.id != 0 { return f; }
    }
    ui::add_default_font(atlas, size)
}

fn add_mem(ttf: const u8[:], size: f32) -> ui::Font {
    let cfg = ui::FontConfig { oversample_h: 2, fallback_glyph: 0xE61D, .. };
    let f = ui::add_font_from_memory(atlas, ttf, size, cfg, CALC_RANGES);
    if f.id != 0 { f } else { f_icon }
}

fn load_fonts(scale: f32) -> bool {
    atlas = ui::create_font_atlas();
    let regular = font_path("segoeui.ttf");
    let semibold = font_path("seguisb.ttf");
    let symbol = font_path("seguisym.ttf");
    var icons = font_path("SegoeIcons.ttf");
    if !file_exists(icons) { icons = font_path("segmdl2.ttf"); }
    // Größen in em, aus App.xaml und den Views des Windows-Rechners.
    f_text = add(regular, 14.0, TEXT_RANGES);       // BodyFontSize
    f_small = add(semibold, 12.0, TEXT_RANGES);     // CaptionFontSize
    f_head = add(semibold, 14.0, TEXT_RANGES);      // BodyStrongFontSize
    f_item = add(regular, 14.0, TEXT_RANGES);
    f_expr = add(regular, 14.0, TEXT_RANGES);
    f_key = add(regular, 16.0, TEXT_RANGES);        // CE, C: FontSize="16"
    f_op = add(regular, 20.0, TEXT_RANGES);
    f_num = add(semibold, 16.0, TEXT_RANGES);
    f_title = add(semibold, 20.0, TEXT_RANGES);     // Kopfzeile "Standard"
    f_big = add(semibold, 20.0, TEXT_RANGES);
    f_sym = add(symbol, 16.0, TEXT_RANGES);
    f_icon = add(icons, 16.0, ICON_RANGES);
    f_icon_s = add(icons, 12.0, ICON_RANGES);
    for i in DISP_SIZES.len { f_disp[i] = add(semibold, DISP_SIZES[i], TEXT_RANGES); }
    let variable = font_path("SegUIVar.ttf");
    f_digit = add(if file_exists(variable) { variable[..] } else { regular[..] }, 18.0, TEXT_RANGES);
    f_calc = add_mem(CALC_ICONS, 20.0);             // CalcStandardOperatorCaptionSize
    f_calc_s = add_mem(CALC_ICONS, 16.0);
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
var s_nav_btn: ui::StyleButton;

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
    st.window.padding = float2 { 3.0, 0.0 };       // 2 px Rand, 1 px Tastenrand
    st.window.spacing = float2 { 2.0, 2.0 };       // Margin="1" je Taste
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
    s_nav_btn = button(st.button, pal.nav_sel, pal.nav_hover, pal.nav_sel, pal.text, pal.text_dim);
}

// --- Bausteine ---------------------------------------------------------------------

let K_NUM = 0;
let K_OP = 1;
let K_EQ = 2;
let K_FLAT = 3;
let K_FLAT_SEL = 4;
let K_NAV_SEL = 5;

fn style_of(kind: i64) -> ui::StyleButton {
    match kind {
        K_NUM => s_num,
        K_EQ => s_eq,
        K_FLAT => s_flat,
        K_FLAT_SEL => s_flat_sel,
        K_NAV_SEL => s_nav_btn,
        _ => s_op,
    }
}

// Beschriftungen, die der Windows-Rechner als Glyphen seiner eigenen
// Schrift zeichnet (Content="&#x…;" in den XAML-Dateien), mit der Glyphe
// dahinter.
let GLYPHS: const u8[:][68] = [
    "%", "",
    "÷", "",
    "×", "",
    "−", "",
    "+", "",
    "=", "",
    "+/-", "",
    "¹/ₓ", "",
    "x²", "",
    "²√x", "",
    "|x|", "",
    "⌊x⌋", "",
    "⌈x⌉", "",
    "→dms", "",
    "→deg", "",
    "π", "",
    "xʸ", "",
    "10ˣ", "",
    "x³", "",
    "³√x", "",
    "ʸ√x", "",
    "2ˣ", "",
    "logᵧx", "",
    "eˣ", "",
    "n!", "",
    "≪", "",
    "≫", "",
    "MC", "",
    "MR", "",
    "M+", "",
    "M−", "",
    "MS", "",
    "M˅", "",
    "⌫", "",
];

fn glyph_of(label: const u8[:]) -> const u8[:] {
    var i = 0;
    while i < GLYPHS.len {
        if GLYPHS[i] == label { return GLYPHS[i + 1]; }
        i += 2;
    }
    ""
}

// Eine Taste; gesperrt erscheint sie blass und reagiert nicht.
fn key(ctx: ui::Context, label0: const u8[:], kind: i64, font0: ui::Font, enabled: bool = true) -> bool {
    let g = glyph_of(label0);
    let label = if g.len > 0 { g } else { label0 };
    let memory = label0.len >= 2 && label0[0] == 'M' && g.len > 0;
    let font = if g.len == 0 { font0 } else if memory { f_calc_s } else { f_calc };
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

// Die größte Anzeigeschrift bis zur Höhe hmax, in der s in die Breite w passt.
fn fit_font_h(s: const u8[:], w: f32, hmax: f32) -> ui::Font {
    for i in DISP_SIZES.len {
        if DISP_SIZES[i] <= hmax && ui::text_width(f_disp[i], s) <= w { return f_disp[i]; }
    }
    f_disp[DISP_SIZES.len - 1]
}

// Die größte Anzeigeschrift, in der s in die Breite w passt.
fn fit_font(s: const u8[:], w: f32) -> ui::Font {
    for i in DISP_SIZES.len {
        if ui::text_width(f_disp[i], s) <= w { return f_disp[i]; }
    }
    f_disp[DISP_SIZES.len - 1]
}
