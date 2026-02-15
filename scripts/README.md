# scripts/

Skrypty automatyzujące operacje infrastrukturalne i ML pipeline. Część jest wywoływana przez GitHub Actions, część służy do ręcznego zarządzania środowiskiem.

## Infrastruktura AWS

**`deploy-to-cloud.sh`** — uruchamia całą infrastrukturę przez `terraform apply`, czeka na gotowość MLflow i wypisuje URL-e dostępowe. Punktem wejścia do sesji roboczej.

**`stop-cloud.sh`** — niszczy infrastrukturę przez `terraform destroy`. Pyta o potwierdzenie. Używać po zakończeniu pracy, żeby nie generować kosztów.

**`cleanup-aws.sh`** — głębsze czyszczenie: oprócz terraform destroy, opróżnia buckety S3 (obsługuje wersjonowanie i delete markers) i weryfikuje, że nie zostały żadne zasoby generujące koszty. Operacja nieodwracalna — wymaga interaktywnego potwierdzenia.

**`verify-deployment.sh`** — sprawdza stan po restarcie instancji (AWS Academy resetuje IP). Weryfikuje: SSH, k3s ready, MLflow `/health`, status podów, ekspozycję NodePort, smoke testy FastAPI i rejestr modeli.
Parametry: `EC2_IP` (domyślnie hardcoded), `SSH_KEY` (domyślnie `~/.ssh/labsuser.pem`).

## Kubernetes

**`setup-k3s.sh`** — instaluje k3s i Helm 3 na instancji EC2. Normalnie wywoływane przez user-data przy starcie instancji, ale można uruchomić ręcznie po problemach.

**`cleanup-old-deployments.sh`** — usuwa stare Helm releases i namespace'y Kubernetes pasujące do wzorca `model-*`. Domyślnie tryb dry-run (`--dry-run`). Przydatne po nieudanych deploymentach.

## MLflow

**`setup-mlflow.sh`** — instaluje MLflow i uruchamia go jako serwis systemd z backendem SQLite (`/opt/mlflow/mlflow.db`) i artefaktami na S3. Parametr: `MLFLOW_BUCKET` (domyślnie `wms-mlflow-artifacts-055677744286`).

## Git hooks

**`install-git-hooks.sh`** / **`install-git-hooks.bat`** — instalują pre-push hook w lokalnym repozytorium ML. Hook wykrywa nowe pliki obrazów/masek (`.jpg`, `.png`) lub zmiany `.dvc` i automatycznie tworzy branch `data/YYYYMMDD-HHMMSS`, commituje i pushuje — blokując bezpośredni push do `main`. AWS credentials nie są potrzebne lokalnie; mergowanie danych odbywa się w CI.

## DVC / S3

**`cleanup-s3-dvc.sh`** — usuwa pliki osierocone z bucketu DVC (nieużywane przez żaden manifest `.dvc`). Domyślnie dry-run. Flaga `--confirm` uruchamia faktyczne usuwanie, `--auto` uruchamia bez interaktywnego potwierdzenia (używane przez CI). Wczytuje aktywne manifesty `images.dvc` i `masks.dvc`, parsuje hashes i porównuje z zawartością S3. Przy obecnej architekturze (DVC push tylko po udanym treningu) pliki osierocone nie powinny powstawać w normalnym przepływie — skrypt służy jako narzędzie awaryjne.

## Walidacja i jakość modelu (używane przez GitHub Actions)

**`data-qa.py`** — waliduje dane treningowe przed uruchomieniem treningu. Sprawdza:
- dopasowanie par obraz-maska (po stem nazwy pliku)
- spójność rozdzielczości
- brak pustych masek
- statystyki pokrycia (wykrywa outlier-y)

Zwraca exit code 0 (PASS) lub 1 (FAIL). Opcjonalnie zapisuje raport JSON (`--output`).

**`quality-gate.py`** — porównuje metryki nowego modelu z baseline'em. **Zdeprecjonowany** — logika przeniesiona do workflow YAML. Pozostawiony jako referencyjna implementacja i do lokalnych testów.

**`get-baseline-metrics.py`** — pobiera metryki aktualnego modelu Production z MLflow Model Registry. Fallback: jeśli brak modelu Production, zwraca baseline 0.0 (pierwsze trenowanie zawsze przechodzi). Wyjście: `--output json` lub `--output simple`.

**`promote-model.py`** — rejestruje run MLflow jako nową wersję modelu i przenosi ją do wskazanego stage (domyślnie Production), archiwizując poprzednią. Parametr wymagany: `--run-id`.

**`update-model-metadata.py`** — aktualizuje plik `model-metadata.json` o metryki, wersję i timestamp. Merguje z istniejącymi danymi.

**`train-with-retry.py`** — wrapper treningowy z retry do 3 prób i różnymi seed-ami. **Zdeprecjonowany** — retry logic przeniesiony do GitHub Actions. Pozostawiony dla celów dokumentacyjnych.
