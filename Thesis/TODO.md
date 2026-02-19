# TODO — Poprawki spójności i redundancji pracy dyplomowej

Data analizy: 2026-02-19

---

## KRYTYCZNE

### 1. Role IAM — sprzeczność między Rozdziałem 3 a Rozdziałem 6

**Problem:** Rozdział 3 twierdzi, że AWS Academy nie pozwala tworzyć ról IAM, a Rozdział 6 opisuje, że Terraform taką rolę tworzy i używa jej do uwierzytelniania EC2.

- **Rozdział 3** (ograniczenia): *"brak możliwości tworzenia ról IAM oraz konfiguracji federacji tożsamości OIDC"*
- **Rozdział 3** (tabela decyzji): *"AWS Academy zabrania tworzenia ról IAM; OIDC niedostępne"*
- **Rozdział 6** (Terraform): *"IAM Role — rola instancji EC2 z uprawnieniami do odczytu i zapisu S3 oraz ECR"*
- **Rozdział 6** (tabela workflow): *"uwierzytelnia się przez rolę IAM przypisaną do instancji"*

**Jak naprawić:**
Rozdział 3 jest za szeroki. Prawdziwe ograniczenie to brak możliwości tworzenia ról IAM dla **federacji OIDC z GitHub Actions**. EC2 Instance Profile (rola przypisywana instancji) jest dozwolona w AWS Academy.

Zmienić w Rozdz. 3: *"brak możliwości tworzenia ról IAM"* → *"brak możliwości konfiguracji dostawcy tożsamości OIDC, który pozwoliłby GitHub Actions uwierzytelniać się w AWS bez kluczy"*

Plik: `tex/03_architektura_systemu.tex` (linia ~20 i tabela decyzji ~168–170)

---

### 2. Czas treningu — trzy różne liczby

**Problem:** Ten sam parametr ma trzy różne wartości w różnych miejscach pracy.

| Miejsce | Wartość |
|---|---|
| Rozdz. 3, cele projektowe | **2,5 h** (limit/cel) |
| Rozdz. 7, tabela `tab:czasy` | **\~3 h** |
| Rozdz. 7, tekst + tabela kosztów + skalowanie | **\~3,5 h** |

Dodatkowo: cel "≤ 2,5 h" (Rozdz. 3) nie został osiągnięty — rzeczywisty czas to 3,5 h. Nie jest to nigdzie skomentowane.

**Jak naprawić:**
- Ujednolicić czas treningu do jednej liczby (**3,5 h** jako zmierzona wartość)
- W Rozdz. 3 albo zaktualizować cel (np. *"trening nie powinien przekraczać czasu sesji AWS"*) albo dodać zdanie, że cel był szacunkowy i rzeczywisty czas wyniósł ~3,5 h
- W tabeli `tab:czasy` zmienić `\sim$3 h` → `\sim$3{,}5 h`

Pliki: `tex/03_architektura_systemu.tex` (linia ~14), `tex/07_analiza_wynikow_i_dzialania_systemu.tex` (tabela `tab:czasy`, linia ~36)

---

## ISTOTNE

### 3. Metryki bramki jakości — nieaktualne nazwy (Rozdział 5)

**Problem:** Rozdział 5 opisuje bramkę jakości używając `val_dice` / `val_iou` (metryki per-epoka na zbiorze walidacyjnym), ale po poprawkach wniesionych do `quality-gate.py` i `train.py` bramka używa `final_test_dice` / `final_test_iou` (metryki na zbiorze testowym po zakończeniu treningu na najlepszym modelu).

- **Rozdział 5** (logika decyzyjna): `val_dice > baseline_dice` i `val_iou > baseline_iou`
- **Rzeczywista implementacja**: `final_test_dice > baseline_dice` i `final_test_iou > baseline_iou`

**Jak naprawić:**
Zaktualizować sekcję "Bramka jakości" w Rozdziale 5 — zmienić nazwy metryk i dodać wyjaśnienie, że używane są metryki ze zbioru testowego (nie walidacyjnego), bo tylko one odzwierciedlają rzeczywistą jakość najlepszego wytrenowanego modelu.

Plik: `tex/05_pipeline_ci_cd.tex` (linia ~152–160)

---

### 4. Tabela skalowania vs limit czasu sesji AWS (Rozdział 3 vs Rozdział 7)

**Problem:** Rozdział 3 wymaga treningu ≤ 2,5 h (okno sesji AWS). Tabela skalowania w Rozdziale 7 szacuje czas dla 700 obrazów na ~7 h, dla 1500 na ~15 h. Nigdzie nie jest wyjaśnione, jak taki trening miałby się zmieścić w ograniczeniu sesji.

**Jak naprawić:**
Dodać przypis lub zdanie do tabeli skalowania w Rozdz. 7: przy zbiorach wymagających treningu >4 h wymagane byłoby uruchomienie wielu sesji AWS lub migracja na konto bez limitu czasu sesji (np. standardowe AWS).

Plik: `tex/07_analiza_wynikow_i_dzialania_systemu.tex` (tabela `tab:skalowanie`, linia ~149)

---

## DROBNE

### 5. Formatowanie komórki w tabeli kosztów (Rozdział 7)

**Problem:** Wiersz podsumowania w tabeli `tab:koszty` używa `\textit{20} USD` zamiast spójnego formatu `$\sim$\$20`.

Plik: `tex/07_analiza_wynikow_i_dzialania_systemu.tex` (linia ~165)

**Poprawka:** zmienić `\textit{20} USD` → `$\sim$\$20`

---

### 6. Podpis rysunku flow MLOps w Rozdziale 2

**Problem:** Rysunek przedstawia cykl MLOps, ale podpis mówi "CI/CD".

- Obecny: `\caption{Przykład flow CI/CD \cite{mlops_flow}}`
- Poprawny: `\caption{Przykład flow MLOps \cite{mlops_flow}}`

Plik: `tex/02_wprowadzenie_teoretyczne.tex` (linia ~46)

---

### 7. MLflow opisany jako narzędzie monitoringu produkcyjnego (Rozdział 2)

**Problem:** Zdanie podsumowujące sekcję o MLflow w Rozdziale 2:
> *"MLflow spina cały cykl życia modelu ML [...] aż po zarządzanie wdrożeniem i monitorowanie kolejnych wersji w środowisku produkcyjnym"*

W projekcie monitorowanie działającej aplikacji realizują Prometheus i Grafana, nie MLflow. MLflow służy do śledzenia eksperymentów i rejestru modeli.

**Jak naprawić:** Skrócić zdanie lub doprecyzować: MLflow zarządza cyklem do momentu rejestracji i promocji modelu; monitoring produkcyjny realizuje Prometheus/Grafana.

Plik: `tex/02_wprowadzenie_teoretyczne.tex` (linia ~49)

---

## REDUNDANCJE (do oceny — nie muszą być usunięte)

| Temat | Gdzie | Uwaga |
|---|---|---|
| Mechanizm stop/start EC2 i koszt $0,29 | Rozdz. 3 (tabela), Rozdz. 7 (koszty), Rozdz. 8 (wnioski) | Trzykrotne powtórzenie — wystarczy raz szczegółowo, reszta to odesłania |
| Zasada działania DVC | Rozdz. 2, 3, 5, 7, 8 | Poziom szczegółowości akceptowalny, bo każde miejsce ma inny kontekst |
| Opis hooka pre-push | Rozdz. 3 (warstwa kontroli wersji) + Rozdz. 5 (pełna sekcja) | Fragment w Rozdz. 3 jest zbędny — wystarczy odesłanie "szczegóły w Rozdziale 5" |
| Opis bramki jakości | Rozdz. 3, 5, 7, 8 | Akceptowalne — każde miejsce ma inny poziom szczegółowości |
