# terraform/

Infrastruktura AWS jako kod. Całość opiera się na jednej instancji EC2 z k3s — świadomy kompromis budżetowy zamiast EKS/RDS/NAT Gateway.

## Struktura

```
terraform/
├── main.tf         # korzeń: wywołuje moduły, konfiguruje providera
├── variables.tf    # zmienne wejściowe (region, instance type, nazwy bucketów)
├── outputs.tf      # adresy, URL-e, komendy SSH po apply
└── modules/
    ├── vpc/            # sieć: VPC, subnet, IGW, security group
    ├── s3-mlops/       # storage: dwa buckety S3 (DVC + MLflow)
    ├── ecr/            # rejestr Docker dla obrazów modelu
    ├── ec2-k3s/        # instancja EC2 z k3s, MLflow, GitHub Actions runner
    └── iam-github-oidc/  # OIDC dla GitHub Actions (wyłączony w AWS Academy)
```

## Moduły

### vpc

Minimalna sieć publiczna (brak NAT Gateway — koszt ~$32/mies.):

- VPC `10.0.0.0/16` + jeden public subnet `10.0.1.0/24`
- Security group: SSH (22) i FastAPI (8000) tylko z IP użytkownika (auto-detect), MLflow (5000) otwarty na `0.0.0.0/0` (potrzebne dla GitHub Actions)

### s3-mlops

Dwa oddzielne buckety z włączonym wersjonowaniem i zablokowanym dostępem publicznym:

- **DVC bucket** — dane treningowe (obrazy + maski), zarządzane przez DVC
- **MLflow bucket** — artefakty modeli, logi, wykresy z treningu

### ecr

Rejestr Docker z polityką lifecycle: zatrzymuje ostatnie 5 tagów, starsze usuwa automatycznie. Image scanning wyłączony (koszt). `force_destroy = true` dla czystego `terraform destroy`.

### ec2-k3s

Główny węzeł obliczeniowy:

- AMI: Amazon Linux 2023 (wspierany do 2028)
- Instancja: `t3.large` (8GB RAM) — minimum dla PyTorch images (~9GB skompresowane)
- Dysk: 100GB gp3 — zwiększony z 40GB po problemach z DiskPressure na k3s
- IAM: `LabInstanceProfile` (predefiniowany w AWS Academy; własne role IAM zablokowane)
- Elastic IP dla stabilnego adresu między restartami sesji

User-data przy starcie instaluje: Docker, k3s, Helm, MLflow (systemd), GitHub Actions runner, opcjonalnie Prometheus + Grafana.

### iam-github-oidc

**Aktualnie wyłączony** w `main.tf` (AWS Academy Learner Lab blokuje tworzenie ról IAM). Moduł gotowy do włączenia w standardowym koncie AWS — definiuje OIDC provider dla `token.actions.githubusercontent.com` i rolę IAM z dostępem do S3 i ECR.

## Użycie

```bash
# Inicjalizacja (raz)
cd terraform && terraform init

# Podgląd zmian
terraform plan

# Lub najlepiej wskazać ścieżkę ręcznie
terraform plan -var-file=D:\...\Water-Meters-Segmentation-Autimatization\devops\terraform\terraform.tfvars

# Tworzenie infrastruktury
terraform apply   # lub użyj scripts/deploy-to-cloud.sh

# Lub najlepiej wskazać ścieżkę ręcznie
terraform apply -var-file=D:\...\Water-Meters-Segmentation-Autimatization\devops\terraform\terraform.tfvars -auto-approve

# Niszczenie (pamiętaj o opróżnieniu S3 najpierw)
terraform destroy   # lub użyj scripts/cleanup-aws.sh
```

Wartości zmiennych trzymaj w pliku `terraform.tfvars` (w `.gitignore`):

```hcl
key_name      = "labsuser"
dvc_bucket    = "wms-dvc-data-<account-id>"
mlflow_bucket = "wms-mlflow-artifacts-<account-id>"
```

## Outputs po apply

| Output               | Przykład                                                    |
| -------------------- | ----------------------------------------------------------- |
| `ec2_public_ip`      | `13.219.216.230`                                            |
| `mlflow_url`         | `http://13.219.216.230:5000`                                |
| `ecr_repository_url` | `055677744286.dkr.ecr.eu-central-1.amazonaws.com/wms-model` |
| `ssh_command`        | `ssh -i ~/.ssh/labsuser.pem ec2-user@13.219.216.230`        |

## Monitoring (opcjonalny)

Prometheus + Grafana wyłączone domyślnie (~750MB RAM, ~2GB dysku). Włączenie:

```hcl
# terraform.tfvars
install_monitoring = true
grafana_password   = "haslo"
```

Dashboardy dostępne przez SSH tunnel:

```bash
ssh -L 3000:localhost:3000 ec2-user@<EC2_IP>
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000  (admin / <grafana_password>)
```

## Ograniczenia AWS Academy

- Sesje wygasają co ~4h — EC2 może zmienić IP (Elastic IP temu zapobiega)
- Brak uprawnień do tworzenia ról IAM — stąd `LabInstanceProfile` i wyłączony moduł OIDC
- `s3:PutObject` zablokowany dla lokalnych credentiali — upload danych tylko przez GitHub Actions
- Klucz SSH: `~/.ssh/labsuser.pem`

## Troubleshooting

**User-data script failed** — sprawdź logi na EC2:

```bash
sudo cat /var/log/user-data.log
```

**MLflow lub k3s nie wystartował** — uruchom ręcznie:

```bash
./scripts/setup-k3s.sh
./scripts/setup-mlflow.sh
```

**S3 BucketAlreadyExists** — nazwy bucketów muszą być globalnie unikalne; dodaj suffix z account ID.
