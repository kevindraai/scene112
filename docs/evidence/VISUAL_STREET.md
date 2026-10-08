# Speelbare Noorderkade-straat

Uitvoering van de [visuele kwaliteitsrichtlijn](https://github.com/kevindraai/scene112/issues/1#issuecomment-6059218603) en [parallelle productieopdracht](https://github.com/kevindraai/scene112/issues/1#issuecomment-6059677526), aansluitend op de gemergede M2. De bestaande wijk blijft 144×144 meter. De straat heeft een echte verbinding met de hoofdweg; huisposities, campagne, academie, besturing en saves blijven bruikbaar.

Negen originele GLBs worden werkelijk in de spelwereld gebruikt: Nederlandse rijwoning, bank, lamp, fiets, vertakte straatboom, politieauto, tankautospuit, agent en bewoner. Editable Blender-bronnen, herbouwscripts en eigen albedo/normal/roughness-maps zijn behouden. Voertuigen hebben gebogen carrosserie, cabine, livery, verlichting en afzonderlijke wielassen; personages gebruiken een eigen 18-bone skin met vier animaties. De boom gebruikt gemaskerde individuele bladeren. Statische onderdelen delen meshes/textures en Godot-import-LOD; afstandsculling begrenst bomen/personages. Bron- en bewijsbestanden zijn van runtime-import uitgesloten.

Overdag, schemer en lichte regen hebben eigen zon/hemel/ambiance, schaduwen, begrensde straatlampen, één lokale reflection probe en regen/VFX. Portable gebruikt minder lokale lichten en twee zoncascades; balanced/high voegen passende effecten toe. SSR wordt alleen in high/rain met werkelijk Forward+ gebruikt. Eigen positionele regen-audio volgt het weer, klinkt zachter binnen en vervangt buiten de vogelambiance; weerswissels herstarten de muziekscore niet. Wereldweer/beeldprofiel worden via save-schema 4 bewaard; oudere saves migreren naar veilige dag/portable-instellingen.

## Onafhankelijke bron- en gameplaycontrole

Godot 4.7.2 official, Linux X11/Xvfb, OpenGL 4.5 Mesa 25.0.7 llvmpipe, 1280×720. Dit is een software-renderende omgeving.

- 195 volledige grafische straatchecks, vier echte screenshots (day/dusk/rain/high-rain), schoon afsluiten.
- Werkelijke PBR-resources en skin/botdeformatie; camera blijft buiten gevel en uitstekende dakrand, ook bij maximale pitch.
- Meer dan 10 m lopen, meer dan 20 m rijden, sturen/remmen/achteruit en veilige uitstap; afzonderlijke rit van hoofdweg via aansluiting door de afgewerkte straat.
- Wielassen blijven op hun plaats tijdens rollen/sturen; lichaamscolliders passen bij de grotere geïmporteerde voertuigen. Bank/fiets hebben fysieke botsing.
- Pauze stopt lichamen, echte animatiecursors en regen. Save/load past de echte omstandigheden terug toe; onbekende waarden worden atomair geweigerd.
- 36 aanvullende GUI-controles: echte instellingenwidgets, bereikbare acties/panelen bij 720p, nieuwedienstvoorkeuren en daadwerkelijk save/load.
- 40 savechecks, 17 weeraudiochecks, 20 native-probetoolchecks; bestaande politie- en vrije-dienstproeven blijven groen. De vrije-dienstproef simuleert 300 seconden en is geen vijf minuten menselijke gameplay.

De gerichte camera-regressie controleert 9.314 daadwerkelijke geveldriehoeken. Een aanvullende camera-only dakvorm dekt de hogere dak-/gootgeometrie; de fysieke loopruimte wordt daarmee niet verkleind.

## Gevonden en herstelde fouten

Een echte JSON-save leverde `4.0` op; een typegevoelige Array-membershipcheck wees de eigen saveversie af. Schema-validatie normaliseert nu uitsluitend eindige gehele getallen en behoudt atomair herstel.

De eerste volledige grafische straatproef meldde na alle gameplayassertions twee gelekte GL-textures. Onafhankelijke isolatie reproduceerde exact twee 349.524-byte leaks bij `Environment.duplicate(true)` gevolgd door vervangen van de gedupliceerde sky. Shallow kopiëren behoudt de scalar-instellingen; een nieuwe unieke sky/material voorkomt de onnodige oude kopie. De minimale [reproducer](sky-copy/README.md) bewaart beide echte logs en hashes. Shader-samplerhints, SSAO, glow en afzonderlijke reflection probes veroorzaakten de geïsoleerde fout niet. De volledige geïntegreerde proef is na de fix schoon; foutlogs zijn niet uitgezonderd.

## Native poort en beperkingen

De exacte native distributies worden opnieuw geëxporteerd en gecontroleerd op Windows x64 en macOS Universal2/arm64/Intel. Dezelfde definitieve ZIP krijgt SHA-/broncontrole, strikte Mac-signaturecontrole en standalone gameplayproeven. De nieuwe grafische matrix onderzoekt Metal op arm64, Vulkan op Intel en D3D12 op Windows met echte backendmetadata en controleert Compatibility afzonderlijk. Automatische enginefallback telt niet als Forward+-bewijs; shader-, script-, dependency-, timeout- en afsluitfouten blijven rood. Hoog/rain krijgt echte drawframes om de SSR-shaderroute te toetsen.

Windows 4.7.2 bevat statisch gekoppelde ANGLE en kan bij onvoldoende OpenGL naar `opengl3_angle` schakelen. Alleen na een volledig schone, werkelijk geverifieerde fallback volgt een afzonderlijke expliciet aangevraagde ANGLE-run met verse vier PNGs, JSON en nul fouten; dit wordt als ANGLE geregistreerd, niet als native OpenGL of Forward+. De pinned binaries en verse enginebron bevestigen dat extra graphics-DLLs vooraf niet nodig zijn. Optionele Agility wordt uitsluitend toegevoegd als werkelijke native fouten dat rechtvaardigen. [Onderzoek/herkomst](visual-street/windows-driver-research.txt).

De standaardrenderer blijft Compatibility totdat de native onderzoeksresultaten een wijziging rechtvaardigen. Software-/hosted resultaten bewijzen geen fysieke doel-GPU-prestaties of menselijke luisterkwaliteit. De afgewerkte straat bewijst de contentpipeline; het overige stadsdeel en v0.1.0 zijn daarmee nog niet voltooid. M3–M5 blijven noodzakelijk.

## Echte vergelijkingsopnamen en metingen

| Zelfde straat/camera | Screenshot | Echte runtimevideo | p50 / p95 / p99 frame-interval | Eerste straatdraw |
|---|---|---|---|---|
| M2 blockout `4cd053b` | [Vóór](visual-street/before/anchor.png) | [Vóór, 22 s route](visual-street/before/runtime.mp4) | 119 / 161 / 198 ms | 4,35 s |
| Originele 3D-straat, dag | [Dag](visual-street/day/anchor.png) | [Dag, 22 s route](visual-street/day/runtime.mp4) | 231 / 381 / 1393 ms | 21,47 s |
| Schemer | [Schemer](visual-street/dusk/anchor.png) | [Schemer, 22 s route](visual-street/dusk/runtime.mp4) | 263 / 586 / 1811 ms | 34,22 s |
| Lichte regen | [Regen](visual-street/rain/anchor.png) | [Regen, 22 s route](visual-street/rain/runtime.mp4) | 260 / 745 / 3412 ms | 44,52 s |

Dit zijn werkelijk gerenderde X11-frames met FFmpeg-schermopname, geen Movie Maker, editor-overlay of marketingcompositie. Alle vier gebruiken exact dezelfde driver-SHA `d1b90dc89019cf71a02a6734b84fc99ca79b7c78de247a0931052c2938db0bd5` en bit-identieke eerste camera/FOV. De oude bron is een gewone read-only Git-archive van de gemergede M2-bron, zonder extra checkout/worktree. De transparante meetoverlay is live data.

Fixtures: uitrusting/radio gereed, startagent `(-2, .1, 38)`, pitch `-.1`, yaw `PI`, FOV 66. Daarna echte W/A/D-input en pauze; auto en agent worden één keer geplaatst op de rijroute bij `(2, .05, 36)` en `(3.8, .1, 36)`. Werkelijke W-input blijft vast tot minstens 1,5 m voorwaartse beweging, daarna echte rem tot stilstand en normale veilige uitstap. De route duurt minimaal 22 echte seconden, maximaal 45. Beide dagritten reden 2,81/2,83 m; schemer/regen 2,83 m. Alle eindlogs hebben de succesmarker en schone afsluiting. Eerste-drawlatency wordt vóór acht extra drawframes voor incremental-sky/probe-settling gemeten; video bevat ook een korte recorderprefix en afsluiting.

De Linux-container gebruikt acht logische CPUs, Mesa 25.0.7 llvmpipe/OpenGL 4.5, 1280×720, portable-profiel en Dummy audio. De nieuwe GPU-geheugenmonitor piekt op 473,60 MiB tegenover 31,53 MiB in de blockout; Godots static-allocationmonitor piekt op 58,51 MiB versus 56,84 MiB. Dit laatste is geen OS-RSS. [Metrics](visual-street/day/metrics.json), [per-frame CSV](visual-street/day/frames.csv) en [bron-/mediahashmanifest](visual-street/day/manifest.json) bewaren de precieze context; elk conditiemapje bevat hetzelfde bewijs.

De softwaremetingen zijn traag en omvatten scheduling, schermrecorder, PNG-readback en koude shader/camera-opbouw. De gecodeerde 30 fps is de videoframerate, geen gemeten game-FPS. Dit voldoet als beschikbare-hardwaremeting en toont tegelijk waarom een doel-GPU-meting nodig blijft; er wordt geen 60-fps- of native-hardwareclaim gemaakt.

Mislukte eerste captures zijn behouden in de ontwikkelcache: een 20 s startupbudget was te kort voor koude software-shaders; een oude plaza-fixture overlapte nieuwe pleinobjecten en werd naar de echte rijbaan verplaatst; een vaste 0,8 s rijinput werd tijdens een lang cameraframe overgeslagen en is vervangen door observeerbare rij-/remvoorwaarden. De onafhankelijke physicsprobe bevestigde bij de rijbaanfixture nul overlaps, 1,88 m beweging in 48 physics-ticks en uitsluitend grondcontacten. Twee schemercaptures werden extern met SIGTERM beëindigd; opnieuw continu awaiten van de capturetool plus begrensde recorder leverde een definitief videoarchief op. Alleen voltooide bestanden met gecontroleerde hashes staan hierboven.


## Eerste native straatrun en gerichte correctie

Run [37801759800](https://github.com/kevindraai/scene112/actions/runs/37801759800), bron `ffbeabde`, slaagde voor Linux, beide exports en alle native headlessproeven inclusief dezelfde Universal2-ZIP op Intel. De drie aanvullende grafische jobs faalden; deze run autoriseert geen merge.

- ARM/Metal voltooide 195 checks en vier foto's, maar meldde zestien echte shadercompilerfouten: anisotrope repeat-filtering genereerde samplerindex 17 terwijl Metal maximaal 15 accepteert. De straatmaterialen en natte-bestratingsshader gebruiken nu gewone mipmap-lineaire filtering. Er is geen shaderfout uitgezonderd; een nieuwe Metal-run moet schoon zijn.
- De officiële Intel-template registreert Vulkan, OpenGL en ANGLE, en geen Metal. De proef vraagt daarom Vulkan voor Forward+ en expliciet ANGLE voor Compatibility. De eerdere OpenGL-start bleef zonder backendmetadata hangen tot de time-out; die mislukking blijft bewaard.
- Windows initialiseert Forward+/D3D12 op Microsoft Basic Render Driver, maar liep vóór de eindmarker tegen de 240s-grens aan. Beide daadwerkelijke Compatibility/ANGLE-runs voltooiden 195 checks, vier foto's en schone afsluiting. Nieuwe verbose- en fasegegevens moeten de resterende stilstand lokaliseren; de primaire time-out blijft een fout.

Provenance onderscheidt nu ook ANGLE-op-Metal wanneer Godot `opengl3` rapporteert, virtuele Apple-adapters en WARP/software. De oude vier vergelijkingsopnamen blijven gekoppeld aan hun ongewijzigde bronhashes vóór deze filtercorrectie; nieuw native bewijs hoort bij de nieuwe PR-head. De eerste lokale hercontrole met gewone mipmaps slaagt: 191 headless- en 195 echte OpenGL-checks, vier beelden en schone audio-/renderafsluiting. Native goedkeuring volgt uitsluitend op de verse exacte-head run.


De tweede native run [37806503527](https://github.com/kevindraai/scene112/actions/runs/37806503527), bron `46ee8ae`, bevestigt schone ARM/Metal én Compatibility-standaloneproeven. Windows/ANGLE voltooit opnieuw alle 195 checks. Forward+/WARP voltooit173 checks en faalt bij de 8s-remdeadline; de loop/pauzefase duurde ongeveer 99s op deze software-adapter. De remcontrole meet nu maximaal twee werkelijke simulatieseconden (120 physics-ticks bij 60Hz), behoudt de verplichte eindsnelheid onder 0,05m/s en gebruikt een aparte 60s-watchdog. Reminput, snelheid, positie en tick-/wandtijd worden gemeten; voertuigfysica blijft identiek. Het totale primaire onderzoeksbudget is 480s (420s in-app), Compatibility 240s, matrix 20min; fouten blijven fataal.

Intel/Vulkan abort vóór app-start; expliciete ANGLE meldt dat geen EGL-display kan worden gemaakt en de daaropvolgende native-GL-route bereikt actor_ready maar geen voltooid menu. De poort blijft rood. De nieuwe proef verzamelt read-only display/CPU-hostgegevens en uitsluitend verse eigen Scene112-crashrapporten, maximaal vijf van 4MiB, om de concrete oorzaak vast te stellen. Deze diagnostiek verklaart de oude failures niet tot hardware-success.


Run [37812929010](https://github.com/kevindraai/scene112/actions/runs/37812929010), bron `f1eb171`, bevestigt volledig schone Windows/D3D12-WARP, twee ANGLE-proeven en beide ARM/Metal/Compatibility-proeven. Windows Forward+ duurt 322,63s op de software-adapter; de rem eindigt op 0m/s na 72 ticks/8741ms. ARM remt in 65 ticks/~1080ms. Beide vallen binnen de expliciete grenzen. Alleen Intel blokkeert de vereiste poort.

Intel heeft volgens de hostgegevens een Apple Paravirtualized Graphics Device met Metal 2. De eigen crashstack lokaliseert Vulkan-initialisatie in `newIndirectArgumentEncoderWithLayout` / `newArgumentEncoderWithArguments`. De gepinde [MoltenVK1.4.1-bron](https://github.com/KhronosGroup/MoltenVK/blob/v1.4.1/MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm) voert precies dat pad uitsluitend met argumentbuffers uit. De volgende Intel-onderzoeksproef stelt daarom uitsluitend voor die Vulkan-child `MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=0`; werkelijke volledige rendering blijft vereist. Dit is geen gewijzigde verpakte gamedefault of geaccepteerd nieuw resultaat. De [officiële parameterdocumentatie](https://github.com/KhronosGroup/MoltenVK/blob/v1.4.1/Docs/MoltenVK_Configuration_Parameters.md) ondersteunt deze runtimeconfiguratie.

Expliciete ANGLE kan op deze Intel-host geen EGL-display maken en valt naar native OpenGL terug. De proef selecteert nu rechtstreeks die werkelijk geïnitialiseerde OpenGL-driver, met dezelfde strikte fout-/backend-/beeldpoorten. Het oude ingekorte stdout leek bij `wind.sample` te stoppen; de volledige engine-log toont dat alle 24 WAVs zijn geladen en de menu-mark.svg wordt geladen. De eigen processample lokaliseert de timeout in de fragmentinterpreter van Apple Software Renderer tijdens `glDrawElements`, niet in audioladen. Alleen de eigen actieve proces-PID wordt vóór de bestaande deadline kort gesampled. Gescheiden profilerstdout/stderr en crash-PID-/starttijdregistratie voorkomen dat een laat Vulkan-crashrapport bij de volgende Compatibility-run wordt toegeschreven. Geen van deze failures wordt uitgezonderd.


Run [37817215630](https://github.com/kevindraai/scene112/actions/runs/37817215630), bron `e3f7364`, behoudt schone Windows- en ARM-resultaten. De Intel-child bevestigt werkelijk discrete MoltenVK-resourcebinding na argumentbuffers=0. Daarna faalt een 262.144-byte stagingbuffer met VkResult −3 en abort een Metal-pipelinevalidatie; deze failure blijft fataal. De gepinde VMA-bron geeft −3 voor nul memory requirements, terwijl MoltenVK bij ingeschakelde placement heaps ook voor coherent Shared-staging een PRIVATE heap-sizequery gebruikt. De volgende begrensde Intel-proef zet aanvullend uitsluitend voor die Vulkan-child `MVK_CONFIG_USE_MTLHEAP=0`. Een afzonderlijk 45s Metal-diagnoseproces registreert de echte heap-querygrootten en één direct Shared-buffer; dit is geen gameplayacceptatie. De oorzaak blijft een gerichte hypothese totdat native resultaten haar bevestigen.

Wereld en avatar starten nu verborgen vóór ze aan de scene tree worden toegevoegd. Het hoofdmenu activeert zo geen onnodige stadsdraw tijdens audio-/UI-initialisatie; starten/hervatten toont dezelfde volledige wereld. De echte grafische speelproef, screenshots en alle timeout-/foutpoorten blijven verplicht.


## Expliciete softwareweergave

De werkelijke Metal-allocatiediagnose in run [37821599779](https://github.com/kevindraai/scene112/actions/runs/37821599779), bron `b632c40`, bevestigt PRIVATE én Shared heap-size/alignment 0, terwijl een directe Shared-buffer van 262.144 bytes slaagt. De gerichte MoltenVK heapconfiguratie verwijdert alle eerdere staging-/textureallocatiefouten. Vulkan initialiseert Forward+ maar abort daarna vóór app-start in Metal-pipelinevalidatie (`No valid pixelFormats set`). Deze nieuwe failure blijft rood en wordt afzonderlijk onderzocht.

Alleen daadwerkelijk software-renderende Compatibility-adapters krijgen nu `software_portable`: 3D-schaal 0,5 met volledige 1280×720-UI, sky-radiance 32, twee begrensde straatlampen, 72 regendeeltjes en geen schaduw-/lokale cubemap-/SSAO-/glow-passes. GLB-geometrie, skin/animatie, bestaande albedo/normal/roughness-materialen en de natte-straatshader blijven identiek. Apple Software Renderer, llvmpipe en softpipe worden via werkelijke engine-adaptermetadata herkend; onbekende adapters, hardware-OpenGL, Metal, Vulkan en D3D12 krijgen dit profiel niet. Settings toont de actieve lichte weergave; gevraagde beeldvoorkeur blijft bewaard. Metadata onderscheidt requested/effective quality en registreert echte viewport-, sky- en effectgetters; een gevraagde high-run geldt hier als softwarefallback, niet als bewezen high-quality hardware-rendering.

Dezelfde geïsoleerde Linux-llvmpipe-route daalt van 105,51s naar 46,17s met 200 voltooide grafische checks, vier verse PNGs en schone afsluiting. Dit is een scenario-walltime, geen game-FPS. Eigen bron-/mediahashes, beide oorspronkelijke logs en backendmetadata bewaren de vergelijking. Native Intel-rendering binnen het bestaande 240s-budget blijft vereist; dit lokale resultaat vervangt die poort niet.
