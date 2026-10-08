# SCÈNE 112

Nederlandstalige 3D-singleplayergame over politie, brandweer, recherche en brandonderzoek, voor spelers van 14+. De volledige productopdracht staat in [docs/WORKORDER.md](docs/WORKORDER.md).

**Ontwikkelbuild M2:** een compacte Nederlandse wijk met bureau/kazerne, third-person lopen/sprinten, rijden/remmen met politieauto en tankautospuit, veilige in-/uitstap, zes bewegende en aanspreekbare buurtbewoners, radio met herhaalbare meldingen en gevolgen, kaart/GPS en duurzame saves. De eerste campagnecasus en twee academielessen voegen zelf geplaatste afzetpionnen, locatieonderzoek, twee brongebonden gesprekken, rechten/intake, hands-on vingerafdrukken en een herstelbaar PV toe. Het aangeleverde beeldpakket vormt het menu; originele muziek en contextuele game-audio maken deel uit van deze mijlpaal. M3–M5 en v0.1.0 zijn nog niet opgeleverd. De korte vrije-dienstbeoordelingen krijgen in M5 verdere interactie.

## Spelen

Download de twee private testbuilds uit de artifacts van een succesvolle [Native builds](../../actions/workflows/native-build.yml)-run. Uitpakken: Windows `Scene112.exe`; macOS `Scene112.app`. Er is geen engine-installatie nodig. macOS is Universal 2 en ad-hoc gesigneerd; nog niet genotariseerd. [Installatie, buildinstructies en testgrenzen](docs/BUILDING.md).

Kies **Vrije politiedienst** of **Vrije brandweerdienst**. Neem uitrusting/PBM en meld je bij de radio van je bureau/kazerne. Benader het juiste voertuig en stap in. Neem via R een melding aan, volg de kaart/GPS, rem, stap veilig uit en kies ter plaatse een zorgvuldige aanpak. Je kunt daarna verder surveilleren. Doorsturen en laten verlopen zijn mogelijk; onzorgvuldige keuzes krijgen een lagere beoordeling.

Kies **Nieuwe campagne · De eerste dienst** voor de verkeerszaak of **Academie · lessen** voor herhaalbare oefeningen. Na de werkelijke rit zet je met Q drie pionnen in veilige westelijke afzetzones; richt daarvoor de camera op de grond. Bekijk schade, bandensporen en wegdek en vraag Lotte en Bram open wat zij hebben waargenomen. Orden in het PV de kaarten naar tijd en onderscheid eigen waarneming, verklaring, handeling en conclusie. Een onbewezen schuldconclusie krijgt concrete feedback en kan worden hersteld. Een geaccepteerd dossier blijft als archief beschikbaar.

In de intakeles leg je de fictieve oefengrond, zwijgrecht en rechtsbijstand vast. Positioneer afdrukken met muis of A/D en houd links of Spatie ingedrukt zolang de bewegende doelzone uitlijnt. Herhaal onscherpe opnamen; drie bruikbare registratieafdrukken bewijzen geen schuld. Vrije diensten en lessen bewaren reeds behaalde campagne- en lesresultaten. Een nieuwe campagne begint opnieuw.

| Bediening | Actie |
|---|---|
| WASD / Shift | Lopen of rijden / sprinten |
| Muis | Camera draaien |
| E / Spatie | Handelen of in-/uitstappen / voertuig remmen |
| Q | Afzetpion op de gerichte veilige grond plaatsen |
| R | Meldkamer, aannemen of doorgeven |
| H | Sirene aan/uit tijdens voertuiggebruik |
| M / Esc | Wijkhulp / pauze |
| F5 / F9 | Dienst opslaan / laatste opslag laden |

Een save wordt pas vervangen wanneer je opslaat. Nieuwe dienst maakt geen bestaande opslag leeg. Opslag staat in de platformcorrecte gebruikersmap `Scene112`. M0/M1-saves worden gemigreerd naar schema 3. Corrupte of onbekende saveversies worden geweigerd en behouden; een gevalideerde vorige opslag wordt als herstelkopie gebruikt. Audio-instellingen worden afzonderlijk bewaard en blijven ook bij een nieuwe campagne gelden.

De 3D-wijk is momenteel een gameplayblockout. De geautoriseerde [visuele kwaliteitsrichtlijn](https://github.com/kevindraai/scene112/issues/1#issuecomment-6059218603) vereist als volgende kwaliteitsmijlpaal een hoogwaardige speelbare straat met echte 3D-assets, PBR-materialen, animatie en dag-/avondbelichting. Menu-art en functionele native builds gelden niet als bewijs dat de volledige wereld visueel is afgewerkt.

## Ontwikkelen en bewijs

Godot **4.7.2 stable**, standard + GDScript, Compatibility-renderer. Open `project.godot`, of gebruik de geverifieerde taakgebonden toolchain in [BUILDING](docs/BUILDING.md). Geen plugins of betaalde assets nodig.

- [Uitvoeringsplan M0–M5](docs/EXECUTION_PLAN.md)
- [M0-platformbewijs](docs/evidence/M0.md) · [M1-gameplaybewijs](docs/evidence/M1.md) · [M2-gameplaybewijs](docs/evidence/M2.md)
- [Assetherkomst/licenties](docs/LICENSES.md)

CI importeert en test de exacte PR-head, exporteert native macOS/Windows-distributies, controleert structuur/architectuur en start de verpakte runtime op native runners. Een export of headless starttest bewijst geen menselijke grafische playthrough op macOS/Windows; die status wordt apart vastgelegd. Per speelbaar ijkpunt blijven beide platformen verplicht.
