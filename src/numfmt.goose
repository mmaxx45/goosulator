// Zahlen so darstellen, wie der Windows-Rechner es in deutscher Sprache tut:
// Punkt als Tausendertrenner, Komma als Dezimaltrenner, 16 signifikante
// Stellen, Exponentialschreibweise ab 10^16 bzw. unter 10^-15.
import std;
import math;

namespace nf;

// Rohtext ("-1234567.5", "1.e+12") in deutsche Schreibweise: "-1.234.567,5".
fn de_text(out: u8[>..]&, raw: const u8[:], group: bool = true) {
    var i = 0;
    if raw.len > 0 && raw[0] == '-' {
        out.push('-');
        i = 1;
    }
    var int_end = i;
    while int_end < raw.len && ascii::is_digit(raw[int_end]) { int_end++; }
    for k in i..int_end {
        out.push(raw[k]);
        let left = int_end - k - 1;
        if group && left > 0 && left % 3 == 0 { out.push('.'); }
    }
    for k in int_end..raw.len {
        let c = raw[k];
        if c == '.' { out.push(','); } else { out.push(c); }
    }
}

// Nullen hinter dem Dezimalpunkt abschneiden, und den Punkt selbst, wenn
// nichts dahinter bleibt.
fn trimmed(raw: const u8[:]) -> const u8[:] {
    if find(raw, ".") < 0 { return raw; }
    var n = raw.len;
    while n > 0 && raw[n - 1] == '0' { n--; }
    if n > 0 && raw[n - 1] == '.' { n--; }
    raw[..n]
}

// Mantisse und Exponent: v = m * 10^e mit 1 <= |m| < 10, m auf 16 Stellen.
fn mant_exp(out: u8[>..]&, v: f64) -> i64 {
    var e = floor(log10(abs(v))) as! i64;
    var raw: u8[>..] = [];
    format_flt(raw, v / pow(10.0, e as f64), 15);
    let digits = if raw[0] == '-' { raw[1..] } else { raw[..] };
    if digits.len >= 2 && digits[0] == '1' && digits[1] == '0' {
        // Die Rundung hat 9,999... zu 10 gemacht.
        e++;
        var again: u8[>..] = [];
        format_flt(again, v / pow(10.0, e as f64), 15);
        out.append(trimmed(again));
    } else {
        out.append(trimmed(raw));
    }
    e
}

fn format_sci(out: u8[>..]&, v: f64) {
    var m: u8[>..] = [];
    let e = mant_exp(m, v);
    // Windows zeigt bei ganzzahliger Mantisse "1,e+20".
    if find(m, ".") < 0 { m.push('.'); }
    de_text(out, m);
    if e >= 0 { format(out, "e+", e); } else { format(out, "e", e); }
}

// Eine Zahl für Anzeige und Rechenweg.
fn format_num(out: u8[>..]&, v: f64, fe: bool = false, group: bool = true) {
    if is_nan(v) { out.append("NaN"); return; }
    if v == 0.0 {
        if fe { out.append("0,e+0"); } else { out.push('0'); }
        return;
    }
    let e = floor(log10(abs(v))) as! i64;
    if fe || e >= 16 || e < -15 {
        format_sci(out, v);
        return;
    }
    var raw: u8[>..] = [];
    format_flt(raw, v, clamp(15 - e, 0, 40));
    // 0,99999999999999999 kann auf 1,000... runden: dann ist trimmed richtig.
    de_text(out, trimmed(raw), group);
}

fn num(v: f64) -> u8[>..] {
    var s: u8[>..] = [];
    format_num(s, v);
    s
}

// Ganze Zahl mit Tausendertrennern, für Tage und Ähnliches.
fn format_int_de(out: u8[>..]&, v: i64) {
    var raw: u8[>..] = [];
    format(raw, v);
    de_text(out, raw);
}

// Auf n signifikante Stellen runden: sin(30°) = 0,49999999999999994 wird 0,5.
fn round_sig(v: f64, n: i64) -> f64 {
    if v == 0.0 || is_nan(v) || is_inf(v) { return v; }
    let e = floor(log10(abs(v))) as! i64;
    var raw: u8[>..] = [];
    if e >= n - 1 || n - 1 - e > 300 { return v; }
    format_flt(raw, v, n - 1 - e);
    let r, ok = parse_flt(raw);
    if ok { r } else { v }
}
