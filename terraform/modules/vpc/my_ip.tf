# Automatically detect your public IP for security group rules
# This eliminates the need to manually specify my_ip variable

data "http" "my_ip" {
  url = "https://api.ipify.org"
}

locals {
  # Add /32 CIDR notation for single IP
  my_ip_cidr = "${chomp(data.http.my_ip.response_body)}/32"
}

# Optional: Output for debugging
output "detected_public_ip" {
  description = "Auto-detected public IP used for security group rules"
  value       = local.my_ip_cidr
}
