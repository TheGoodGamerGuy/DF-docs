#!/bin/bash
#
# iotrunner.sh
#
# This script automates creating a DigitalOcean droplet for IoT services
# using Terraform. It prompts for the DO token, droplet name, and SSH
# key fingerprints, then spins up the droplet (with Docker installed).

# -------------------------------------------------------------------
# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color
# -------------------------------------------------------------------

echo -e "${YELLOW}Starting IoT infrastructure setup...${NC}"

# -------------------------------------------------------------------
# Prompt for droplet name
# -------------------------------------------------------------------
echo -e "${YELLOW}Enter the name of the droplet you want to create:${NC}"
read DROPLET_NAME
echo ""

# -------------------------------------------------------------------
# Prompt for DigitalOcean API token
# -------------------------------------------------------------------
echo -e "${YELLOW}Enter your DigitalOcean API token:${NC}"
read DIGITALOCEAN_TOKEN
echo ""

# -------------------------------------------------------------------
# Prompt for SSH fingerprints
# -------------------------------------------------------------------
echo -e """${YELLOW}Enter the SSH fingerprints (from your DigitalOcean Security settings).
Add one fingerprint per line; type 'done' when finished.${NC}"""
SSH_FINGERPRINTS=()
while true; do
    read -p "Fingerprint: " fingerprint
    if [ "$fingerprint" == "done" ]; then
        break
    fi
    SSH_FINGERPRINTS+=("\"$fingerprint\"")
done

SSH_FINGERPRINTS_STR=$(IFS=,; echo "${SSH_FINGERPRINTS[*]}")
echo ""

# -------------------------------------------------------------------
# Install/Update Terraform
# -------------------------------------------------------------------
echo -e "${YELLOW}Installing/updating Terraform...${NC}"
sudo apt-get update -y
sudo apt-get install -y gnupg software-properties-common curl

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository \
  "deb [arch=amd64] https://apt.releases.hashicorp.com \
  $(lsb_release -cs) main"
sudo apt-get update -y
sudo apt-get install -y terraform

# -------------------------------------------------------------------
# Write out terraform.tfvars with user inputs
# -------------------------------------------------------------------
cat << EOF > terraform.tfvars
droplet_name     = "${DROPLET_NAME}"
do_token         = "${DIGITALOCEAN_TOKEN}"
ssh_public_keys  = [
  ${SSH_FINGERPRINTS_STR}
]
EOF

echo -e "${GREEN}Created terraform.tfvars file with droplet name, DO token, and SSH fingerprints.${NC}"

# -------------------------------------------------------------------
# Initialize Terraform and plan
# -------------------------------------------------------------------
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

echo -e "${YELLOW}Creating Terraform plan...${NC}"
terraform plan -out=tfplan

# -------------------------------------------------------------------
# Prompt to apply
# -------------------------------------------------------------------
read -p "Do you want to apply the Terraform plan? (yes/no): " confirm
if [ "$confirm" = "yes" ] || [ "$confirm" = "y" ]; then
  echo -e "${YELLOW}Applying Terraform plan...${NC}"
  terraform apply tfplan

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Terraform apply completed successfully!${NC}"
    echo -e "${GREEN}Droplet IP:${NC} $(terraform output -raw droplet_ip)"
    echo -e "${YELLOW}Docker is installed on the droplet. You can now SCP your Compose files"
    echo -e "and run 'docker compose up -d' remotely or however you wish to finalize.${NC}"
  else
    echo -e "${RED}Terraform apply failed. Please check the errors above.${NC}"
  fi
else
  echo -e "${RED}Terraform apply canceled.${NC}"
fi
