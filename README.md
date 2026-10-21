# Suceava Pulse — Flutter starter

Acesta este un starter de UI Flutter pentru o aplicație comunitară independentă, concentrată pe sosirile de avion, tren și autocar în Suceava și pe oportunități de cerere potențială în apropierea punctelor de transport.

**Important:** toate cursele și orele din acest starter sunt demonstrative. Nu există încă integrare cu date de transport live, push notifications reale sau date interne Bolt.

## 1. Creează automat proiectul pe Windows

Cel mai simplu este să extragi ZIP-ul, să deschizi PowerShell în folderul extras și să rulezi:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\create_project_windows.ps1
```

Scriptul creează `C:\Users\<utilizator>\Developer\suceava_travel_alerts`, generează proiectul Flutter Android, copiază fișierele starterului, inițializează Git și încearcă să ruleze `flutter pub get`, `flutter analyze` și `flutter test`. Nu suprascrie un director de proiect existent. Dacă destinația există deja, scriptul se oprește în siguranță.

Dacă preferi manual, rulează:

```powershell
New-Item -ItemType Directory -Force "$HOME\Developer" | Out-Null
Set-Location "$HOME\Developer"
flutter create --org ro.suceava --project-name travelalerts --platforms=android suceava_travel_alerts
Set-Location "$HOME\Developer\suceava_travel_alerts"
git init
```

Proiectul inițial este Android-first. iOS poate fi adăugat ulterior, dar compilarea iOS necesită macOS cu Xcode.

## 2. Rulează și verifică aplicația

În terminalul din rădăcina proiectului:

```powershell
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter devices
```

Pornește un emulator Android din Android Studio → Device Manager. După ce apare în `flutter devices`, rulează:

```powershell
flutter run
```

Dacă Android Studio este deschis, poți folosi și Run pentru a porni aplicația.

## 3. Deschide proiectul în Claude Code

Din PowerShell, în rădăcina proiectului:

```powershell
claude
```

Cere-i să citească `claude_suceava_travel_alerts_prompt.md` și să continue incremental. Nu configura încă Firebase până când UI-ul, modelele și testele inițiale funcționează.

## Structură inclusă în starter

- `lib/app/`, `lib/core/` — inițializare, navigație, temă, texte în română.
- `lib/features/` — `transport` (modele, surse), `arrivals` (listă, filtre, detalii), `dashboard` (panou, potențial de cerere), `settings` (preferințe persistente), `notifications` (logica deciziei de alertare, fără trimitere).
- `test/` — teste unitare (domeniu, date, controller) și teste de widget (panou, filtre, stări, detalii, setări).
- `claude_suceava_travel_alerts_prompt.md` — specificația completă pentru Claude Code.
- `docs/ARCHITECTURE.md` — note despre arhitectură și limitele MVP-ului.
- `docs/DATA_SOURCE_FEASIBILITY.md` — ce surse de date reale există pentru zboruri, trenuri și autocare și ce lipsește pentru integrare.
- `backend/README.md` și `infrastructure/README.md` — pași pentru fazele viitoare.
