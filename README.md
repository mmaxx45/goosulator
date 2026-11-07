# Rechner in Goose

Der Windows-11-Rechner, nachgebaut in [Goose](https://aardappel.github.io/goose/) mit dem `ui`-Modul (Nuklear über gfx/SDL3).

```
goose rechner.goose          # starten
goose build rechner.goose    # rechner.exe bauen (mit Konsolenfenster)
.uild.ps1                  # rechner.exe ohne Konsolenfenster
goose test_calc.goose        # Tests der Rechenlogik
```

**Modi:** Standard, Wissenschaftlich, Programmierer, Datumsberechnung sowie die Konverter Währung, Volumen, Länge, Gewicht und Masse, Temperatur, Energie, Fläche, Geschwindigkeit, Zeit, Leistung, Daten, Druck und Winkel. Dazu Einstellungen mit hellem und dunklem Design.

**Funktionen:** Verlauf und Speicher (ab 600 px Breite als Seitenleiste), Rechenweg, Fehlermeldungen, wiederholtes `=`, Klammern, 2nd, Trigonometrie mit DEG/RAD/GRAD und hyp, F-E, HEX/DEC/OCT/BIN, QWORD bis BYTE, Bitweise, Bitverschiebung und das Bit-Tastenfeld.

**Tastatur wie bei Windows:** Ziffern, `+ - * / % = ( )`, Enter, Esc (C), Entf (CE), Rücktaste, F9 (±), R (1/x), @ (√), Q (x²), Strg+M/P/Q/R/L für den Speicher, Strg+H (Verlauf), Strg+C/V, Alt+1…5 (Moduswechsel). Im Programmierer zusätzlich A–F, `& | ^ ~ < >` und F5–F8 (Basis).

**Wechselkurse** kommen von frankfurter.dev (Referenzkurse der EZB) über `urlmon.dll`, also ohne C-Code. Sie werden unter `%LOCALAPPDATA%\Goosulator\kurse.json` zwischengespeichert und stehen damit auch offline zur Verfügung.

**Schriften:** Segoe UI, Segoe UI Symbol und Segoe Fluent Icons werden zur Laufzeit aus `C:\Windows\Fonts` geladen.

Aufbau: `src/calc.goose` (Standard/Wissenschaftlich, Shunting-Yard), `src/progview.goose`, `src/dateview.goose`, `src/convview.goose`, `src/fx.goose` (Kurse), `src/theme.goose` (Farben, Schriften, Tasten), `src/kit.goose` (eigene Widgets), `src/numfmt.goose` (deutsches Zahlenformat).

Testschalter: `--click "x,y;x,y" --mode N --size BxH --keys "12+3E" --open trig|func|hist|mem|bitweise|schieben|bits|kalender|addieren --frames N --shot bild.png`
