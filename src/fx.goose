// Wechselkurse von frankfurter.dev (Referenzkurse der Europäischen
// Zentralbank), geladen über urlmon.dll und zwischengespeichert unter
// %LOCALAPPDATA%\Goosulator\kurse.json, damit der Rechner auch offline
// mit den letzten Kursen rechnet.
import std;
import os;
import json;

namespace fx;

extern "urlmon" {
    fn URLDownloadToFileA(caller: u64, url: const u8[1024]&, file: const u8[1024]&, reserved: u32,
                          callback: u64) -> i32;
}
extern "wininet" {
    fn DeleteUrlCacheEntryA(url: const u8[1024]&) -> i32;
}

let URL = "https://api.frankfurter.dev/v1/latest?base=EUR";

let IDLE = 0;
let LOADING = 1;
let READY = 2;
let FAILED = 3;

var state = IDLE;
var status: u8[..160];
var date: u8[..16];
var codes: u8[..4][>..<];
var rates: f64[>..<];           // Einheiten pro Euro
var started = false;
var pending = false;
var wait = 0;
var changed = false;

fn cstr(s: const u8[:]) -> u8[1024] {
    var b: u8[1024] = [0; 1024];
    for c, i in s { if i < 1023 { b[i] = c; } }
    b
}

fn dir() -> u8[>..] {
    var base: u8[>..] = [];
    if !env("LOCALAPPDATA", base) { if !env("TEMP", base) { base.append("."); } }
    str(base, "\\Goosulator")
}

fn cache_path() -> u8[>..] { str(dir(), "\\kurse.json") }

fn set_status(s: const u8[:]) {
    status.resize(0);
    status.append(s[..min(s.len, 160)]);
}

// "2026-11-06" -> "06.11.2026"
fn date_de() -> u8[>..] {
    if date.len != 10 { return str(date); }
    str(date[8..10], ".", date[5..7], ".", date[0..4])
}

// JSON der API einlesen; true, wenn Kurse darin waren.
fn parse(text: u8[:]) -> bool {
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, err = json::parse(text, doc, decoded);
    guard root else { return false; }
    let rs = json::member(root, "rates");
    guard rs else { return false; }
    codes.clear();
    rates.clear();
    codes.push("EUR");
    rates.push(1.0);
    json::each(rs) { n =>
        let v, ok = json::as_f64(n);
        if ok && n.key.len == 3 && v > 0.0 {
            codes.push(n.key);
            rates.push(v);
        }
    };
    let d, has_date = json::as_string(json::member(root, "date"));
    date.resize(0);
    if has_date { date.append(d[..min(d.len, 16)]); }
    changed = true;
    codes.len > 1
}

fn load_cache() -> bool {
    var text: u8[>..] = [];
    if !read_file(cache_path(), text) { return false; }
    parse(text)
}

fn start() {
    if started { return; }
    started = true;
    if load_cache() {
        state = READY;
        set_status(str("Aktualisiert: ", date_de()));
    }
    request();
}

// Das Laden blockiert kurz; es läuft erst im nächsten Bild, damit vorher
// "wird aktualisiert" zu sehen ist.
fn request() {
    state = LOADING;
    pending = true;
    wait = 2;
    set_status("Kurse werden aktualisiert …");
}

fn poll() {
    if !pending { return; }
    wait--;
    if wait > 0 { return; }
    pending = false;
    fetch();
}

fn fetch() {
    make_dir(dir());
    let tmp = str(dir(), "\\kurse.tmp");
    let url = cstr(URL);
    let file = cstr(tmp);
    DeleteUrlCacheEntryA(url);
    let hr = URLDownloadToFileA(0, url, file, 0, 0);
    var text: u8[>..] = [];
    if hr == 0 && read_file(tmp, text) && parse(text) {
        write_file_atomic(cache_path(), text);
        delete_file(tmp);
        state = READY;
        set_status(str("Aktualisiert: ", date_de()));
        return;
    }
    delete_file(tmp);
    if codes.len > 1 {
        state = READY;
        set_status(str("Offline – Kurse vom ", date_de()));
    } else {
        state = FAILED;
        set_status("Kurse konnten nicht geladen werden. Keine Internetverbindung?");
    }
}

let NAME_OFS: const u8[:][62] = [
    "AUD", "Australischer Dollar",
    "BGN", "Bulgarischer Lew",
    "BRL", "Brasilianischer Real",
    "CAD", "Kanadischer Dollar",
    "CHF", "Schweizer Franken",
    "CNY", "Chinesischer Yuan",
    "CZK", "Tschechische Krone",
    "DKK", "Dänische Krone",
    "EUR", "Euro",
    "GBP", "Britisches Pfund",
    "HKD", "Hongkong-Dollar",
    "HUF", "Ungarischer Forint",
    "IDR", "Indonesische Rupiah",
    "ILS", "Israelischer Schekel",
    "INR", "Indische Rupie",
    "ISK", "Isländische Krone",
    "JPY", "Japanischer Yen",
    "KRW", "Südkoreanischer Won",
    "MXN", "Mexikanischer Peso",
    "MYR", "Malaysischer Ringgit",
    "NOK", "Norwegische Krone",
    "NZD", "Neuseeland-Dollar",
    "PHP", "Philippinischer Peso",
    "PLN", "Polnischer Zloty",
    "RON", "Rumänischer Leu",
    "SEK", "Schwedische Krone",
    "SGD", "Singapur-Dollar",
    "THB", "Thailändischer Baht",
    "TRY", "Türkische Lira",
    "USD", "US-Dollar",
    "ZAR", "Südafrikanischer Rand",
];

fn name_of(code: const u8[:]) -> const u8[:] {
    var i = 0;
    while i < NAME_OFS.len {
        if NAME_OFS[i] == code { return NAME_OFS[i + 1]; }
        i += 2;
    }
    code
}

let SYMBOLS: const u8[:][62] = [
    "EUR", "€",
    "USD", "$",
    "GBP", "£",
    "JPY", "¥",
    "CNY", "¥",
    "AUD", "$",
    "CAD", "$",
    "HKD", "$",
    "NZD", "$",
    "SGD", "$",
    "MXN", "$",
    "INR", "₹",
    "KRW", "₩",
    "ILS", "₪",
    "TRY", "₺",
    "PHP", "₱",
    "THB", "฿",
    "PLN", "zł",
    "BRL", "R$",
    "ZAR", "R",
    "CHF", "CHF",
    "SEK", "kr",
    "NOK", "kr",
    "DKK", "kr",
    "ISK", "kr",
    "CZK", "Kč",
    "HUF", "Ft",
    "RON", "lei",
    "BGN", "лв",
    "IDR", "Rp",
    "MYR", "RM",
];

fn symbol(code: const u8[:]) -> const u8[:] {
    var i = 0;
    while i < SYMBOLS.len {
        if SYMBOLS[i] == code { return SYMBOLS[i + 1]; }
        i += 2;
    }
    code
}
