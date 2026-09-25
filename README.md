# C64 Intro Maker

Ein C64-Programm (PAL), mit dem man auf dem C64 selbst ein Intro aus Musik,
Font, Farben, Effekten, Titel und Scrolltext zusammenstellt und als
eigenstaendig startbares PRG speichert. Spezifikation: [docs/SPEC.md](docs/SPEC.md).

## Bauen

Voraussetzungen: KickAssembler (`kickass`), VICE (`x64sc`, `c1541`),
Python 3.11+, fuer das gepackte Editor-PRG `exomizer`.

```
make          # build/intromaker.d64
make test     # Unit-Tests der Build-Tools
make smoke    # Screenshots aus VICE (build/*.png)
make run      # Editor in VICE starten
```
