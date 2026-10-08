# Issue #1 — uitvoering

Bron: [WORKORDER.md](WORKORDER.md). Werkmodus: werkbon met expliciet autonoom mandaat.

| Stap | Speelbare uitkomst | Poort |
|---|---|---|
| M0 | Menu → lopen, camera, uitrusting/radio → save/load | Import, runtime, beide native exports + CI/native smoke |
| M1 | Wijk, voertuigen, NPC’s, meldkamer, vijf minuten dienst | Rij-/spelertransities en playthrough |
| M2 | Academie politie, verkeerszaak, arrestant/PV | Keuzes, procedure, rapportscore |
| M3 | Woningbrand, gerichte blussing, water, redding | Brand/tijd/veiligheid, blijvende incidentstaat |
| M4 | Onderzoek van dezelfde brand, twee verhoren, hypotheses | Herkomst bewijs, tegenstrijdigheid, verschillende uitkomsten |
| M5 | Drie vrije incidentfamilies, campagne/academie, distributie | Volledige 20–30 minuten playthrough, exacte-head CI/review, beide ZIP’s |

Eerst M0 exporteren en werkelijk starten; daarna pas inhoud uitbreiden. Eén implementatie-PR tegelijk. Geen andere repositories wijzigen. Code, assets en scenario’s blijven origineel/procedureel. Compatibility is de voorlopige draagbare renderer; doelhardwarebenchmark blijft open. Save-schema 2 met migratie van schema 1, platformcorrect `user://`, tijdelijk bestand plus gevalideerde herstelkopie en validatie bij laden. Scripts voor wereld/besturing, staat en UI hebben afzonderlijk ownership; CI blijft deterministisch.

Bootstrap: centrale README en aangewezen uitvoeringsdocumenten gelezen op Tuned.pixel-revisie `882ba834d08697aee4b09ed161a062f5cc7b4659`. Geen aanvullende lokale ADR’s/AGENTS aanwezig. Godot 4.7.2 upstream bevestigd; lokale toolchain wordt taakgebonden in `/tmp` geplaatst. Hoofdbranch was schoon; Issue #1 Ready en geen actieve PR’s. Privé build-/PR-publicatie volgt de expliciete werkbon; geen betaalde assets/diensten.

Status: M0-code en platformpoort voltooid op `545bfa5`; onafhankelijke review **Approve**, [exacte-head CI](https://github.com/kevindraai/scene112/actions/runs/37761334565) groen inclusief Linux-graphics, Windows x64, Mac arm64 en hetzelfde Universal2-archief op Intel. [PR #2](https://github.com/kevindraai/scene112/pull/2) is gemerged als `4fe5b3b`; main-CI is gecontroleerd: Linux/Windows groen, Mac-bootstrap stuitte op gedeelde ongeauthenticeerde GitHub API-quota; één omgevingsretry loopt. De duurzame read-only metadata-tokenfix gaat met M1 mee. De gebruiker heeft na de automatische approval-rejectie expliciet M0 en volgende merges toegestaan, telkens na groene onafhankelijke review en exacte-head CI. M1 wordt lokaal uitgevoerd en gaat na de main-controle naar één eigen implementatie-PR. macOS/Windows-hardwaregameplay is nog niet aangetoond. Alleen exports of headless smoke tellen niet als grafisch speelbaar bewijs. M1: lokale vijfminutendienst geslaagd met zeven afhandelingen/geen verlopen meldingen; beide lokale native exports/validators groen, onafhankelijke review Approve. M1 voegt rijbare voertuigen, veilige spelertransities, zes buurtbewoners, radiolevenscyclus en schema-2 saves toe (schema 1 wordt gemigreerd). Verificatie: fysieke rij-/collision-/exitchecks, deterministische dispatch, gecombineerde dienstautomatisering en beide nieuwe native exports. Volgende acties: M1 integratie/review/exports; main controleren en M1-PR/CI, daarna M2–M5.
