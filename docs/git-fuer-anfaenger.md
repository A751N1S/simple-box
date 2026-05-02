# Git in 5 Minuten

Mentales Modell: Git ist ein Programm, das Schnappschuesse von einem
Ordner macht. Der Ordner heisst Repo. Ein Schnappschuss heisst Commit.
GitHub = Webseite, die Repos in der Cloud spiegelt.

## Workflow ohne Konsole

1. **GitHub Desktop** installieren: https://desktop.github.com
2. Repo klonen
3. Files aendern
4. In GitHub Desktop: Summary tippen, Commit, Push

Das war es fuer den Anfang.

## Der Bootstrap-One-Liner

Auf jeder Box als Admin:
```powershell
irm https://raw.githubusercontent.com/A751N1S/simple-box/main/bootstrap.ps1 | iex
```

Eine Zeile, holt aktuellen Stand, installiert.

## Was du ignorieren kannst

Branches, Pull Requests, Forks, Merge Conflicts, Tags, Submodules, Actions.
Brauchst du am Anfang nicht.

## Wenn was schiefgeht

GitHub Desktop -> History -> Rechtsklick auf Commit -> "Revert this commit".
Dann pushen. Aenderung ist rueckgaengig gemacht (als neuer Commit).

Bei versehentlich committeten Secrets: zusaetzlich rotieren (also den Token /
Key in der Quelle neu generieren), nicht nur revertieren.
