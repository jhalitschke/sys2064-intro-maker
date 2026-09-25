# Offene Fragen / Abweichungen

Punkte, an denen die Spezifikation unklar oder widerspruechlich ist, und wie
sie vorerst geloest wurden.

1. **Font-Liste > 16 Eintraege.** Die Spec erlaubt 15 Katalog-Fonts, die Liste
   hat aber nur 16 Zeilen (4-19) und 2 eingebaute Fonts. `build_disk.py`
   begrenzt Fonts daher auf 14 (`CAT_MAX_FONTS`). Alternative waere eine
   scrollende Liste.
