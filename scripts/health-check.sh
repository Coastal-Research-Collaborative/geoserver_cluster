#!/bin/bash

# GeoServer Cluster Health Check Script
# This script checks the health of the entire cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    GEOSERVER_BASE_PORT=8081
    GEOSERVER_INSTANCES=2
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_service_health() {
    local service_name=$1
    local url=$2
    local expected_status=${3:-200}
    
    echo -n "Checking $service_name... "
    
    if response=$(curl -s -w "%{http_code}" -o /dev/null --max-time 10 "$url" 2>/dev/null); then
        if [ "$response" -eq "$expected_status" ]; then
            echo -e "${GREEN}✓ Healthy${NC} (HTTP $response)"
            return 0
        else
            echo -e "${RED}✗ Unhealthy${NC} (HTTP $response)"
            return 1
        fi
    else
        echo -e "${RED}✗ Unreachable${NC}"
        return 1
    fi
}

check_geoserver_cluster() {
    echo "=== GeoServer Cluster Health Check ==="
    
    local healthy_nodes=0
    local total_nodes=$GEOSERVER_INSTANCES
    
    for i in $(seq 1 $total_nodes); do
        local port=$((GEOSERVER_BASE_PORT + i - 1))
        if check_service_health "GeoServer Node $i" "http://localhost:$port/geoserver/web"; then
            ((healthy_nodes++))
        fi
    done
    
    echo
    if [ $healthy_nodes -eq $total_nodes ]; then
        echo -e "${GREEN}✓ All $total_nodes GeoServer nodes are healthy${NC}"
        return 0
    elif [ $healthy_nodes -gt 0 ]; then
        echo -e "${YELLOW}⚠ Only $healthy_nodes/$total_nodes GeoServer nodes are healthy${NC}"
        return 1
    else
        echo -e "${RED}✗ No GeoServer nodes are healthy${NC}"
        return 2
    fi
}

check_supporting_services() {
    echo "=== Supporting Services Health Check ==="
    
    local services_healthy=0
    local total_services=6
    
    # Check Load Balancer
    if check_service_health "Load Balancer (Caddy)" "http://localhost:${CADDY_PORT:-8600}"; then
        ((services_healthy++))
    fi
    
    # Check Database
    if check_service_health "PostgreSQL" "http://localhost:${POSTGRES_PORT:-25432}" 000 2>/dev/null || \
       docker compose exec -T db pg_isready -h localhost -U ${POSTGRES_USER:-docker} >/dev/null 2>&1; then
        echo -e "PostgreSQL... ${GREEN}✓ Healthy${NC}"
        ((services_healthy++))
    else
        echo -e "PostgreSQL... ${RED}✗ Unhealthy${NC}"
    fi
    
    # Check ActiveMQ
    if check_service_health "ActiveMQ Broker" "http://localhost:${ACTIVEMQ_WEB_PORT:-8161}"; then
        ((services_healthy++))
    fi
    
    # Check Prometheus
    if check_service_health "Prometheus" "http://localhost:${PROMETHEUS_PORT:-9090}"; then
        ((services_healthy++))
    fi
    
    # Check Grafana
    if check_service_health "Grafana" "http://localhost:${GRAFANA_PORT:-3000}"; then
        ((services_healthy++))
    fi
    
    # Check if containers are running
    echo -n "Docker containers... "
    local running_containers=$(docker compose ps --services --filter "status=running" | wc -l)
    local total_containers=$(docker compose ps --services | wc -l)
    
    if [ $running_containers -eq $total_containers ]; then
        echo -e "${GREEN}✓ All containers running${NC} ($running_containers/$total_containers)"
        ((services_healthy++))
    else
        echo -e "${YELLOW}⚠ Some containers not running${NC} ($running_containers/$total_containers)"
    fi
    
    echo
    if [ $services_healthy -eq $total_services ]; then
        echo -e "${GREEN}✓ All supporting services are healthy${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ $services_healthy/$total_services supporting services are healthy${NC}"
        return 1
    fi
}

test_load_balancing() {
    echo "=== Load Balancing Test ==="
    
    local lb_url="http://localhost:${CADDY_PORT:-8600}/geoserver/web"
    local test_requests=10
    
    echo "Testing load balancing with $test_requests requests..."
    
    for i in $(seq 1 $test_requests); do
        if response=$(curl -s -w "Server: %{remote_ip}:%{remote_port}\n" -o /dev/null "$lb_url" 2>/dev/null); then
            echo "Request $i: Load balancer responded"
        else
            echo "Request $i: Failed"
        fi
    done
    
    echo -e "${GREEN}✓ Load balancing test completed${NC}"
}

show_cluster_status() {
    echo "=== Cluster Status Summary ==="
    
    echo "Docker Compose Services:"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    echo "Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
}

main() {
    echo "GeoServer Cluster Health Check"
    echo "==============================="
    echo "Timestamp: $(date)"
    echo
    
    local exit_code=0
    
    # Run health checks
    if ! check_geoserver_cluster; then
        exit_code=1
    fi
    
    echo
    if ! check_supporting_services; then
        exit_code=1
    fi
    
    echo
    test_load_balancing
    
    echo
    show_cluster_status
    
    echo
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}🎉 Cluster is fully healthy and operational!${NC}"
    else
        echo -e "${YELLOW}⚠️  Cluster has some issues that need attention.${NC}"
    fi
    
    exit $exit_code
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi