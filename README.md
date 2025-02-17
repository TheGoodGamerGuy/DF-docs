# DF-docs
- [Installation](#installation)
	- [DigitalOcean](#digitalocean)
	- [Docker Stack](#docker-stack)

# Installation
## DigitalOcean:
Use Ubuntu 22-04

### Docker
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
### docker-compose.yml
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
      - "${DOCKER_INFLUXDB_INIT_PORT}:8086"   # Map host port to container port 8086
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

  # ---------------------------------------------------------------
  # Grafana service
  # ---------------------------------------------------------------
  grafana:
    container_name: grafana
    image: grafana/grafana:latest
    environment:
      - TZ=Etc/UTC                  # Set the timezone
      - GF_PATHS_DATA=/var/lib/grafana  # Where Grafana stores data
      - GF_PATHS_LOGS=/var/log/grafana  # Where Grafana stores logs
    ports:
      - "3000:3000"                 # Expose Grafana's web UI on port 3000
    volumes:
      - ./volumes/grafana/data:/var/lib/grafana  # Persist Grafana data
      - ./volumes/grafana/log:/var/log/grafana   # Persist Grafana logs
    healthcheck:
      # Attempt a simple download from Grafana to confirm it’s responding
      test: ["CMD", "wget", "-O", "/dev/null", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped
    networks:
      - monitoring

  # ---------------------------------------------------------------
  # Mosquitto (MQTT broker)
  # ---------------------------------------------------------------
  mosquitto:
    container_name: mosquitto
    build:
      context: ./.templates/mosquitto/.  
      # Docker build context located in the local ./.templates/mosquitto directory
      args:
        - MOSQUITTO_BASE=eclipse-mosquitto:latest  
          # Base image for building the Mosquitto container
    environment:
      - TZ=${TZ:-Etc/UTC}           # Set timezone, default is UTC
    ports:
      - "1883:1883"                 # Mosquitto MQTT default port
    volumes:
      - ./volumes/mosquitto/config:/mosquitto/config  # Config directory
      - ./volumes/mosquitto/data:/mosquitto/data      # Data directory
      - ./volumes/mosquitto/log:/mosquitto/log        # Log directory
      - ./volumes/mosquitto/pwfile:/mosquitto/pwfile  # Password file
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
    # Used by InfluxDB to persist data across container restarts

# ---------------------------------------------------------------
# Docker network
# ---------------------------------------------------------------
networks:
  monitoring:
    driver: bridge  # Use a user-defined bridged network for all services

```

### Launch docker stack
```bash
docker-compose up -d 
```
