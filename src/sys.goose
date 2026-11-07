// Systemeinstellungen aus der Registry: Akzentfarbe und hell/dunkel, so wie
// sie der Windows-Rechner von Windows übernimmt.
import std;

namespace sys;

extern "advapi32" {
    fn RegGetValueA(hkey: u64, subkey: const u8[256]&, value: const u8[64]&, flags: u32,
                    kind: u64, data: u8[64]&, size: u32&) -> i32;
}

// HKEY_CURRENT_USER: (HKEY)(LONG)0x80000001, vorzeichenerweitert.
let HKCU: u64 = 0xFFFFFFFF80000001;
let RRF_RT_REG_BINARY: u32 = 0x8;
let RRF_RT_REG_DWORD: u32 = 0x10;

fn key(s: const u8[:]) -> u8[256] {
    var b: u8[256] = [0; 256];
    for c, i in s { if i < 255 { b[i] = c; } }
    b
}

fn name(s: const u8[:]) -> u8[64] {
    var b: u8[64] = [0; 64];
    for c, i in s { if i < 63 { b[i] = c; } }
    b
}

fn read(subkey: const u8[:], value: const u8[:], flags: u32, out: u8[64]&) -> i64 {
    var size: u32 = 64;
    let k = key(subkey);
    let v = name(value);
    let r = RegGetValueA(HKCU, k, v, flags, 0, out, size);
    if r != 0 { return -1; }
    size
}

// Die Akzentpalette: acht RGBA-Farben, von Hell3 über die Akzentfarbe bis
// Dunkel3. Index 1 ist Hell2 (dunkles Design), 4 ist Dunkel1 (helles).
fn accent(index: i64, out: u8[4]&) -> bool {
    var data: u8[64] = [0; 64];
    let n = read("Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Accent", "AccentPalette",
                 RRF_RT_REG_BINARY, data);
    if n < 32 { return false; }
    for i in 4 { out[i] = data[index * 4 + i]; }
    true
}

// Ob Apps hell dargestellt werden sollen; ohne Eintrag dunkel.
fn light_theme() -> bool {
    var data: u8[64] = [0; 64];
    let n = read("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", "AppsUseLightTheme",
                 RRF_RT_REG_DWORD, data);
    n >= 4 && data[0] != 0
}
