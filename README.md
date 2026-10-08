# SCÈNE 112

Nederlandstalige 3D-singleplayergame over politie, brandweer, recherche en brandonderzoek, voor spelers van 14+. De volledige productopdracht staat in [docs/WORKORDER.md](docs/WORKORDER.md).

**Ontwikkelbuild M0:** een compacte procedurele Nederlandse wijk, bureau en kazerne, third-person lopen/sprinten, camera met botsingsdetectie, uitrusting/radio/academie-interactie, hoofdmenu, pauze, instellingen en één persistent save-slot. Voertuigen zijn in deze eerste build nog geparkeerd decor. M1–M5 en v0.1.0 zijn nog niet opgeleverd.

## Spelen

Download de twee private testbuilds uit de artifacts van een succesvolle [Native builds](../../actions/workflows/native-build.yml)-run. Uitpakken: Windows `Scene112.exe`; macOS `SCÈNE 112.app`. Er is geen engine-installatie nodig. macOS is Universal 2 en ad-hoc gesigneerd; nog niet genotariseerd. [Installatie, buildinstructies en testgrenzen](docs/BUILDING.md).

Kies **Nieuwe dienst**, loop door de ingang van het bureau naar **Uitrusting**, meld je bij de **Radio** en bezoek de **Academie** op het voorplein. Verken daarna de wijk. Sla op, verplaats je en laad om je dienst te hervatten.

| Bediening | Actie |
|---|---|
| WASD / Shift | Lopen / sprinten |
| Muis | Camera draaien |
| E | Handelen bij een object |
| M / Esc | Wijkhulp / pauze |
| F5 / F9 | Dienst opslaan / laatste opslag laden |

Een save wordt pas vervangen wanneer je opslaat. Nieuwe dienst maakt geen bestaande opslag leeg. Opslag staat in de platformcorrecte gebruikersmap `Scene112`. Corrupte of onbekende saveversies worden geweigerd en behouden; een gevalideerde vorige opslag wordt als herstelkopie gebruikt.

## Ontwikkelen en bewijs

Godot **4.7.2 stable**, standard + GDScript, Compatibility-renderer. Open `project.godot`, of gebruik de geverifieerde taakgebonden toolchain in [BUILDING](docs/BUILDING.md). Geen plugins of betaalde assets nodig.

- [Uitvoeringsplan M0–M5](docs/EXECUTION_PLAN.md)
- [Testbewijs en open platformgrenzen](docs/evidence/M0.md)
- [Assetherkomst/licenties](docs/LICENSES.md)

CI importeert en test de exacte PR-head, exporteert native macOS/Windows-distributies, controleert structuur/architectuur en start de verpakte runtime op native runners. Een export of headless starttest bewijst geen menselijke grafische playthrough op macOS/Windows; die status wordt apart vastgelegd. Per speelbaar ijkpunt blijven beide platformen verplicht.
