# Voyager Bar — živá tapeta Voyagera 1 pre macOS

*[English README](README.md)*

Natívna aplikácia (Swift + SceneKit/Metal), ktorá pod ikony na ploche vykresľuje
3D model sondy Voyager 1 v medzihviezdnom priestore — so skutočnou oblohou
a živou telemetriou z efemeríd JPL.

## Čo je vo vnútri

- **Procedurálny 3D model v mierke 1:1** — 3,66 m parabolická anténa HGA
  s Cassegrainovým subreflektorom, desaťboký trup s tepelnými žalúziami
  a MLI fóliou, Zlatá platňa s gravírovaním (pulzarová mapa, vodík), tri RTG
  s rebrami, vedecké rameno so skenovacou platformou (kamery ISS, IRIS, UVS,
  PPS), 13 m priehradový magnetometer a dve 10 m antény PWS/PRA.
- **Fyzikálne správna orientácia** — anténa mieri na Zem, roll je odvodený
  od hviezdy Canopus. Slnko svieti z reálneho smeru (zo sondy ho vidno pri
  Orióne), s magnitúdou ~−15,6 je to najjasnejší objekt oblohy.
- **Skutočná obloha** — 41 487 hviezd z katalógu HYG v4.1 (do mag. 8,
  farby podľa B−V) + ~170 000 slabších hviezd podľa hustoty galaxie,
  procedurálna Mliečna dráha v galaktických súradniciach (výduť, Veľká trhlina,
  Uhoľné vrecko, hmloviny, Magellanove mračná, M31).
- **Živá telemetria** (HUD vľavo dole): vzdialenosť od Zeme a Slnka (km/mi,
  AU — číslice kilometrov bežia naživo), jednosmerný a obojsmerný svetelný čas,
  rýchlosť, misijné hodiny od štartu, kedy dorazí signál odoslaný teraz,
  a odpočet do okamihu, keď bude Voyager **jeden svetelný deň od Zeme**
  (18.–19. novembra 2026).
- **Filmová kamera** — štyri zábery (Hero s Labuťou, Profile s Kentaurom,
  Looking Home so Slnkom, Outbound s jadrom galaxie) s plynulými prechodmi
  a pomalým driftom; zábery sú vybrané tak, aby bola v pozadí vždy Mliečna dráha.
- HDR, bloom, mäkké tiene, PBR materiály, vinetácia.

## Časová os (Explorer)

Panel v menu bare → **Explorer**.

- **Rozsah a mierka.** Presné dáta JPL Horizons pokrývajú let od 5. 9. 1977 (hodinu po
  štarte, odkedy má JPL trajektóriu) do 1. 1. 2100, kde sa končí oficiálna predikcia.
  Táto časť osi je **lineárna** a dá sa priblížiť od 120 rokov až po 10-minútové úseky
  (koliečko/pinch = zoom, vodorovný posun = posúvanie, ťahanie = presun v čase).
  Za rokom 2100 nasleduje **logaritmický „hlboký čas"** až do roku 1 000 000:
  Voyager sa ďalej integruje ako teleso na hyperbole okolo Slnka a hviezdy sa
  posúvajú podľa svojich skutočných priestorových rýchlostí z katalógu HYG
  (poloha aj jasnosť sa prepočítavajú z pohľadu sondy). Presnosť tu už nie je
  „kilometrová" — ide o fyzikálne konzistentnú extrapoláciu a je tak aj označená.
- **Prehrávanie** od reálneho času po 1 000 rokov za sekundu, dopredu aj dozadu,
  skoky medzi míľnikmi, tlačidlo **Live** vráti všetko do prítomnosti.
- **Míľniky:** štart, snímka Zem–Mesiac, Jupiter, Io, Ganymedes, Kallisto, Titan,
  Saturn, Pale Blue Dot, predbehnutie Pioneera 10, rázová vlna, heliopauza, jeden
  svetelný deň, koniec predikcie JPL, 1 000 AU, jeden svetelný rok a vypočítané
  najbližšie priblíženia ku hviezdam (napr. Gliese 445: ~1,9 ly okolo roku 46 600).
- **Prelety.** Pri Jupiteri a Saturne sa zobrazia planéty a mesiace podľa presných
  vektorov z Horizons (10-minútový krok) — s osvetlením, rotáciou podľa IAU,
  sploštením, prstencami Saturna a zatmeniami Slnka. Tapeta vtedy sama prepne na
  záber, ktorý ukáže sondu aj planétu.
- Časová os je spoločná: tapeta, panel v menu bare aj HUD ukazujú simulovaný
  dátum (s odznakom SIMULATED/EXTRAPOLATED).

## Obhliadka zblízka

V Exploreri sa sondou dá voľne otáčať (ťahanie alebo dvoma prstami),
približovať (pinch/koliečko, až na ~0,6 m), posúvať (⌥-ťahanie) a dvojklikom
zaostriť na miesto pod kurzorom. Bočný panel obsahuje 11 súčastí s rýchlymi
zábermi a popisom (anténa, subreflektor, Zlatá platňa s gravírovaním, trup,
RTG, skenovacia platforma, vedecké rameno, magnetometer, antény PWS, trysky…),
popisky v 3D, inšpekčné svetlo pre tienené miesta a „Look toward" (Slnko, Zem,
smer letu, jadro galaxie, Gliese 445, práve blízke planéty).

## Spotreba AI (Claude + OpenAI Codex)

Ikona v menu bare ukazuje najnapätejší limit každého poskytovateľa (farebne podľa
zostávajúcej kapacity) alebo počet tokenov za dnešok; kliknutím sa otvorí panel:

- **Tokeny a cena** za dnešok, 7 a 30 dní, 14-dňový graf, najpoužívanejší model.
  Čítajú sa **lokálne** logy Claude Code (`~/.claude/projects`) a Codex
  (`~/.codex/sessions`), prírastkovo (číta sa len to, čo pribudlo). Cena je
  „API ekvivalent" podľa oficiálnych cenníkov Anthropic a OpenAI (vrátane cache,
  1h cache a fast módu) — pri predplatnom to nie je suma, ktorú platíte.
- **Limity plánu.** Codex zapisuje svoj stav limitov priamo do logu, takže sa
  zobrazí bez siete. Pre Claude je potrebné raz kliknúť na „Connect plan limits…":
  aplikácia si (iba na čítanie) prečíta prihlásenie Claude Code z Keychainu a
  zavolá rovnaké rozhranie ako `/usage`. Token sa nikdy neobnovuje ani
  nezapisuje, takže prihlásenie Claude Code sa nijako neovplyvní; keď vyprší,
  stačí raz otvoriť Claude Code.
- Rovnaké údaje sú voliteľne aj priamo na tapete (panel „AI USAGE").

## Inštalácia

Najjednoduchšie jedným príkazom v Termináli (nainštaluje alebo aktualizuje na najnovšie vydanie):

```bash
curl -fsSL https://raw.githubusercontent.com/FeN1x1/voyager-bar/main/install.sh | bash
```

Alebo stiahni `VoyagerBar-<verzia>.dmg` z [vydaní](https://github.com/FeN1x1/voyager-bar/releases/latest)
a pretiahni aplikáciu do Applications. Build nie je notarizovaný Apple, takže pri prvom
spustení treba v Systémových nastaveniach → Súkromie a bezpečnosť kliknúť „Aj tak otvoriť".

Zostavenie zo zdrojov:

```bash
./build.sh             # zostaví build/Voyager Bar.app (universal: Apple silicon + Intel)
./build.sh --install   # zostaví a nainštaluje do /Applications
./build.sh --dmg       # zostaví DMG a ZIP na distribúciu
open "/Applications/Voyager Bar.app"
```

Požiadavky: macOS 13 Ventura alebo novší, Xcode Command Line Tools
(`xcode-select --install`).

Aplikácia beží v menu bare (malá silueta Voyagera), nemá ikonu v Docku. Ľavý klik otvorí panel riadiaceho strediska, pravý klik nastavenia.

## Menu bar, maskot a nastavenia (1.1)

- **Menu bar:** jeden krúžkový ukazovateľ na poskytovateľa v jeho farbe — Claude oranžová,
  OpenAI biela (na svetlej lište čierna). Pre Claude sa predvolene ukazuje **5-hodinový**
  limit, pre Codex **týždenný**; dá sa prepnúť (5 h / týždeň / najtesnejší, použité / zostáva).
- **Claude limity bez hesla:** Claude Code ukladá prihlásenie do Keychainu cez nástroj
  `security`, ktorému táto položka dôveruje — Voyager Bar ho číta rovnako, takže macOS
  nepýta heslo. Token sa iba číta, nikdy neobnovuje ani nezapisuje.
- **Maskot:** malý rotujúci Voyager kdekoľvek na obrazovke; pri nabehnutí (alebo po kliknutí)
  bublina s limitmi, dvojklik otvorí panel, pravý klik možnosti. Majáčik: zelená → jantárová
  (75 %) → blikajúca červená (90 %), pri 100 % Voyager „zaspí".
- **Nastavenia v 4 záložkách:** Tapeta (živá tapeta zap/vyp, monitory, kamera…), Menu bar,
  Maskot, Systém.

## Panel v menu bare

Čierny panel v štýle riadiaceho strediska misie: živý render sondy, vzdialenosť od Zeme
(tikajúce kilometre), svetelný čas, „signál na ceste" (kde práve letí signál vyslaný
o polnoci), a spotreba AI — tokeny, cena, 14-dňový graf a limity plánov ako segmentové
ukazovatele s odpočtom resetu. Stránka **Settings** obsahuje všetky nastavenia tapety
(kamera, kompozícia, pohyb, fps, jednotky, prekrytia, antialiasing), menu baru,
spúšťania po prihlásení, pripojenia limitov Claude a akcie (Explorer, uloženie snímky,
nastavenie ako systémovej tapety).

## Úspora energie

- Renderuje sa v natívnom rozlíšení panelu (pri škálovaných Retina režimoch
  je to menej pixelov než backing store okna).
- Pri zakrytí plochy (aplikácia na celú obrazovku, maximalizované okno),
  uspatí displeja, prepnutí používateľa alebo ručnej pauze sa renderovanie
  úplne zastaví.
- V režime nízkej spotreby (Low Power Mode) sa FPS obmedzí na 15.
- Na M3 Pro pri 30 fps (displej 3024×1964): ~14 % jedného jadra CPU, ~650 MB pamäte (väčšinou GPU buffre HDR). Pri 15 fps približne polovica. Explorer má vlastnú scénu, ktorá sa pri zatvorení okna uvoľní.

## Dáta

- `Resources/ephemeris.bin` — denné stavové vektory Voyagera 1 z JPL Horizons
  (riešenie `Voyager_1_ST+refit2022_m`, 1977–2100: 5 min po štarte, 10 min pri preletoch, inak denne), heliocentrické
  aj geocentrické, ICRF. Interpolácia kubickým Hermitovým polynómom
  (presnosť pod 1 km). Mimo rozsahu sa trajektória extrapoluje balisticky.
- `Resources/stars.bin` — HYG Database v4.1 (David Nash / astronexus),
  licencia CC BY-SA 4.0: hviezdy do mag. 8 a všetky hviezdy do 25 pc s 3D polohou
  a rýchlosťou.
- `Resources/bodies.bin` — vektory Voyager → Mesiac, Jupiter a Galileove mesiace,
  Saturn a 6 mesiacov okolo preletov (JPL Horizons).
- `Resources/Textures/` — textúry Zeme, Mesiaca, Jupitera, Saturna a jeho prstencov
  zo Solar System Scope, licencia CC BY 4.0.
- Obe súbory sa dajú pregenerovať: `python3 tools/prepare_data.py`.
- Panoráma Mliečnej dráhy sa vygeneruje pri prvom spustení (~0,5 s)
  a uloží do `~/Library/Caches/com.voyager1.wallpaper/`.

## Vývoj

```bash
# Statická snímka bez spúšťania tapety:
"build/Voyager Bar.app/Contents/MacOS/VoyagerBar" --snapshot out.png \
    --size 3024x1964 --mode outbound --scale 2
# režimy: hero | profile | home | outbound | tour (s --tour-time <s>)
# ďalej: --date 1979-03-05T12:00:00Z | --date 46580, --part record --studio, --orbit yaw,pitch,dist
"build/Voyager Bar.app/Contents/MacOS/VoyagerBar" --usage-report   # súhrn tokenov z lokálnych logov
```

Zdrojové súbory (`Sources/`):

| Súbor | Obsah |
|---|---|
| `Ephemeris.swift` | načítanie efemeríd, interpolácia, odvodená telemetria |
| `Spacecraft.swift` | 3D model a materiály |
| `Sky.swift` | hviezdy (vlastný Metal shader, bodové sprity), Mliečna dráha, Slnko |
| `MilkyWay.swift` | procedurálny model galaxie, prevod do galaktických súradníc |
| `VoyagerScene.swift` | scéna, svetlá, kamera a zábery |
| `WallpaperController.swift` | okno na úrovni plochy, nastavenia |
| `HUDView.swift` | telemetria |
| `AppDelegate.swift` | menu bar, správa monitorov, napájanie |
| `SimClock.swift` | spoločný simulovaný čas |
| `SolarSystem.swift`, `Bodies.swift` | polohy a vykresľovanie planét a mesiacov |
| `Milestones.swift` | historické a vypočítané míľniky |
| `ExplorerWindow.swift`, `ExplorerParts.swift`, `TimelineView.swift` | Explorer, súčasti, časová os |
| `UsageStore.swift`, `UsageLimits.swift`, `UsagePricing.swift` | tokeny, limity, cenníky |
| `UsagePopover.swift`, `UsageHUDView.swift` | panel v menu bare a na tapete |

Neoficiálny fanúšikovský projekt, nie je spojený s NASA ani JPL.

Poznámka: bledomodrá bodka Zeme pri Slnku je od neho odsunutá 6× ďalej,
než je skutočný uhol (max. ~0,33°), aby sa nestratila v žiare.

## Ukážky

| | |
|---|---|
| ![Hero](docs/hero.jpg) | ![Profile](docs/profile.jpg) |
| ![Looking Home](docs/home.jpg) | ![Outbound](docs/outbound.jpg) |
