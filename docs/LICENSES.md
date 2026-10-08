# Herkomst en licenties

Alle projectcode, geometrie, kleuren, UI, icon.svg en in-game teksten zijn voor SCÈNE 112 gemaakt. De afgewerkte straat, politieauto, tankautospuit en personages zijn originele Blender-bronnen en geïmporteerde GLB-assets; het overige stadsdeel bevat nog Godot-blockoutgeometrie. Er zijn geen aangekochte of van derden gekopieerde game-assets en geen nagebootste echte korpsmerken.

De eigen 3D-bronnen staan onder `source/3d`, herbouwscripts onder `tools/art` en naast de editable voertuig-/personagebronnen. De eigen PBR-texturen staan onder `assets/textures`; GLBs onder `assets/models`. Manifests leggen geometrie, maker, bron, maps en licentie vast. Blender 4.3.2 werd uitsluitend als authoringtool gebruikt, zonder externe assetbibliotheken; de editable bestanden en Python-bronnen blijven behouden. De avatar gebruikt een eigen 18-bone rig met originele idle-, loop-, ren- en draaganimaties. De projectlicentie hieronder geldt ook voor deze zelfgemaakte assets.

SCÈNE 112 visual identity v1: originele vectorillustraties voor dit project; geen derdenmateriaal. Het aangeleverde pakket in `design/visual-identity-v1` komt uit branch `art/scene112-visual-identity-v1`, commit `36cdb3a020c373ef29fcc82597d1014247a7d20d`. SVG-bronbestanden blijven behouden; er worden geen fontbestanden gedistribueerd. De illustraties zijn art direction en vormen geen gameplaybewijs.

Alle audio in `assets/audio` is origineel gecomponeerd/gesynthetiseerd voor SCÈNE 112 met de reproduceerbare bron `tools/compose_audio.py`: eigen hoofdthema, situationele score, stadsbronnen, voertuig, radio en handelingen. Er zijn geen externe samples, muziekquotes, vertrouwelijke meldkameropnamen of commerciële middleware gebruikt. `assets/audio/manifest.json` vermeldt bron, maker, projectlicentie, SHA256, lengte, kanalen en PCM-piek/RMS per bestand. De projectlicentie hieronder geldt ook voor deze eigen audio-assets.

Godot 4.7.2 en de exporttemplates: MIT, https://godotengine.org/license/ . De engine bevat componenten onder aanvullende licenties: https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt . De licentiepagina is vanuit het hoofdmenu bereikbaar; distributies moeten Godot’s copyright/licenties behouden.

De projectbron is private/proprietary, tenzij de repository-eigenaar later een projectlicentie vaststelt. De aanwezigheid van MIT-enginecode verleent geen licentie op de gamebron.
