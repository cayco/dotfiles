---
name: chrome-shopping
description: >-
  Use this skill when the user asks to search for products, parts, check prices,
  compare e-commerce offers, or inspect auction descriptions and technical parameters
  (e.g., Allegro, Amazon, Ceneo, OLX) using Chrome CDP (local 127.0.0.1:9222 or
  always-on WrapVM on prox at http://10.0.2.100:9223).
---

# Chrome E-Commerce Shopping & Product Search

Ta procedura służy do deterministycznego, szybkiego i bezlimitowego wyszukiwania ofert oraz sprawdzania szczegółowych opisów i parametrów aukcji (Allegro, Amazon, Ceneo itp.) za pośrednictwem Chrome CDP — automatycznie łączy się z lokalnym Chrome (`http://127.0.0.1:9222`), a gdy jest wyłączony, korzysta ze współdzielonego Chrome w **WrapVM na `prox` (`http://10.0.2.100:9223`, podgląd i logowanie: `https://wrapvm.int.cayco.pl`)**.

## Zasady działania (Kaganiec tokenowy):
1. **NIGDY nie pobieraj całego DOM-u strony (`document.body.innerText`, `innerHTML` ani snapshotów HTML).** Śmiecenie drzewem strony zapełnia kontekst i grozi limitami chmurowymi.
2. **NIGDY nie używaj bezpośredniego curl/requests do pobierania stron sklepów.** Sklepy (Allegro, Amazon, OLX) blokują boty przez Cloudflare i reCAPTCHA. Chrome użytkownika jest już uwierzytelniony i omija blokady.
3. **Zawsze używaj dedykowanego lokalnego skryptu narzędziowego:**
   [search_shops.mjs](./scripts/search_shops.mjs)

---

## Procedura wykonania:

### Tryb 1: Wyszukiwanie ofert na listingu (np. "znajdź mi wąż pneumatyczny")
Gdy użytkownik szuka produktów lub porównuje ceny, uruchom wyszukiwanie listingu:

```bash
# Wyszukiwanie na Allegro (domyślne):
~/.gemini/config/skills/chrome-shopping/scripts/search_shops.mjs -s allegro -q "nazwa produktu" -l 10

# Wyszukiwanie na Amazon.pl:
~/.gemini/config/skills/chrome-shopping/scripts/search_shops.mjs -s amazon -q "nazwa produktu" -l 10

# Wyszukiwanie na Ceneo:
~/.gemini/config/skills/chrome-shopping/scripts/search_shops.mjs -s ceneo -q "nazwa produktu" -l 10

# Wyszukiwanie na OLX (opcjonalnie: --courier dla Przesyłki OLX, --city warszawa, --category elektronika):
~/.gemini/config/skills/chrome-shopping/scripts/search_shops.mjs -s olx -q "seagate exos 10tb" --category elektronika --courier -l 15
~/.gemini/config/skills/chrome-shopping/scripts/search_shops.mjs -s olx -q "dysk 12tb" --category elektronika --city warszawa -l 15
```
- Przedstaw wyniki w czytelnej tabeli Markdown z bezpośrednimi linkami do aukcji.

---

### Tryb 2: Sprawdzenie opisu i parametrów technicznych konkretnej aukcji
Gdy użytkownik pyta o szczegóły oferty (np. *"co jest w zestawie oferty 1?"*, *"jaki ma gwint?"*, *"sprawdź opis tej aukcji"*, *"czy ma fakturę?"*), uruchom skrypt z parametrem `-d <URL>`:

```bash
~/.gemini/config/skills/chrome-shopping/scripts/search_shops.mjs -d "https://allegro.pl/oferta/..."
```
Skrypt wejdzie bezpośrednio w podany link i wyciągnie:
- **Tabelę parametrów technicznych** (np. EAN, producent, stan, gwint, wymiary),
- **Oczyszczony opis przedmiotu od sprzedawcy** (bez nagłówków, stopki i banerów Allegro),
- **Cenę i dane sprzedawcy**.

Odpowiedz użytkownikowi zwięźle, bezpośrednio cytując lub podsumowując znalezione parametry techniczne.
