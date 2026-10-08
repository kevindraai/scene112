# SCÈNE 112 | Master workorder

> Status: **Authorized / Ready for implementation**  
> Datum: 2026-10-08  
> Repository: kevindraai/scene112 (private)  
> Opdrachtgever: repository-eigenaar  
> Uitvoerend team: Codex, met GPT-6 (Sol, High indien beschikbaar) als regisseur/architect.

## 0. Executive mandate

**Bouw een echt speelbare, Nederlandstalige 3D-singleplayergame voor macOS én Windows.** SCÈNE 112 combineert een levende Nederlandse stad, vrije politie- en brandweerdiensten, een interactieve academie, recherche/verhoren, processen-verbaal en brandonderzoek met een doorlopende verhaallijn. Doelgroep: 14+.

Dit is een uitvoeringsopdracht, geen brainstorm, ontwerpstudie, mock-up of verzameling minigames. Begin met werkende gameplay. Leg alleen besluiten vast die nodig zijn om te bouwen en te testen. Rapporteer verifieerbare resultaten; claim nooit speelbaarheid op een platform dat niet getest is.

**Autonomie:** neem binnen deze workorder zelfstandig product-, architectuur- en UX-beslissingen. Geen stilstand bij niet-essentiële vragen. Werk systematisch aan opeenvolgende speelbare builds. Werk uitsluitend in dit repository; raak ClubSolution, ExitLane, Tuned Pixel en hun CI niet aan. Publicatie buiten deze private repo, wijziging van betaalde diensten of gebruik van externe betaalde assets vereist aparte toestemming.

## 1. Productvisie en spelregels

De speler moet het gevoel hebben **een echte dienst te draaien** en tegelijk een spannend onderzoek te kunnen voeren. Geen GTA-kloon, geen administratieve spreadsheet en geen leeg decor. Echte verplaatsing, handelingen, waarneming, risico, keuze en consequenties vormen de gameplay.

Vier rollen in één gedeelde wereld:

- **Politieagent:** briefing, uitrusting, surveillance, meldingen, verkeersincidenten, personen aanspreken, staandehouden/aanhouden waar passend, verdachten verwerken en PV's opstellen.
- **Rechercheur:** plaats-delictonderzoek, sporen en getuigen, hypotheses, videobeelden, verhoren, onderzoeksbord en dossier.
- **Brandweerman/-vrouw:** kazerne, alarmering, uitruk, verkennen, waterwinning, slangen, binnenaanval waar verantwoord, redding, brandbestrijding en eenvoudige THV.
- **Brandonderzoeker:** ontstaansgebied en hypothesen onderzoeken, brand-/rookpatronen interpreteren, aanwijzingen vastleggen en brandonderzoeksrapport opstellen; onderscheid met strafrechtelijke forensische opsporing behouden.

Een incident is een **persistente gebeurtenis** met verschillende perspectieven. Wat tijdens de brandweerfase gebeurt, beïnvloedt wat later aantoonbaar onderzocht kan worden. Niet elk incident is een misdrijf; niet elk verhoor eindigt in een bekentenis. Correct en zorgvuldig optreden is ook succes.

### Kernlussen

1. **Vrije dienst:** start op bureau/kazerne, neem uitrusting mee, ga zelf de stad in, ontvang of ontdek een melding, rij erheen, handel haar interactief af, rapporteer en vervolg je dienst.
2. **Onderzoekszaak:** incident → locatieonderzoek → bewijs/getuigen → verhoor → controleerbare hypothese → PV/dossier → onderbouwde afsluiting.
3. **Brandweer:** alarmering → uitruk → risicobeoordeling → tactische keuzes en middelen → actieve bestrijding/redding → overdracht/evaluatie → mogelijk later onderzoek.
4. **Academie:** begeleide demonstratie → hands-on uitvoering → zelfstandig oefenen → objectieve beoordeling → toepassen in de stad.

## 2. Technische keuzes

- **Engine:** Godot **4.7.2 stable**, standard build; GDScript als standaardtaal. Upgrade van de engine alleen na apart werkende cross-platform export.
- **Graphics:** gestileerd en samenhangend 3D, third-person met inspectiecamera/close-up waar relevant. Kies Forward+/Mobile/Compatibility na een korte benchmark op doelhardware; draagbare prestaties gaan boven fotorealisme.
- **Doelplatforms:** macOS Universal 2 (Intel x86_64 + Apple Silicon arm64) en Windows 10/11 x86_64. Desktop native, **geen webwrapper**. Muis + toetsenbord als eerste input; gamepad optioneel, architectuur wel voorbereid.
- **Assets:** originele zelfgemaakte, procedureel gegenereerde of aantoonbaar juist gelicentieerde assets. Leg herkomst en licentie/attributie vast. Geen CSI-, GTA-, brandweer- of politiemerken namaken; Nederlandse sfeer wel behouden.
- **Repo:** nette Godot-structuur; scenes/, scripts/, data/, assets/, tests/, docs/, .github/workflows/. Houd bronbestanden in Git, grote bronassets eventueel in Git LFS, gegenereerde imports/builds buiten Git.
- **Duurzame staat:** versieer save-schema, bewaar campagneprogressie, incidentstatus, inventory/evidence, spelerpositie en voertuigen waar zinvol. Voorzie nieuwe game, doorgaan, handmatig herstarten en veilige fallbacks bij corruptie.
- **Narrative:** data-driven scenario's/quests/dialogen waar haalbaar, zodat nieuwe incidenten zonder duplicatie van complete scenes toegevoegd kunnen worden.
- **Belangrijk:** een streaming/open-world-techniek is een implementatieoptie, geen excuus om eerst een ingewikkelde wereldengine te bouwen. Voor v0.1 volstaat één continu speelbaar, compact gebied.

## 3. Levend Nederlands stadsdeel

Bouw eerst één herkenbare wijk/stadszone met een politiebureau, brandweerkazerne, rijtjeshuizen, kruising/hoofdweg, winkel/plein, kleine industriestrook en verschillende betreedbare locaties. De speler kan zonder missiewissel te voet of met een voertuig naar de meeste activiteiten rijden.

Het gebied bevat doelgerichte landmarks, voetgangers/NPC's, beperkt functionerend verkeer, verlichting/dagritme, verkeer dat kan reageren op blokkades en contextueel geluid. Zorg voor echte interactie: deuren, objecten, bewijspunten, voertuigen, gesprekken en incidenten. Maak liever een compacte geloofwaardige buurt dan tientallen lege straten. Gebruik NPC-routines en incident-spawning spaarzaam en deterministisch testbaar.

Incidenten leven los van een actieve missie: ze kennen ontstaan, melding, beschikbaarheid, urgentie, acceptatie, afhandeling, verlopen/overdracht en nasleep. De wereld hoeft niet te bevriezen als de speler een melding niet aanneemt. Geen oneindige spamlijst van incidenten; capaciteit en rustmomenten tellen mee.

## 4. Academie: tutorial als onderdeel van de wereld

De tutorial is een **interactieve academie in Train Simulator-stijl**: een begeleider geeft een korte uitleg, toont wat relevant is, laat de speler de handeling werkelijk uitvoeren en toetst resultaat. Modus: begeleid, oefenen, zelfstandig. De lessen blijven herhaalbaar.

De eerste speelbare versie omvat minimaal:

1. **Politie, basisdienst:** bewegen/kijken, bureau, uitrusting, radio/meldkamer, in- en uitstappen, rijden, verkeersincident afzetten, spreken met betrokkenen en afhandelen.
2. **Politie, arrestant en rapportage:** rechtmatige interactie op hoofdlijnen, proportionele keuzes, cautie op relevant moment, procedureel passende verwerking, dactyloscopische opname als hands-on minitaak en een PV met eigen waarnemingen, verklaringen en tijdlijn.
3. **Brandweer, basisinzet:** materieel bekijken, PBM, uitruk, verkennen, waterwinning/slang leggen, gerichte blussing en slachtofferveiligheid.

Maak ook oefenplaatsen voor bewijsvergaring, verhoor en brandonderzoek, zelfs wanneer hun volledige lessen pas na de eerste verticale slice volgen. Tutorials mogen niet neerkomen op alleen tekst of een klikbare checklist.

## 5. Politiesysteem, verhoor en PV

**Politiehandelingen:** identificeren, aanspreken/staandehouden waar de casus dit rechtvaardigt, controleren, aanhouden, vervoer, bureau-intake, verklaringen, feiten vastleggen. Simuleer de kern zorgvuldig zonder te claimen dat het spel juridisch opleidt. Raadpleeg officiële openbare Politieacademie-, politie- en wetgevingsbronnen; documenteer simplificaties.

**Dactyloscopie:** een concrete procedurele interactie waarbij de speler uitleg, positionering en registratie uitvoert; resultaat beïnvloedt de bruikbaarheid van een spoor. Houd onderscheid tussen identificatie-/registratieafdrukken en dactyloscopisch spooronderzoek.

**Verhoorsysteem:** meer dan een dialoogboom. NPC's hebben eigen informatie, belangen, waargenomen feiten en mogelijke tegenstrijdigheden. De speler kiest een aanpak, stelt open en gerichte vragen, kan doorvragen en selectief bewijs voorhouden. Verkeerde timing/suggestieve vraagstelling kan het dossier schaden. Zwijgrecht, cautie en rechtsbijstand zijn afhankelijk van het scenario procedureel verankerd. Minimaal twee uitgewerkte ondervraagbare personages en één casus met een echte tegenstrijdigheid. Een bekentenis mag nooit de enige winnende uitkomst zijn.

**Proces-verbaal:** maak een Nederlandstalige interactieve PV-editor waarin eigen waarnemingen, informatie van anderen, chronologie, verrichte handelingen, bewijsverwijzingen en conclusies zorgvuldig worden onderscheiden. Speler kiest en ordent inhoud, geen uren typen. Scoreer objectiviteit, volledigheid, proportionaliteit en consistentie. Inhoudelijk onjuist rapporteren heeft gevolgen voor de zaak, maar laat herstellen waar logisch.

**Recherche:** bewijsstukken hebben bron, tijd, vindplaats en relevante verbanden; getuigenverklaringen kunnen afwijken; speler koppelt aanwijzingen op een onderzoeksbord, test hypotheses en neemt geen conclusies aan zonder onderbouwing. Vermijd magische 'scan om de dader te vinden'-mechanieken.

## 6. Brandweer en brandonderzoek

Maak een versimpelde maar echte gameplay-simulatie: brandhaarden, branduitbreiding, rook, verslechterende zichtbaarheid, brandbare objecten, beperkt blusmiddel/watertoevoer, slachtoffers met tijdsdruk en gevolgen van tactische keuzes. Bied interacties met slang/straalpijp, blusrichting, waterbron, deuren, zoeken en redden. Een brand mag niet verdwijnen door één globale 'blus'-knop.

De brandweerrol draait om verkennen, beslissen en veilig optreden, niet om roekeloos 'snelst alle vlammen uit'. Maak binnenaanvallen uitsluitend speelbaar binnen een verantwoord gesimuleerd scenario en laat slechte risicobeoordeling nadelig uitwerken.

Brandonderzoek gebruikt de blijvende incidentstaat: sporen die overbleven, tijdlijn, plaats van ontstaan, mogelijke warmtebronnen, elektrische installatie, getuigen en plausibele oorzaken. De speler kiest hypotheses en maakt een onderbouwd rapport. Team Brandonderzoek en strafrechtelijke forensische opsporing houden een eigen rol; vermoedelijke opzettelijke brandstichting kan de recherchelijn activeren.

## 7. Speelbare campagne voor eerste release

**Zaak 1: De eerste dienst.** Start op het bureau, doe kort academiewerk, rij op surveillance, handel een verkeersincident af (afzetten, waarnemen, spreken, eenvoudige afhandeling/PV). Zowel juiste als onjuiste aanpak krijgen consequenties.

**Zaak 2: De woningbrand.** Start op kazerne, ontvang alarmering, rij uit, verken, kies prioriteiten, leg af, blus en red slachtoffer(s). Brand- en rookontwikkeling reageren op acties/tijd. Evalueer afloop en bewaar de relevante incidentstaat.

**Zaak 3: Sporen in de as.** Keer terug naar hetzelfde pand, dit keer voor brandonderzoek en eventueel recherche. Verzamel aanwijzingen, onderzoek alternatieve oorzaken, ondervraag minstens twee personen, leg tegenstrijdigheden naast bewijs en rond een onderzoeksrapport/PV af. Een juiste onderbouwde uitkomst, een onvolledige uitkomst en een aantoonbaar verkeerde conclusie zijn mogelijk.

De zaak bevat een compact narratief verband en heeft een afgerond einde in v0.1. Missies mogen lineair starten, maar vinden binnen dezelfde vrije wereld plaats. Geen triviale 'ga naar marker en druk E' als primaire uitdaging.

## 8. Vrije dienst: harde eis

Naast de campagne bevat v0.1 een vrije dienst. De speler start op het bureau of de kazerne en kan zonder actieve campagne vrij bewegen, rijden, mensen ontmoeten en meldingen oppakken.

Minimaal drie herhaalbare maar gevarieerde incidentfamilies: (a) overlast/openbare orde, (b) verkeersongeval, (c) buitenbrand of kleine gebouwbrand. Varianten ontstaan door NPC's, locaties, risicofactoren, keuze en resultaat. Meldkamer laat aannemen, doorgeven of aflopen toe. Na afhandeling kan de speler verder surveilleren. Geen lege free roam zonder volwaardige interactie.

## 9. UX, spelgevoel en toegankelijkheid

- Nederlandstalige UI, ondertiteling voor belangrijke gesprekken en radio, consistente politiesignalen en herkenbare maar fictieve vormgeving.
- Een fatsoenlijk hoofdmenu, nieuwe game/doorgaan, vrij dienstverband, campagne, academie, instellingen, pauze, opnieuw proberen en hulp.
- Third-person lopen, sprinten, kijken, interactie, in/uit voertuig, rijbesturing, camera die niet door muren klipt, korte interactieprompts, heldere missie-/objectiefstatus.
- In-game kaart/navigatie of duidelijke route-indicatie, radio/meldkamer, dossier, inventory/uitrusting en beoordelingsscherm.
- Aansprekende geluiden en visuele feedback; geen eindeloze placeholders als definitieve v0.1. Spanning voor 14+, geen gratuit expliciet geweld.
- Wanneer de speler fouten maakt: begrijpelijke feedback, niet alleen plotselinge game-over. Beloon precisie, zorgvuldigheid, effectiviteit en niet-schadelijke oplossingen.

## 10. Native Mac en Windows: onverhandelbaar

**Voor ieder speelbaar ijkpunt moeten minimaal een macOS-build en Windows-build exporteerbaar zijn.** Voor de v0.1-release zijn twee artefacten verplicht:

- Scene112-macOS-universal.zip (bevat een .app voor arm64 en x86_64).
- Scene112-Windows-x64.zip (bevat een standalone .exe + benodigde bestanden).

Gebruik Godot 4.7.2 bijpassende exporttemplates, expliciete export_presets.cfg en herhaalbare GitHub Actions-builds. Geen browsergame, Docker-desktopwrapper of noodzaak om Godot lokaal te installeren. Maak eigen gebruikersbestanden platformcorrect. Gebruik op macOS voor de private testversie desnoods ad-hoc signing; notarization en Developer ID-signing worden pas afgedwongen zodra daartoe credentials en releasewens beschikbaar zijn. Leg duidelijk uit hoe gebruikers een nog niet genotariseerde private build starten.

Valideer op GitHub-hosted runners onder Linux (headless/import/tests) en de relevante macOS- en Windows-omgevingen. Controleer Mac-architecturen, bundle-structuur en uitvoerrechten. Voer waar mogelijk native launch smoke tests uit. **Een geslaagde export ≠ bewezen grafisch speelbaar**: test daadwerkelijk gameplay op echte desktophardware zodra beschikbaar en leg ontbrekend bewijs expliciet vast.

Een bestand mag pas als 'getest op macOS/Windows' worden gemarkeerd wanneer er passende testresultaten zijn, niet alleen wanneer twee ZIP-bestanden bestaan. Houd geen release tegen wegens ontbrekende betaalde Apple-credentials voor een private testbuild, maar verzwijg het verschil ook niet.

## 11. CI, issues en ontwikkeldiscipline

Gebruik één implementatie-PR tegelijk, met **één gebruikersuitkomst per PR**. Voorkom aparte PR's voor elke scène, rapportoptie of een paar regels documentatie. Parallel onderzoek en voorbereiden mag, maar geen conflicterende implementatie-PR's.

Op exact de PR-head moeten noodzakelijke checks slagen vóór merge. Na merge controleer je main. Bouw stappen op in documentatie/lint/import/unit/headless-smoke/export/native-smoke; voorkom zware exports bij uitsluitend docswijzigingen. Houd de checks snel en betrouwbaar en archiveer mislukte logs.

Test incidentstatus, spelertransities, bewijslogica, verhoorvertakkingen, scoring, saves, replay van scenario's en regressies. Voeg deterministische seeds toe voor incidenten waar handig. Voer daarnaast echte interactieve playthroughs uit en toon verifieerbaar bewijs (screenshots/video, log en stappen) waar mogelijk.

**Geen governance-molen:** maak alleen echte productissues, houd status en open punten kort. Werkorder blijft de productbron; code, tests en release zijn de deliverables. Documenteer gamebediening, bouwen, licenties en ontwikkelstart.

## 12. Mijlpalen en volgorde

**M0: Ontwikkelbasis (zo snel mogelijk)**
- Godot-project met hoofdmenu, minimale speelbare 3D-locatie, bestuurbaar personage, camera, interactie-object en een functioneel save-slot.
- Eerste reproduceerbare macOS Universal- en Windows x64-export in CI, desnoods met voorlopig landschap. Dit is de eerste harde platformpoort.

**M1: De straat op**
- Compact stadsdeel, politiebureau, kazerne, politieauto en brandweervoertuig, instappen/rijden, enkele levende NPC's en basismeldkamer.
- Vanaf menu echt vrij kunnen rondlopen en rijden; demonstrabele gameplayloop van minstens vijf minuten.

**M2: Politiewerk**
- Academieles 1 en 2; onderzoek/verslaglegging; volwaardig speelbare casus 'De eerste dienst'.

**M3: Brandweer**
- Academieles 3; rook, brandverspreiding, slangen, water en redding; volwaardig speelbare 'De woningbrand'.

**M4: Onderzoek en keten**
- Bestaande brand staat als onderzoekslocatie; bewijssysteem, hypotheses, brandonderzoek, twee verhoorbare NPC's, PV en 'Sporen in de as'.

**M5: v0.1.0 vertical slice**
- Vrije dienst met drie incidentfamilies, campagne, academie, save/load, polish, geluid, bediening, scoring, tests en beide native distributies; tag en release.

**Voor later, niet blokkeren voor v0.1:** grotere stad, volledige carrièretakken, meer voertuigen, diepgaande THV, aanvullende forensische labs, tientallen scenario's, lokale spraakherkenning en multiplayer. Architectuur uitbreidbaar, maar geen lege abstrahering vooruit.

## 13. Definitie van 'speelbaar' en acceptatie

v0.1.0 is pas gereed als een nieuwe speler zonder engine of ontwikkeltools de game kan openen, bewegen, voertuig rijden, minstens drie academielessen uitvoeren, een politiemelding afhandelen, een brandweerincident spelen, bewijs verzamelen, twee personen verhoren, een PV/rapport afronden, de drie verbonden scenario's afronden, een vrije dienst met herhaalbare meldingen spelen en voortgang opslaan/laden.

De hoofdscenario's hebben observeerbare winst-/verlies- of kwaliteitscondities; keuzes doen ertoe. Streef naar minimaal 20-30 minuten betekenisvolle gameplay zonder dat de speler alleen tekstvensters doorloopt. Toets de ervaring met echte playthroughs; leg vast welke onderdelen nog simplificaties zijn.

Beide ZIP-bestanden zijn onderdeel van dezelfde GitHub Release en hebben installatie-instructies, controleerbare build herkomst, teststatus en bekende beperkingen. Werkende builds zonder voldoende spelinhoud zijn alleen tussenmijlpalen, niet v0.1.0.

## 14. Concrete eerste uitvoeringsopdracht voor Codex

1. Lees dit document en inspecteer de bestaande repository/branches/issues. **Verwijder niets** en neem bestaande veranderingen mee. Maak een beknopt uitvoeringsplan in maximaal één pagina.
2. Zet Godot 4.7.2-project en minimaal een nette README, passende .gitignore, licentieregister en developer-instructies op. Kies eigen heldere architectuur zonder onnodige frameworks.
3. Implementeer onmiddellijk de eerste loop: 3D-wijkhoek, personage, camera, bewegen, interactie, simpel menu, scèneovergang en één save/load-proef.
4. Maak een CI-workflow die de Godot-import valideert en **macOS Universal 2 plus Windows x64** exporteert. Upload artifacts voor iedere succesvolle relevante main-build en maak een testbuild op beide platforms zichtbaar.
5. Zorg voor een verifieerbare playthrough, controleer of de game feitelijk gestart kan worden en los gebreken op vóór uitbreiding.
6. Ga dan zelfstandig door met M1, M2, M3, M4 en M5. Herprioriteer alleen op basis van duidelijke gameplay-/platformproblemen; behoud de productdoelen.

Gebruik agents gericht: game design/recherche/brandweer als afgebakend onderzoek, Godot-implementatie en onafhankelijke test/review. GPT-6 Sol (High waar beschikbaar) bewaakt de samenhang. Vraag niet om toestemming voor normale technische keuzes; leg wel werkelijk onoplosbare blokkades kort vast en werk aan de volgende onafhankelijke taak.

**Eindrapport:** links naar commits/PR's, exact release-URL, installatiestappen voor Mac en Windows, echte testbewijzen, gameplay die zichtbaar werkt, niet-afgeronde features en bekende beperkingen. Claim geen voltooiing voor zaken die alleen zijn gespecificeerd.

## 15. Officiële technische referenties

- Godot 4.7.2 stable: https://godotengine.org/download/archive/4.7.2-stable/
- Godot export: https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html
- Godot macOS-export: https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html
- Godot Windows-export: https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_windows.html
- NIPV (brandweeronderwijs/onderzoek): https://nipv.nl/
- Politieacademie: https://www.politieacademie.nl/
- Overheid.nl: https://wetten.overheid.nl/

**Startcriterium:** dit document is de werkorder. Begin met M0 en lever werkende code plus een testbuild voor beide besturingssystemen; maak geen nieuwe designstudie als vervanging van de implementatie.
