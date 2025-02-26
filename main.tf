###########################
# main.tf
###########################

terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

###########################
# Variables
###########################
variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
}

variable "droplet_name" {
  description = "Name of the IoT droplet"
  type        = string
}

variable "ssh_public_keys" {
  description = "List of SSH key fingerprints to allow"
  type        = list(string)
}

###########################
# Provider
###########################
provider "digitalocean" {
  token = var.do_token
}

###########################
# Droplet resource
###########################
resource "digitalocean_droplet" "iot_stack" {
  name       = var.droplet_name
  image      = "ubuntu-22-04-x64"
  region     = "fra1"
  size       = "s-2vcpu-4gb"
  monitoring = true
  ssh_keys   = var.ssh_public_keys

  # Minimal user_data: install Docker, add an iot-user, etc.
  user_data = <<-EOF
    #!/bin/bash
    
    # Basic updates
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release

    # Docker repo
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      \$(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    
    apt-get update -y

    # Install Docker & docker-compose plugin
    apt-get install -y docker-ce docker-ce-cli containerd.io \
      docker-compose docker-compose-plugin

    # Create a non-root user
    useradd -m -s /bin/bash iot-user
    echo "iot-user:password" | chpasswd
    usermod -aG sudo iot-user
    usermod -aG docker iot-user

    # The droplet now has Docker installed. You can scp your
    # local Docker Compose files to /home/iot-user and run them
    # as needed.
  EOF
}

###########################
# Output
###########################
output "droplet_ip" {
  description = "Public IPv4 address of the IoT droplet"
  value       = digitalocean_droplet.iot_stack.ipv4_address
}
