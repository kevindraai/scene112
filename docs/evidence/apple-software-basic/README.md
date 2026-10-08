# Apple Software Renderer: afgebakende basic-kandidaat

Buiten canonical: `/tmp/scene112-apple-basic-prep`. `handoff/apple-software-basic.patch` wijzigt uitsluitend StreetAtmosphere en de bestaande GraphicsValidation-verwachtingen. Runtime-assets, oorspronkelijke PBR-maps/materialen, glTF-bronnen, 18-bone rigs/vier clips, physics/colliders, app/input/save/CI blijven ongewijzigd. Root/D moeten deze kandidaat reviewen en op exact native PR-head beproeven; **Apple/Mac-succes of <240s is niet aangetoond**.

Production gate: actual renderer `gl_compatibility`, herkenbare naam die begint met `Apple Software Renderer`, bestaande software-classificatie, en echte niet-headless display. Alleen dan geldt effectieve `software_basic`: **werkelijke 3D-scale .25 en bestaande automatische mesh-LOD threshold 8**. De gekozen gebruikersvoorkeur blijft staan. llvmpipe/softpipe behouden `.5`, oorspronkelijke LOD en `software_portable`; hardware, Forward+/Mobile en onbekende adapters behouden hun bestaande gedrag. Sky 32, portable PBR, 72 rain/de bestaande lampen, geen software-reflectie/shadow/SSAO/glow zijn dezelfde eerder aanvaarde softwaregrenzen. De variant slaat viewport mode/scale/LOD op en herstelt alle drie; er is geen backend-spoof of productie-fixturehook.

GraphicsValidation houdt zijn 200 bestaande gameplaycontroles: echte >10m loop, >20m rijden, sturen/reverse/brake/uitstappen, facade/roof-springarm, oorspronkelijke import/PBR/rigs, pauze, weer en save/load. Alleen de softwareverwachting in de balanced- en high-branches wordt conditioneel; basic vereist de echte `.25`/LOD 8 getters, overig softwareprofiel vereist `.5`. Geen timeout verlengd, posecontrole geschrapt, actor verstopt of PBR naar unshaded omgezet.

## Werkelijke maatvoering en geometrie

`tests/viewport_size_probe.gd` tekent een tijdelijke, onafhankelijke diagnostische quad met binair gecodeerde shader-`VIEWPORT_SIZE` (kalibratiezwart/wit gecontroleerd). Dit verandert geen productmateriaal. Readback op echte Compatibility/llvmpipe:

| 3D-scale getter | Shader-renderbuffer | Uitvoertexture |
|---|---|---|
| 1.0 | 1280×720 | 1280×720 |
| .5 | 640×360 | 1280×720 |
| .25 | 320×180 | 1280×720 |

`.25` heeft hier dus werkelijk een kwart zoveel 3D-pixels als `.5`; UI/output blijft 1280×720. De publieke viewporttexture is de uitvoer, dus geen geldig bewijs van de interne 3D-afmeting op zichzelf. Het diagnosebeeld leest een engine-uniform in plaats van afmetingen uit de scaler te berekenen. Native Apple moet dezelfde diagnose nog bevestigen.

De echte geladen scene bevat **9 oorspronkelijke GLB-paden, 10 rigs van 18 bones, 129 collision objects, 89 LOD-bearing surfaces met 403 bestaande LOD-levels**. Bronarrays blijven 226.040 vertices/795.432 indices in 343 unieke scene-meshes/405 surfaces, inclusief bestaande eenvoudige physics/decor-meshes. RenderingServer levert die bron-/LOD-data; daadwerkelijke viewport render-info bevestigt gekozen primitives. Geen geometrie-export/rebuild voor deze kandidaat.

`tests/lod_scale_probe.gd`: identieke statische street-camera, fysica/animatie via de normale app bevroren, 8 settleframes en 24 echte process-frame samples per as. Geen schermrecorder/native meetclaim. Real llvmpipe:

| Scale / LOD | Primitives mediaan | Draws | Frameinterval p50 / p95 |
|---|---:|---:|---:|
| .5 / 1 | 52.776 | 102 | 57,67 / 68,99ms |
| .25 / 1 | 52.776 | 102 | 49,54 / 58,93ms |
| .25 / 8 | 33.688 | 102 | 30,41 / 36,61ms |
| .25 / 16 | 30.952 | 102 | 29,40 / 36,85ms |

LOD 8 reduceert werkelijk primitives, met beperkte extra winst van16; daarom 8 als begrensde kandidaat. Dit profiel behoudt oorspronkelijke geometrie voor botsingen en bewaart de oorspronkelijke PBR/Skin/UV-data. De metingen onderscheiden fragment-/pixelkosten en geometriekosten op déze Linux backend. Ze voorspellen geen Apple-frametime.

## Bewijs en overdracht

- `validation/classification.log`: 18 begrensde classificatiefixtures; uitsluitend herkenbaar Apple softwareGL wordt basic.
- `validation/viewport-restore.log`: echte setters/getters herstellen mode,scale,LOD naar oorspronkelijk1.0/1.0. Headless helperfixture, geen GPU-claim.
- `validation/viewport-size-readback.{log,json}`: werkelijk gekalibreerde shader-readback, originele renderernaam.
- `validation/lod-scale.{log,json}` plus4 PNG: geïsoleerde schaal/LOD-assen met echte render-info.
- `validation/baseline-runtime.log`: daadwerkelijke ongedwongen llvmpipe-software baseline. `validation/apple-fixture-runtime.log`: **expliciet geforceerd Apple-profiel op echte llvmpipe**, nooit Apple-backend of native-timingcredit. Adaptergetters/backendlogs blijven de echte naam tonen. Beide voeren dezelfde volledige validator uit.
- JSON/PNG's uit de twee full loops staan in de taakgebonden XDG-Scene112 folders en worden met scope meegekopieerd naar `validation/evidence/`.
- `validation/source-snapshot.json` en handoff SHA256SUMS bewijzen baselinebron en ongewijzigde assets. Header/diagnostics scheiden requested/effective quality.

De 8c-native Intel-sample is echte primaire aanleiding: main-thread fragment-interpreter/scanlinewerk domineert een aanzienlijk deel van die sampling; `.5` kreeg daar 240 s timeout. Dit is een inference uit de sample, geen exacte GPU-/UI-kostenverdeling. Native1410 Mobile-hang en Compat-timeout blijven negatieve bewijsstukken; deze kandidaat herclassificeert ze niet.

Een eerste read-only collector had onjuiste render-infoargumenten en is begrensd gestopt; een eerste forced fixture verving de atmosphere-node en gaf stale-high-assertion/sky-cleanupfouten. Beide ontwikkelfouten zijn gearchiveerd. Finale fixture zet alleen het profiel op de bestaande node. Alleen actuele schone logs gelden. De vorige baseline kende kort overlappende mislukte instrumentatie bij startup; die is niet als definitieve performancebaseline gebruikt.

Kopieer alleen `handoff/scripts` of pas de reviewbare patch toe. Neem `handoff/.gdignore` niet over in product-scripts. Tests zijn aparte tools; de productie herkent de echte adapter en bevat geen force-environmentvariabele. Pure klasfixtures, default-vs-forced full loop en binary readback moeten onderscheiden blijven. Handoff is eigen projectbron onder de bestaande private/proprietary licentie. Het toepassen van de uiteindelijke pipeline/head/nativepoorten is Root/D-ownership.

Primaire API: [Viewport scaling/LOD](https://docs.godotengine.org/en/4.7/classes/class_viewport.html), [RenderingServer mesh/render-info](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html), [spatial shader VIEWPORT_SIZE](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html).

Finale looptests: beide **200/200 groen**, actuele echte adapter llvmpipe. Fresh baseline high-rain stage23.66s, forced basic22.82s: geen betrouwbare volledige-loop snelheidwinst; de eerdere46→25 vergelijking is door startup/cache/overlap vervallen. De gescheiden statische assen bewijzen de kleinere buffer en daadwerkelijk lagere primitives, niet een gehaalde native240s-poort. Alle finale logs sluiten clean af; software-classificatie18 fixtures en echte setter/restore-API groen. Geen canonical wijziging.
