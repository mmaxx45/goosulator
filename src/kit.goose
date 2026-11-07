// Kleine Widgets, die Nuklear nicht hat: Listeneinträge mit zwei Zeilen,
// Navigationseinträge mit Symbol, Reiter mit Unterstrich.
import std;
import gfx;
import ui;
import src.theme;

namespace kit;

var scale: f32 = 1.0;

fn hovered(ctx: ui::Context, r: ui::Rect) -> bool {
    ui::input_is_mouse_hovering_rect(ctx, r)
}

fn clicked(ctx: ui::Context, r: ui::Rect) -> bool {
    ui::input_is_mouse_click_in_rect(ctx, ui::BUTTON_LEFT, r) &&
        ui::input_is_mouse_released(ctx, ui::BUTTON_LEFT)
}

fn text_right(ctx: ui::Context, r: ui::Rect, s: const u8[:], font: ui::Font, color: ui::Color) {
    let w = ui::text_width(font, s);
    let h = ui::info(font).height;
    let x = max(r.x, r.x + r.w - w);
    ui::draw_text(ctx, ui::rect(x, r.y + (r.h - h) * 0.5, min(w, r.w), h), s, font,
                  ui::rgba(0, 0, 0, 0), color);
}

fn text_left(ctx: ui::Context, r: ui::Rect, s: const u8[:], font: ui::Font, color: ui::Color) {
    let w = ui::text_width(font, s);
    let h = ui::info(font).height;
    ui::draw_text(ctx, ui::rect(r.x, r.y + (r.h - h) * 0.5, min(w + 1.0, r.w), h), s, font,
                  ui::rgba(0, 0, 0, 0), color);
}

fn text_center(ctx: ui::Context, r: ui::Rect, s: const u8[:], font: ui::Font, color: ui::Color) {
    let w = ui::text_width(font, s);
    let h = ui::info(font).height;
    ui::draw_text(ctx, ui::rect(r.x + (r.w - w) * 0.5, r.y + (r.h - h) * 0.5, w + 1.0, h), s,
                  font, ui::rgba(0, 0, 0, 0), color);
}

// Ein Eintrag im Verlauf oder Speicher: oben klein der Rechenweg, darunter
// groß das Ergebnis, beides rechtsbündig.
fn two_line_item(ctx: ui::Context, top: const u8[:], bottom: const u8[:], h: f32) -> bool {
    ui::layout_row_dynamic(ctx, h, 1);
    let state, r = ui::widget(ctx);
    if state == ui::WIDGET_INVALID { return false; }
    let hot = state == ui::WIDGET_VALID && hovered(ctx, r);
    if hot { ui::fill_rect(ctx, r, 4.0, th::pal.flat_hover); }
    let inner = ui::rect(r.x + 12.0, r.y + 6.0, r.w - 24.0, r.h - 12.0);
    if top.len > 0 {
        text_right(ctx, ui::rect(inner.x, inner.y, inner.w, 18.0), top, th::f_text, th::pal.text_dim);
    }
    text_right(ctx, ui::rect(inner.x, inner.y + inner.h - 30.0, inner.w, 30.0), bottom,
               th::f_big, th::pal.text);
    hot && clicked(ctx, r)
}

// Ein Eintrag der Navigation: Symbol, Name, beim gewählten ein Balken links.
fn nav_item(ctx: ui::Context, icon: u32, name: const u8[:], selected: bool) -> bool {
    let state, r = ui::widget(ctx);
    if state == ui::WIDGET_INVALID { return false; }
    let hot = state == ui::WIDGET_VALID && hovered(ctx, r);
    if selected || hot { ui::fill_rect(ctx, r, 4.0, th::pal.flat_hover); }
    if selected {
        ui::fill_rect(ctx, ui::rect(r.x, r.y + r.h * 0.5 - 8.0, 3.0, 16.0), 1.5, th::pal.bar);
    }
    if icon != 0 {
        let t = th::icon_text(icon);
        text_center(ctx, ui::rect(r.x + 4.0, r.y, 32.0, r.h), t, th::f_icon, th::pal.text);
    }
    text_left(ctx, ui::rect(r.x + 44.0, r.y, r.w - 48.0, r.h), name, th::f_text, th::pal.text);
    hot && clicked(ctx, r)
}

// Ein Reiter: Text, beim gewählten unterstrichen.
fn tab(ctx: ui::Context, name: const u8[:], selected: bool) -> bool {
    let state, r = ui::widget(ctx);
    if state == ui::WIDGET_INVALID { return false; }
    let hot = state == ui::WIDGET_VALID && hovered(ctx, r);
    let w = ui::text_width(th::f_text, name);
    let font = if selected { th::f_small } else { th::f_text };
    text_center(ctx, r, name, font, if selected || hot { th::pal.text } else { th::pal.text_dim });
    if selected {
        ui::fill_rect(ctx, ui::rect(r.x + (r.w - w) * 0.5, r.y + r.h - 3.0, w, 3.0), 1.5, th::pal.bar);
    }
    hot && clicked(ctx, r)
}

// Ein Wert, den man anklickt, um ihn zu bearbeiten (Konverter, Datum).
fn value_field(ctx: ui::Context, s: const u8[:], font: ui::Font, active: bool, h: f32) -> bool {
    ui::layout_row_dynamic(ctx, h, 1);
    let state, r = ui::widget(ctx);
    if state == ui::WIDGET_INVALID { return false; }
    let hot = state == ui::WIDGET_VALID && hovered(ctx, r);
    text_left(ctx, ui::rect(r.x + 8.0, r.y, r.w - 16.0, r.h), s, font,
              if active { th::pal.text } else if hot { th::pal.text } else { th::pal.text_dim });
    hot && clicked(ctx, r)
}

// Leerzeile der Höhe h.
fn gap(ctx: ui::Context, h: f32) {
    ui::layout_row_dynamic(ctx, h, 1);
    ui::spacer(ctx);
}

// Wie viel Höhe im Fenster unter der aktuellen Zeile noch frei ist.
// Kostet eine 1 Einheit hohe Leerzeile.
fn remaining(ctx: ui::Context, h: f32) -> f32 {
    ui::layout_row_dynamic(ctx, 1.0, 1);
    let b = ui::widget_bounds(ctx);
    ui::spacer(ctx);
    let win = ui::window_get_position(ctx);
    h - (b.y - win.y) - 6.0
}
