# DF-docs
- [Installation](#installation)
  - [DigitalOcean](#digitalocean)
    - [Docker installation](#docker-installation)
  - [Docker Stack](#docker-stack)
    - [Main docker-compose.yml](#main-docker-composeyml)
    - [Monitoring docker-compose.yml](#monitoring-docker-composeyml)
    - [Launch docker stack](#launch-docker-stack)
- [Setup](#setup)
  - [InfluxDB](#influxdb)
    - [Environment variables](#environment-variables)
    - [Change the following values in the environment variables](#change-the-following-values-in-the-environment-variables)
  - [Telegraf](#telegraf)
    - [Telegraf config](#telegraf-config)
  - [Grafana](#grafana)
    - [Add Data Sources](#add-data-sources)
    - [InfluxDB source](#influxdb-source)
    - [Loki source](#loki-source)
    - [Prometheus source](#prometheus-source)


# Installation
## DigitalOcean:
Use Ubuntu 22-04

### Docker installation
```bash
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install the Docker packages
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Hello world test for docker
```bash
sudo docker run hello-world
```

## Docker Stack
### Main docker-compose.yml
```yml
services:
  # ---------------------------------------------------------------
  # InfluxDB service
  # ---------------------------------------------------------------
  influxdb:
    container_name: influxdb         # Name the container "influxdb"
    image: influxdb:2               # Use the official InfluxDB v2 image
    env_file:
      - .env                        # Load environment variables from the .env file
    volumes:
      - influxdb-storage:/var/lib/influxdb2  # Named volume to persist InfluxDB data
      - ./entrypoint.sh:/entrypoint.sh:ro     # Mount custom entrypoint script (read-only)
    entrypoint: ["/entrypoint.sh"]  # Use our script as the container entrypoint
    ports:
      - "8086:8086"   # Map host port to container port 8086
    restart: unless-stopped         # Automatically restart unless manually stopped
    networks:
      - monitoring                  # Attach the container to the "monitoring" network
    healthcheck:
      # Use InfluxDB’s built-in /health endpoint to verify the service is up.
      test: ["CMD", "curl", "--fail", "http://localhost:8086/health"]
      interval: 30s                 # Interval between health checks
      timeout: 10s                  # Time to wait for a response before marking as failed
      retries: 3                    # Number of consecutive failures before "unhealthy"
      start_period: 30s             # Grace period before starting health checks

  # ---------------------------------------------------------------
  # Telegraf service
  # ---------------------------------------------------------------
  telegraf:
    container_name: telegraf
    image: telegraf:latest
    env_file:
      - .env                        # Load environment variables from the .env file
    environment:
      - INFLUX_TOKEN=${INFLUX_TOKEN}  # Pass the InfluxDB token into the container
    volumes:
      - ./telegraf.conf:/etc/telegraf/telegraf.conf:ro  # Mount telegraf.conf (read-only)
    command: telegraf --config /etc/telegraf/telegraf.conf  
      # Override the default command to point to the config file
    depends_on:
      - influxdb                    # Ensure InfluxDB is started before Telegraf
    restart: unless-stopped
    networks:
      - monitoring
    healthcheck:
      # Simple check to confirm the Telegraf process is running
      test: ["CMD", "pgrep", "telegraf"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  ################################################
  # Grafana
  ################################################
  grafana:
    container_name: grafana
    image: grafana/grafana:latest
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - TZ=Etc/UTC
      - GF_PATHS_DATA=/var/lib/grafana
      - GF_PATHS_LOGS=/var/log/grafana
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
      - grafana-log:/var/log/grafana
    healthcheck:
      test: ["CMD", "wget", "-O", "/dev/null", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped
    networks:
      - monitoring

  ################################################
  # Mosquitto
  ################################################
  mosquitto:
    container_name: mosquitto
    image: eclipse-mosquitto:latest
    environment:
      - TZ=${TZ:-Etc/UTC}
    # Expose the MQTT port
    ports:
      - "1883:1883"
    # Use named volumes for data and logs, no config override
    volumes:
      - mosquitto-data:/mosquitto/data
      - mosquitto-log:/mosquitto/log
    restart: unless-stopped
    networks:
      - monitoring

  # ---------------------------------------------------------------
  # Portainer CE (Container management UI)
  # ---------------------------------------------------------------
  portainer-ce:
    container_name: portainer-ce
    image: portainer/portainer-ce:latest
    ports:
      - "8000:8000"  # Required for Portainer Edge agent
      - "9000:9000"  # Main Portainer UI
      - "9443:9443"  # HTTPS port for Portainer
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock  
        # Allow Portainer to communicate with Docker engine
      - ./volumes/portainer-ce/data:/data
        # Persist Portainer data (users, settings, etc.)
    restart: unless-stopped
    networks:
      - monitoring

# ---------------------------------------------------------------
# Named volumes
# ---------------------------------------------------------------
volumes:
  influxdb-storage:
  grafana-data:
  grafana-log:
  mosquitto-data:
  mosquitto-log:

# ---------------------------------------------------------------
# Docker network
# ---------------------------------------------------------------
networks:
  monitoring:
    driver: bridge  # Use a user-defined bridged network for all services
```
### Monitoring docker-compose.yml
```yml
services:
  # ---------------------------------------------------------------
  # cAdvisor - Analyzes and exposes resource usage and performance data 
  # from running containers
  # ---------------------------------------------------------------
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest   # Official cAdvisor image
    container_name: cadvisor                 # Name the container "cadvisor"
    restart: unless-stopped                  # Auto-restart unless manually stopped
    ports:
      - "8080:8080"                          # Expose cAdvisor UI on host port 8080
    privileged: true                         # Gives cAdvisor ability to read all cgroup data
    volumes:
      - /:/rootfs:ro                         # Mount the root filesystem as read-only
      - /sys:/sys:ro                         # Mount /sys directory, read-only for cgroup data
      - /var/lib/docker:/var/lib/docker:ro   # Read-only access to Docker data
      - /var/run/docker.sock:/var/run/docker.sock:ro  
        # Read-only access to Docker socket, allows cAdvisor to monitor containers

  # ---------------------------------------------------------------
  # Prometheus - Collects metrics from cAdvisor and other endpoints
  # ---------------------------------------------------------------
  prometheus:
    image: prom/prometheus:latest            # Official Prometheus image
    container_name: prometheus               # Name the container "prometheus"
    restart: unless-stopped                  # Auto-restart unless manually stopped
    ports:
      - "9090:9090"                          # Prometheus accessible on host port 9090
    volumes:
      - /opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro  
        # Mount the Prometheus config file from host into the container (read-only)

  # ---------------------------------------------------------------
  # Loki - A log aggregation system from Grafana
  # ---------------------------------------------------------------
  loki:
    image: grafana/loki:latest               # Official Loki image
    container_name: loki                     # Name the container "loki"
    restart: unless-stopped                  # Auto-restart unless manually stopped
    ports:
      - "3100:3100"                          # Loki API/UI accessible on host port 3100
    command: -config.file=/etc/loki/local-config.yaml  
      # Use the provided configuration file for Loki
    volumes:
      - loki_data:/loki                      # Named volume for storing Loki data
      - /opt/loki/loki-config.yaml:/etc/loki/local-config.yaml:ro  
        # Read-only mount of Loki’s config from the host

  # ---------------------------------------------------------------
  # Promtail - Agent that collects logs and sends them to Loki
  # ---------------------------------------------------------------
  promtail:
    image: grafana/promtail:latest           # Official Promtail image
    container_name: promtail                 # Name the container "promtail"
    restart: unless-stopped                  # Auto-restart unless manually stopped
    volumes:
      - /var/log:/var/log:ro                 # Read-only mount of system logs
      - /var/lib/docker/containers:/var/lib/docker/containers:ro  
        # Access container logs (if file-based scraping is still desired)
      - /etc/promtail:/etc/promtail:ro       # Mount Promtail config directory (read-only)
      - /tmp:/tmp                            # Used for storing Promtail's positions and temp data
      - /var/run/docker.sock:/var/run/docker.sock:ro  
        # Read-only access to Docker socket for Docker service discovery
    command: -config.file=/etc/promtail/promtail-config.yaml
      # Load the configuration file for Promtail

# ---------------------------------------------------------------
# Named volumes for persistent data storage
# ---------------------------------------------------------------
volumes:
  loki_data:
    # Data volume used by Loki to store logs
```

### Launch docker stack
```bash
docker-compose up -d 
```


# Setup
## InfluxDB
### Environment variables:
### **Change the following values in the environment variables**
Set username and password
Generate admin Token through linux cli
```bash
openssl rand -hex 32
```
Set primary organization and bucket

```env
DOCKER_INFLUXDB_INIT_MODE=setup

## Environment variables used during the setup and operation of the stack
#

# Primary InfluxDB admin/superuser credentials
#
DOCKER_INFLUXDB_INIT_USERNAME=changeme
DOCKER_INFLUXDB_INIT_PASSWORD=changeme 
DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=changeme 

# Primary InfluxDB organization & bucket definitions
# 
DOCKER_INFLUXDB_INIT_ORG=changeme 
DOCKER_INFLUXDB_INIT_BUCKET=changeme 

# Primary InfluxDB bucket retention period
#
# NOTE: Valid units are nanoseconds (ns), microseconds(us), milliseconds (ms)
# seconds (s), minutes (m), hours (h), days (d), and weeks (w).
DOCKER_INFLUXDB_INIT_RETENTION=0s
# 0s means forever

# InfluxDB hostname definition
DOCKER_INFLUXDB_INIT_HOST=influxdb 

# Telegraf configuration file
# 
# Will be mounted to container and used as telegraf configuration
TELEGRAF_CFG_PATH=./telegraf/telegraf.conf
```
### The fo


## Telegraf

telegraf docker compose:
```yml
  telegraf:
    container_name: telegraf
    image: telegraf:latest
    env_file:
      - .env                        # Load environment variables from the .env file
    environment:
      - INFLUX_TOKEN=${INFLUX_TOKEN}  # Pass the InfluxDB token into the container
    volumes:
      - ./telegraf.conf:/etc/telegraf/telegraf.conf:ro  # Mount telegraf.conf (read-only)
    command: telegraf --config /etc/telegraf/telegraf.conf  
      # Override the default command to point to the config file
    depends_on:
      - influxdb                    # Ensure InfluxDB is started before Telegraf
    restart: unless-stopped
    networks:
      - monitoring
    healthcheck:
      # Simple check to confirm the Telegraf process is running
      test: ["CMD", "pgrep", "telegraf"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

The Telegraf config contains outputs for InfluxDB :
	url, token, organization and primary bucket, which are pulled from the environment variables
It also has some basic server monitoring data inputs
### Telegraf config
```config
[global_tags]
[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  hostname = ""
  omit_hostname = false
[[outputs.influxdb_v2]]
  urls = ["http://${DOCKER_INFLUXDB_INIT_HOST}:8086"]
  token = "$DOCKER_INFLUXDB_INIT_ADMIN_TOKEN"
  organization = "$DOCKER_INFLUXDB_INIT_ORG"
  bucket = "$DOCKER_INFLUXDB_INIT_BUCKET"
  insecure_skip_verify = false
[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false
[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]
```


## Grafana
- [Add Data Sources](#add-data-sources)
- [InfluxDB source](#influxdb-source)
- [Loki source](#loki-source)
- [Prometheus source](#prometheus-source)
### Add Data Sources
![image](https://github.com/user-attachments/assets/21aa52d6-b549-4f3b-ad50-8b0a2394a037)

### Influxdb source
Choose flux language
URL
```
http://host.docker.internal:8086
```
Set Organization, Token and default bucket
![image](https://github.com/user-attachments/assets/799c2df8-4fc6-43e8-a4df-184814d864bf)

### Loki source
Make sure to use the provided configuration file when setting up Loki
URL
```
http://host.docker.internal:3100
```
![image](https://github.com/user-attachments/assets/4d08cc46-38c7-41ed-9c90-e2c33d1184a3)


### Prometheus source
URL
```
http://host.docker.internal:9090
```
![image](https://github.com/user-attachments/assets/8671255c-99a4-4d2a-9ee7-f80ae3b94784)

## Monitoring

