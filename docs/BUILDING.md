# Bouwen en private testbuilds

De vastgezette toolchain is **Godot 4.7.2 stable, standard edition** en de bijbehorende `4.7.2.stable` exporttemplates. Python 3.12 of nieuwer volstaat voor de bootstrap- en artefactcontrole. Het spel zelf heeft geen Python of editor nodig.

`tools/setup_godot.py` haalt de editor en optioneel templates uit de officiële [Godot GitHub-release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable). Zowel de officiële assetmetadata als de gedownloade bytes moeten overeenkomen met de vastgelegde SHA256. Bij afwijkingen stopt de installatie. Templates zijn circa 1,28 GB; eerste installatie vraagt vrije schijfruimte voor download én uitpakken. Alle buildtools blijven in de opgegeven cache. macOS/Windows gebruiken Godots self-contained editormodus; Linux gebruikt cache-lokale XDG-directories.

## Linux: lokale checks en cross-export

```sh
python3 tools/setup_godot.py --cache-dir .godot-tools --templates
export XDG_DATA_HOME="$PWD/.godot-tools/data"
export XDG_CONFIG_HOME="$PWD/.godot-tools/config"
export XDG_CACHE_HOME="$PWD/.godot-tools/cache"
GODOT_BIN="$PWD/.godot-tools/editor/Godot_v4.7.2-stable_linux.x86_64"
"$GODOT_BIN" --version
"$GODOT_BIN" --headless --path . --editor --import
"$GODOT_BIN" --headless --path . --script tests/run_tests.gd
"$GODOT_BIN" --headless --path . -- --smoke-test
mkdir -p build/windows
"$GODOT_BIN" --headless --path . --export-release macOS "$PWD/build/Scene112-macOS-universal.zip"
"$GODOT_BIN" --headless --path . --export-release Windows "$PWD/build/windows/Scene112.exe"
python3 -m zipfile -c build/Scene112-Windows-x64.zip build/windows/Scene112.exe build/windows/Scene112.pck
python3 tools/validate_artifacts.py macos build/Scene112-macOS-universal.zip
python3 tools/validate_artifacts.py windows build/Scene112-Windows-x64.zip
```

Wanneer Windows een aanvullende consolewrapper genereert, neem die bij distributie ook op. De `.exe` en `.pck` moeten naast elkaar blijven. Het macOS-preset gebruikt een Universal2-template en Godots ingebouwde ad-hoc ondertekening. Een export vanaf Linux bewijst geen native uitvoerbaarheid; CI voert daarna de exports en runtimecontrole op de doelplatforms uit.

Voor een bestaande Linux-editor kan alleen de template-installatie worden uitgevoerd:

```sh
XDG_DATA_HOME=/tmp/scene112-tools/data python3 tools/setup_godot.py --cache-dir /tmp/scene112-tools --templates-only
```

## Native ontwikkelomgeving

Voer `python tools/setup_godot.py --cache-dir .godot-tools --templates` uit vanuit het repository. Op macOS staat de editor vervolgens in `.godot-tools/editor/Godot.app`; de commandlinetool is `Godot.app/Contents/MacOS/Godot`. Op Windows is de commandlinetool `.godot-tools/editor/Godot_v4.7.2-stable_win64_console.exe`. Gebruik bij PowerShell `&` om een executable in een geciteerd pad aan te roepen. Open `project.godot` voor interactieve ontwikkeling; wijzig de vastgezette engineversie pas na afzonderlijk werkende exports.

## CI en bewijs

De workflow [Native builds](../.github/workflows/native-build.yml) controleert de **exacte PR-head** en opnieuw `main` na merge. Linux voert Python-lint, Godot-import, deterministische tests en de ingebouwde applicatiesmoke/playthrough uit. Pas daarna mogen de macOS- en Windows-jobs exporteren. Zij controleren het distributiearchief en starten de standalone executable met `--headless -- --smoke-test` en `--headless -- --playthrough`; de assertions moeten eindigen met `SMOKE_OK` respectievelijk `SCENE112_PLAYTHROUGH_OK` en exitcode 0. Script-/enginefouten in logs maken de check rood, ook als Godot exitcode 0 teruggeeft.

Linux voert bovendien de geautomatiseerde playthrough met een echte OpenGL-renderer op een geïsoleerd Xvfb-display uit. De gerenderde `m0-playthrough.png` wordt bij de logs bewaard. Deze automatisering stuurt de fysieke loopinput en controleert interacties/save-load; voor sommige nabijheidschecks wordt de positie gezet. Het is technische gameplayvalidatie en geen menselijke playthrough of Mac-/Windows-grafisch bewijs.

Op macOS controleert CI `.app`-structuur, uitvoerrechten, beide CPU-architecturen en de ad-hoc handtekening. De eerste native smoketest/playthrough draait op arm64. Een aparte Intel-Mac-job consumeert exact hetzelfde Universal2-archief, controleert de broncommit en SHA256 en voert beide controles opnieuw uit op x86_64. Windows controleert de x86_64 PE-header, de externe resourcepack en native lancering. Deze controles bewijzen runtime-initialisatie en de ingebouwde fysieke gameplayassertions. **Grafische speelbaarheid vereist aanvullend expliciet testbewijs op desktophardware.**

Elke succesvolle relevante PR-/main-build biedt `Scene112-macOS-universal.zip` en `Scene112-Windows-x64.zip` als workflowartifacts, met een JSON-provenancerecord (broncommit, engine, runnerarchitectuur, run-ID, SHA256 en testniveau). Logs worden ook bij failures bewaard. Artifacts en logs verlopen na 14 dagen. Bij uitsluitend Markdown-/licentiewijzigingen slaat de workflow de zware jobs over; de vaste check **Required native build gate** blijft bestaan en beoordeelt de documentatiecheck. Gebruik deze vaste check voor branch protection. Een handmatig gestarte workflow bouwt altijd beide platformen.

## Installeren zonder ontwikkeltools

**Windows 10/11 x64:** pak `Scene112-Windows-x64.zip` volledig uit in een schrijfbare map en start `Scene112.exe`. Bewaar `Scene112.pck` in dezelfde map. Een private build is niet met een betaald Windows-certificaat ondertekend; SmartScreen kan daarom een melding geven.

**macOS Intel/Apple Silicon:** pak `Scene112-macOS-universal.zip` uit met Finder en verplaats `Scene112.app` bijvoorbeeld naar Applications. De private testbuild is ad-hoc ondertekend en niet genotariseerd. Probeer Control-klik → Open; als de huidige macOS-versie dit blokkeert, open de app één keer en kies daarna Systeeminstellingen → Privacy en beveiliging → Open toch. Bevestig alleen de build uit dit private repository. Volg zo nodig de [officiële Godot-instructies voor niet-genotariseerde apps](https://docs.godotengine.org/en/4.7/tutorials/export/running_on_macos.html). Developer ID-signing en notarization volgen wanneer releasewens en credentials beschikbaar zijn.

Spelerbestanden worden door Godot via `user://` platformcorrect opgeslagen. Een release- of speelbaarheidstatus mag uitsluitend worden vermeld met de bijbehorende tests en concrete playthrough; het bestaan van de ZIP-bestanden volstaat niet.
