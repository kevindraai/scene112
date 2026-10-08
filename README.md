# SCÈNE 112

Nederlandstalige 3D-singleplayergame over politie, brandweer, recherche en brandonderzoek, voor spelers van 14+. De volledige productopdracht staat in [docs/WORKORDER.md](docs/WORKORDER.md).

**Ontwikkelbuild M1:** een compacte Nederlandse wijk met bureau/kazerne, third-person lopen/sprinten, rijden/remmen met politieauto en tankautospuit, veilige in-/uitstap, zes bewegende en aanspreekbare buurtbewoners, radio met herhaalbare meldingen en gevolgen, kaart/GPS, menu/pauze/instellingen en saves voor speler, voertuigen en incidenten. M2–M5 en v0.1.0 zijn nog niet opgeleverd. De korte M1-incidentbeoordelingen worden in volgende mijlpalen volwaardige politie-/brandweercasussen.

## Spelen

Download de twee private testbuilds uit de artifacts van een succesvolle [Native builds](../../actions/workflows/native-build.yml)-run. Uitpakken: Windows `Scene112.exe`; macOS `Scene112.app`. Er is geen engine-installatie nodig. macOS is Universal 2 en ad-hoc gesigneerd; nog niet genotariseerd. [Installatie, buildinstructies en testgrenzen](docs/BUILDING.md).

Kies **Vrije politiedienst** of **Vrije brandweerdienst**. Neem uitrusting/PBM en meld je bij de radio van je bureau/kazerne. Benader het juiste voertuig en stap in. Neem via R een melding aan, volg de kaart/GPS, rem, stap veilig uit en kies ter plaatse een zorgvuldige aanpak. Je kunt daarna verder surveilleren. Doorsturen en laten verlopen zijn mogelijk; onzorgvuldige keuzes krijgen een lagere beoordeling.

| Bediening | Actie |
|---|---|
| WASD / Shift | Lopen of rijden / sprinten |
| Muis | Camera draaien |
| E / Spatie | Handelen of in-/uitstappen / voertuig remmen |
| R | Meldkamer, aannemen of doorgeven |
| M / Esc | Wijkhulp / pauze |
| F5 / F9 | Dienst opslaan / laatste opslag laden |

Een save wordt pas vervangen wanneer je opslaat. Nieuwe dienst maakt geen bestaande opslag leeg. Opslag staat in de platformcorrecte gebruikersmap `Scene112`. M0-saves worden gemigreerd naar schema 2. Corrupte of onbekende saveversies worden geweigerd en behouden; een gevalideerde vorige opslag wordt als herstelkopie gebruikt.

## Ontwikkelen en bewijs

Godot **4.7.2 stable**, standard + GDScript, Compatibility-renderer. Open `project.godot`, of gebruik de geverifieerde taakgebonden toolchain in [BUILDING](docs/BUILDING.md). Geen plugins of betaalde assets nodig.

- [Uitvoeringsplan M0–M5](docs/EXECUTION_PLAN.md)
- [M0-platformbewijs](docs/evidence/M0.md) · [M1-gameplaybewijs](docs/evidence/M1.md)
- [Assetherkomst/licenties](docs/LICENSES.md)

CI importeert en test de exacte PR-head, exporteert native macOS/Windows-distributies, controleert structuur/architectuur en start de verpakte runtime op native runners. Een export of headless starttest bewijst geen menselijke grafische playthrough op macOS/Windows; die status wordt apart vastgelegd. Per speelbaar ijkpunt blijven beide platformen verplicht.
