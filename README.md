# SCÈNE 112

Nederlandstalig 3D-singleplayerconcept over politie, brandweer en brandonderzoek aan de Noorderkade, voor 14+. Deze conceptbuild bundelt drie verbonden zaken, drie academielessen, vrije diensten met drie incidentfamilies, save/load en originele offline audio. Dit is **geen geaccepteerde v0.1.0**: de volledige 20–30 minuten ervaring, definitieve visuele afwerking en laatste Intel-Mac-grafische controle zijn nog niet bewezen. [Conceptstatus en bekende beperkingen](docs/CONCEPT.md) · [volledige werkbon](docs/WORKORDER.md).

## Installeren

Gebruik de macOS- en Windows-ZIP van dezelfde build/publicatie en controleer de bijbehorende teststatus. Windows 10/11 x64: volledig uitpakken, `Scene112.exe` starten en `Scene112.pck` ernaast houden. macOS Intel/Apple Silicon: Universal 2-ZIP met Finder uitpakken en `Scene112.app` openen. De private Mac-build is ad-hoc gesigneerd, niet genotariseerd; volg zo nodig de stappen in [BUILDING](docs/BUILDING.md#installeren-zonder-ontwikkeltools). Godot of andere ontwikkelsoftware is niet nodig. Het bestaan van een ZIP betekent niet dat de laatste grafische test op dat platform geslaagd is.

## Eerste speelroute

Kies **Nieuwe campagne · De eerste dienst**. Neem bij het bureau uitrusting, meld je bij de radio en benader de politieauto. Rijd zelf naar het incident, rem en stap uit. Plaats met Q drie pionnen in de veilige afzetzones; richt op de grond. Onderzoek schade, bandensporen en wegdek en spreek Lotte en Bram. Orden in het PV tijd, eigen waarneming, verklaringen, handelingen en conclusie. Onvoldoende onderbouwde conclusies kun je verbeteren.

Ga vanuit de zaakbeoordeling verder naar **De woningbrand**. Controleer PBM en radio, rijd met de tankautospuit naar Huis 24, verken de buitenzijde/deur en sluit water aan. Leg met Q korte slangsegmenten tot je werkplek. R opent het inzetplan; richt de waterstraal met de muis en houd links ingedrukt. Zoek en draag het slachtoffer zelf naar de opvang wanneer de beschermde spelconditie toegang toestaat. Rond af via nasmeulcontrole/overdracht. De afloop blijft bewaard.

Vervolg met **Sporen in de as** in hetzelfde afgekoelde pand. Richt op een spoor: F fotografeert, E legt vast. Spreek Saar en Lars, vergelijk hun bronnen, bezoek de sporenbalie in het bureau en gebruik R voor het onderzoeksbord en rapport. Een tegenstrijdige verklaring alleen bewijst geen schuld. Onderbouwd, onvolledig en onjuist afsluiten hebben verschillende gevolgen.

**Academie · lessen** biedt **Les 1 · Basisdienst op straat**, **Les 2 · Arrestant en rapportage** en **Les 3 · Brandweer basisinzet**. Bij registratieafdrukken positioneer je met muis of A/D en houd je links of Spatie ingedrukt terwijl de doelzone uitlijnt. Herhaal onscherpe opnamen.

**Vrije politiedienst** biedt interactieve overlast- en verkeersmeldingen; **Vrije brandweerdienst** biedt buitenbranden. Neem uitrusting/PBM, meld je aan en open met R de meldkamer. Aannemen, doorgeven en verlopen blijven mogelijk. Varianten verschillen in bronnen/omstandigheden; na je rapport of overdracht kun je verder surveilleren.

| Bediening | Actie |
|---|---|
| WASD / Shift | Lopen of rijden / sprinten |
| Muis | Camera draaien; waterstraal richten |
| E / Spatie | Interactie, in-/uitstappen / remmen |
| Q | Pion of slangsegment op gerichte grond plaatsen |
| Linkermuisknop | Gerichte waterstraal; registratieafdruk vasthouden |
| F | Tijdens brandonderzoek het gerichte spoor fotograferen |
| R | Meldkamer, inzetplan of onderzoeksbord volgens actieve zaak |
| H | Sirene tijdens voertuiggebruik |
| M / Esc | Wijkkaart en hulp / pauze |
| F5 / F9 | Opslaan / laatste opslag laden |

Saves gebruiken schema 7; oudere ondersteunde schema’s 1–6 worden gevalideerd en gemigreerd. Nieuwe dienst wist een bestaande opslag niet; opslaan vervangt haar. Beschadigde/onbekende saves worden geweigerd, met gevalideerde herstelkopie waar beschikbaar. Vrije dienst en lessen bewaren behaalde campagne-/lesresultaten; **Nieuwe campagne** begint opnieuw. Audio-instellingen blijven afzonderlijk bewaard. Alle 40 originele WAV-bestanden zijn lokaal aanwezig: muziek, adaptieve lagen, omgevingsgeluid en handelingen werken offline.

## Bron en bewijs

Godot **4.7.2 stable**, GDScript en native macOS/Windows-export. Originele Blender/GLB-assets, PBR-maps en gerigde figuren zijn meegeleverd; de wijk en personages blijven visueel in ontwikkeling. Geen betaalde assets of runtimeplugins nodig.

- [Installeren, bouwen en testgrenzen](docs/BUILDING.md)
- [Conceptoplevering en beperkingen](docs/CONCEPT.md)
- [Uitvoeringsplan](docs/EXECUTION_PLAN.md)
- [Assetherkomst en licenties](docs/LICENSES.md)

Gebruik uitsluitend concrete logs en provenance van de betreffende build voor platformclaims. Automatische/headless controles en geïsoleerde beeldproeven vervangen geen volledige menselijke playthrough.
