# SCÈNE 112 | Beeldpakket v1 (Noorderkade)

**Zelfstandig grafisch opleverpakket.** Alle afbeeldingen zijn originele, deterministische SVG-bronbestanden voor SCÈNE 112. Geen externe afbeeldingen, fonts, merknamen of afhankelijkheden. Illustraties zijn **geen screenshots van de speelbare game**.

## Art direction

Een fictieve Nederlandse stad, gezien op het moment dat een gewone avonddienst verandert in een ingrijpend incident. Baksteen, nat asfalt, water, bedrijventerrein, politiebureau en kazerne. Niet Amerikaanse GTA-esthetiek of fotorealistische beloften, wel hoogwaardige grafische storytelling voor een **gestileerde 3D-game**.

**Kleuren zijn overgenomen uit de actuele Godot-wereld** (`scripts/world.gd`): navy `#193655`, politieblauw `#2885a8`, baksteen `#a46450`, crème `#e9d9bb`, brandweerrood `#bd413e`, glas `#81b5c2`, asfalt `#3a4650`. Aanvullend: informatieturkoois `#5cd6d1`, handelingsamber `#efb84d`, achtergrond `#091722`.

## Bestanden

- `brand/mark.svg`: 512×512 beeldmerk, alleen paden en vormen. Eigen fictief merk zonder officiële korpssymboliek.
- `brand/wordmark.svg`: SCÈNE 112 titel/marketing, 1600×400, met live SVG-tekst. **Voor Godot de lettervormen eerst naar paden omzetten of rasteriseren**; SVG-fonts worden niet vanzelf altijd identiek gerenderd.
- `brand/cover-emblem.svg`: 1024×1024 compositie voor folder / social avatar.
- `key-art/main-menu.svg`: 1920×1080 filmische vectorillustratie met bewust donker en rustig linkergebied voor Codex' werkelijke menu.
- `key-art/mission-police.svg`, `mission-fire.svg`, `mission-investigation.svg`, `mission-academy.svg`: 1024×576 levelkaarten zonder ingebrande tekst.
- `ui/*.svg`: tien 128×128 pictogrammen voor politie, brandweer, recherche, brandonderzoek, radio, dossier, academie, kaart, bewijs, waarschuwing.
- `tokens.json`: palet, maatvoering en semantiek.

## Afstemming op de daadwerkelijke code

Gecontroleerd op 8 oktober 2026: Godot **4.7.2**, GDScript, Compatibility-renderer, 1280×720. `scripts/app.gd` heeft momenteel een menuvenster links rond (50,55) met 470×590 afmetingen en een HUD op (24,24). `scripts/world.gd` bouwt het fictieve Noorderkade procedureel op, inclusief bureau, kazerne, rijtjeshuizen, plein en industrie. M0/M1 zijn geen volwaardige recherche- en brandweersimulatie. Gebruik de illustraties daarom eerst voor menu en rolkeuze; laat de campagnekaarten pas zien wanneer overeenkomstige gameplay bestaat.

## Veilig inbouwen

1. **Deze branch verandert geen productiescripts, scènes of actieve assets.** Laat Codex de lopende hoofdwerklijn afronden.
2. Maak als volgende aparte gebruikersuitkomst maximaal één integratie-PR, beginnend met het hoofdmenu, het beeldmerk en vier rolpictogrammen. Laat interne navigatie, saves, inputcapture en pauzeren werken.
3. Houd menu-knoppen en titels in Godot (`Control`, `Label`, `TextureRect`). Gebruik `key-art/main-menu.svg` als full-rect achtergrond met correcte aspect crop. Gebruik een scrim waar nodig; toets contrast op 1280×720.
4. SVG's zijn bronnen. Controleer Godot 4.7.2 SVG-import; rasteriseer waar nodig reproduceerbaar naar PNG/WebP. Gebruik geen browserengine. Gedrukte titels en illustratiebeschrijvingen zijn geen game-UI.
5. CI: daadwerkelijke scène import, 1280×720 UI-tests, macOS Universal 2 én Windows x64 exports; gebruikersinteracties ongewijzigd.
6. Voeg bij integratie toe aan `docs/LICENSES.md`: 'SCÈNE 112 visual identity v1, originele vectorillustraties voor dit project; geen derdenmateriaal'. Geen fontbestanden distribueren.
7. Geen verzonnen leeftijdscertificering (PEGI), geen afbeeldingen voorstellen als gameplay-screenshots of claimen dat niet-gebouwde rollen al speelbaar zijn.

**Hand-off voor Codex:** Integreer de grafische identiteit wanneer de volgende zinvolle UI-slice aan de beurt is; geen aparte PR zolang een andere implementatie-PR actief is. Art branch: `art/scene112-visual-identity-v1`.
