#!/bin/bash

# GeoServer Cluster Scaling Script
# Usage: ./scale-cluster.sh [up|down] [number_of_instances]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
CADDY_FILE="$PROJECT_DIR/scripts/docker/build/caddy/Caddyfile"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo "Warning: .env file not found. Using default values."
    GEOSERVER_BASE_PORT=8081
fi

usage() {
    echo "Usage: $0 [up|down] [number_of_instances]"
    echo "  up:   Scale up to the specified number of instances"
    echo "  down: Scale down to the specified number of instances"
    echo "  Examples:"
    echo "    $0 up 4     # Scale up to 4 GeoServer instances"
    echo "    $0 down 2   # Scale down to 2 GeoServer instances"
}

generate_geoserver_service() {
    local node_num=$1
    local port=$((GEOSERVER_BASE_PORT + node_num - 1))
    
    cat << EOF

  ### Geoserver-$node_num
  gs-node$node_num:
    image: geobeyond/geoserver:2.20.6
    volumes:
      - \${GEOSERVER_DATA_MNT}:\${GEOSERVER_DATA_DIR}
      - \${GEOSERVER_CACHE_MNT}:\${GEOSERVER_CACHE_DIR}
    ports:
      - "$port:8080"
    environment:
      - GEOSERVER_DATA_DIR=\${GEOSERVER_DATA_DIR} 
      - GEOWEBCACHE_CACHE_DIR=\${GEOSERVER_CACHE_DIR}
      - RECREATE_DATADIR=FALSE
      - BROKER_URL=tcp://0.0.0.0:61616
      - GEOSERVER_ADMIN_PASSWORD=\${GEOSERVER_ADMIN_PASSWORD}
      - GEOSERVER_ADMIN_USER=\${GEOSERVER_ADMIN_USER}
      - READONLY=disabled
      - CLUSTER_DURABILITY=false
      - CLUSTERING=True
      - TOGGLE_MASTER=true
      - TOGGLE_SLAVE=true
      - EMBEDDED_BROKER=disabled
      - CLUSTER_CONNECTION_RETRY_COUNT=10
      - CLUSTER_CONNECTION_MAX_WAIT=500
      - DB_BACKEND=POSTGRES
      - HOST=db
      - POSTGRES_PORT=5432
      - POSTGRES_DB=gis
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASS=\${POSTGRES_PASS}
      - SSL_MODE=allow
      - RANDOMSTRING=23bd87cfa327d47e-node$node_num
      - INSTANCE_STRING=ac3bcba2fa7d989678a01ef4facc4173010cd8b40d2e5f5a8d18d5f863ca976f-node$node_num
      - SAMPLE_DATA=false
    restart: on-failure
    depends_on:
      db:
        condition: service_healthy
      geobroker:
        condition: service_healthy
    healthcheck:
      test: curl --fail -s http://localhost:8080/geoserver/web || exit 1
      interval: 1m30s
      timeout: 10s
      retries: 3
      start_period: 100s
    deploy:
      resources:
        limits:
          memory: \${GEOSERVER_MEMORY_LIMIT:-2G}
          cpus: '\${GEOSERVER_CPU_LIMIT:-1.0}'
        reservations:
          memory: \${GEOSERVER_MEMORY_RESERVATION:-1G}
          cpus: '\${GEOSERVER_CPU_RESERVATION:-0.5}'
    networks:
      - geocluster
    labels:
      org.label-schema.group: "geoserver"
EOF
}

update_caddy_config() {
    local num_instances=$1
    local backends=""
    
    for i in $(seq 1 $num_instances); do
        backends="$backends gs-node$i:8080"
    done
    
    cat > "$CADDY_FILE" << EOF
:8600 {
  reverse_proxy $backends {
    lb_policy           round_robin
    lb_try_duration     1s
    lb_try_interval     250ms
    health_uri          /geoserver/web
    health_interval     30s
    health_timeout      5s
    health_status       200
  }
  
  header {
    X-Forwarded-For {remote_host}
    X-Real-IP {remote_host}
  }
  
  log {
    output stdout
    format console
  }
}
EOF
    
    echo "Updated Caddy configuration for $num_instances instances"
}

update_compose_file() {
    local num_instances=$1
    
    # Create a temporary file
    local temp_file=$(mktemp)
    
    # Copy everything up to the first geoserver service
    awk '/### Geoserver-1/{exit} {print}' "$COMPOSE_FILE" > "$temp_file"
    
    # Generate all geoserver services
    for i in $(seq 1 $num_instances); do
        generate_geoserver_service $i >> "$temp_file"
    done
    
    # Add the rest of the services (everything after the last geoserver service)
    awk '/### Load balancer/{found=1} found{print}' "$COMPOSE_FILE" >> "$temp_file"
    
    # Replace the original file
    mv "$temp_file" "$COMPOSE_FILE"
    
    echo "Updated docker-compose.yml for $num_instances GeoServer instances"
}

update_caddy_dependencies() {
    local num_instances=$1
    local dependencies=""
    
    for i in $(seq 1 $num_instances); do
        dependencies="$dependencies      gs-node$i:\n        condition: service_healthy\n"
    done
    
    # Update the caddy service dependencies
    sed -i.bak "/depends_on:/,/condition: service_healthy/ {
        /depends_on:/!{/condition: service_healthy/!d;}
        /depends_on:/{
            r /dev/stdin
        }
    }" "$COMPOSE_FILE" << EOF
    depends_on:
$(echo -e "$dependencies")      geobroker:
        condition: service_healthy
EOF
    
    rm -f "$COMPOSE_FILE.bak"
}

if [ $# -ne 2 ]; then
    usage
    exit 1
fi

ACTION=$1
NUM_INSTANCES=$2

if ! [[ "$NUM_INSTANCES" =~ ^[0-9]+$ ]] || [ "$NUM_INSTANCES" -lt 1 ]; then
    echo "Error: Number of instances must be a positive integer"
    exit 1
fi

case $ACTION in
    up|down)
        echo "Scaling GeoServer cluster to $NUM_INSTANCES instances..."
        update_compose_file $NUM_INSTANCES
        update_caddy_config $NUM_INSTANCES
        update_caddy_dependencies $NUM_INSTANCES
        
        echo "Cluster scaling configuration updated successfully!"
        echo "Run 'docker compose up -d' to apply the changes."
        ;;
    *)
        echo "Error: Invalid action '$ACTION'"
        usage
        exit 1
        ;;
esac