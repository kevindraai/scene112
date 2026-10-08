# Noorderkade straatbron

Originele metrische Blender-geometrie: gemetselde rijwoning met echte raamopeningen, deurpanelen, kozijnen, dorpels, gordijnen, goten, regenpijpen, pannendak en schoorsteen; houten bank, straatlamp en fiets. De runtime gebruikt GLB, geen Blender-installatie. De `.blend`-bestanden bevatten ingepakte eigen texturen en blijven bewerkbaar.

Herbouw vanaf de repositoryroot met Blender 4.3 of nieuwer en NumPy voor de texturegenerator:

```sh
python tools/art/author_street_textures.py
blender --background --factory-startup --python-exit-code 1 --python tools/art/author_street_models.py
godot --headless --path . --editor --import
```

De texturegenerator maakt achttien originele 1024² PNGs (albedo, normal en roughness voor baksteen, klinkers, asfalt, dakpannen, hout en gras/aarde) met vaste seeds. De primaire UV-laag gebruikt oppervlaktemeters en tegelt per twee meter. Statische onderdelen worden per materiaal samengevoegd en voor export getrianguleerd; huizen gebruiken gedeelde geïmporteerde mesh-/textureresources. Godot maakt automatisch afstands-LOD tijdens de GLB-import. De gevels houden de bestaande woningposities en botsingsgrenzen; deze slice maakt woonhuizen nog niet betreedbaar.

`assets/models/street/manifest.json` vermeldt bron, bewerkbare bestanden, materiaal-/driehoekaantallen en licentie. `assets/textures/street/manifest.json` registreert de oorspronkelijke texturebestanden met SHA256. PNGs die Godot uit GLB extraheert zijn gegenereerde imports en worden niet dubbel opgeslagen in Git. `source/.gdignore` voorkomt dat Godot editable Blender-bronnen als runtime-assets importeert.

Alle geometry en texturepatronen zijn voor SCÈNE 112 gemaakt. Geen gekopieerde merken, samples of betaalde assets. De private projectlicentie geldt voor de assets; Blender is alleen de authoringtool.
