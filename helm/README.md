# helm/

Chart Helmowy do deploymentu serwisu ML na k3s. Jeden chart (`ml-model`) obsługuje zarówno serving modelu, jak i ekspozycję metryk dla Prometheusa.

## Struktura

```
ml-model/
├── Chart.yaml          # metadata chartu (wersja 1.0.0)
├── values.yaml         # domyślne wartości — większość nadpisywana przez CI
└── templates/
    ├── _helpers.tpl        # helpery nazewnicze (fullname, labels itp.)
    ├── deployment.yaml     # Deployment Kubernetes
    ├── service.yaml        # Service (NodePort)
    └── servicemonitor.yaml # ServiceMonitor dla Prometheusa
```

## Konfiguracja

Kluczowe wartości w `values.yaml` — w CI nadpisywane przez `--set` lub osobny plik wartości:

| Klucz | Domyślna wartość | Opis |
|---|---|---|
| `image.repository` | *(wymagane)* | URL repozytorium ECR |
| `image.tag` | `latest` | Tag obrazu Docker |
| `service.type` | `NodePort` | Bez LoadBalancera (budżet) |
| `service.port` | `8000` | Port FastAPI |
| `resources.limits` | 512Mi / 500m | Limity dla poda |
| `env.MLFLOW_TRACKING_URI` | *(opcjonalne)* | URI MLflow dla dynamicznego ładowania modelu |
| `serviceMonitor.enabled` | `true` | Scraping Prometheusa co 30s na `/metrics` |
| `livenessProbe` | `/health`, delay 30s | Restart poda gdy endpoint nie odpowiada |
| `readinessProbe` | `/health`, delay 15s | Ruch dopiero po gotowości poda |

## Deployment z CLI

```bash
helm upgrade --install ml-model ./helm/ml-model \
  --set image.repository=<ecr-url>/wms-model \
  --set image.tag=<git-sha> \
  --set env.MLFLOW_TRACKING_URI=http://localhost:5000
```

## Ważne szczegóły implementacyjne

**`hostNetwork: true`** w deployment — pod używa sieci hosta, co pozwala serwisowi modelowemu łączyć się z MLflow przez `localhost:5000` zamiast przez wewnętrzny DNS klastra. Wynika to z architektury single-node k3s, gdzie MLflow działa bezpośrednio na hoście jako serwis systemd.

**NodePort zamiast LoadBalancera** — AWS LoadBalancer kosztuje ~$18/mies., NodePort jest darmowy. Serwis dostępny przez `http://<EC2_IP>:<nodePort>`.

**ECR authentication** — jeśli obraz jest prywatny, należy wcześniej utworzyć secret w k3s:
```bash
kubectl create secret docker-registry ecr-secret \
  --docker-server=<ecr-url> \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password)
```
i dodać `imagePullSecrets: [{name: ecr-secret}]` do values.

**ServiceMonitor** — wymaga działającego Prometheus Operator (instalowanego przez `install_monitoring=true` w Terraform). Jeśli monitoring jest wyłączony, `serviceMonitor.enabled: false`.
