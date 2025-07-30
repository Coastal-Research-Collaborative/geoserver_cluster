#!/bin/bash

# GeoServer Cluster Deployment Script
# Makes it easy to deploy the container setup on any server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

print_banner() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "    GeoServer Cluster Deployment Script"
    echo "=================================================="
    echo -e "${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    print_status "Prerequisites check passed ✓"
}

setup_environment() {
    print_status "Setting up environment..."
    
    # Create .env file if it doesn't exist
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            print_status "Creating .env file from .env.example"
            cp .env.example .env
        else
            print_error "Neither .env nor .env.example found. Cannot proceed."
            exit 1
        fi
    else
        print_status "Using existing .env file"
    fi
    
    # Create necessary directories
    mkdir -p geoserver-data geoserver-cache
    
    # Set proper permissions for data directories
    if [ "$(uname)" = "Linux" ]; then
        sudo chown -R 1000:1000 geoserver-data geoserver-cache 2>/dev/null || true
    fi
    
    print_status "Environment setup complete ✓"
}

check_ports() {
    print_status "Checking port availability..."
    
    # Load environment variables
    set -a
    source .env
    set +a
    
    # Ports to check
    PORTS_TO_CHECK=(
        "$POSTGRES_PORT:PostgreSQL"
        "8161:ActiveMQ Web"
        "61616:ActiveMQ Broker"
        "8081:GeoServer Node 1"
        "8082:GeoServer Node 2"
        "8600:Caddy Load Balancer"
        "9090:Prometheus"
        "3000:Grafana"
    )
    
    for port_info in "${PORTS_TO_CHECK[@]}"; do
        port="${port_info%%:*}"
        service="${port_info##*:}"
        
        if ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; then
            print_warning "Port $port ($service) is already in use"
        fi
    done
    
    print_status "Port check complete ✓"
}

deploy_cluster() {
    print_status "Deploying GeoServer cluster..."
    
    # Pull latest images
    print_status "Pulling Docker images..."
    docker compose pull
    
    # Build custom images if needed
    print_status "Building custom images..."
    docker compose build
    
    # Start the cluster
    print_status "Starting services..."
    docker compose up -d
    
    print_status "Deployment initiated ✓"
}

wait_for_services() {
    print_status "Waiting for services to become healthy..."
    
    # Wait for services to start
    sleep 10
    
    # Check service health
    max_attempts=30
    attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if docker compose ps | grep -q "Up (healthy)"; then
            healthy_services=$(docker compose ps | grep -c "Up (healthy)" || echo "0")
            total_services=$(docker compose ps | grep -c "Up" || echo "0")
            
            print_status "Services status: $healthy_services/$total_services healthy"
            
            # Check if core services (db, geobroker, gs-node1, gs-node2, caddy) are healthy
            core_healthy=0
            for service in "db" "geobroker" "gs-node1" "gs-node2" "caddy"; do
                if docker compose ps "$service" 2>/dev/null | grep -q "Up (healthy)"; then
                    core_healthy=$((core_healthy + 1))
                fi
            done
            
            if [ "$core_healthy" -eq 5 ]; then
                print_status "Core services are healthy ✓"
                break
            fi
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    
    if [ $attempt -eq $max_attempts ]; then
        print_warning "Some services may still be starting up. Check with 'docker compose ps'"
    fi
}

show_access_info() {
    print_status "Deployment complete! Access information:"
    echo ""
    echo -e "${BLUE}Services Access URLs:${NC}"
    echo "  • GeoServer Cluster (Load Balanced): http://localhost:8600"
    echo "  • GeoServer Node 1: http://localhost:8081"
    echo "  • GeoServer Node 2: http://localhost:8082"
    echo "  • Grafana Dashboard: http://localhost:3000"
    echo "  • Prometheus: http://localhost:9090"
    echo "  • ActiveMQ Console: http://localhost:8161"
    echo ""
    echo -e "${BLUE}Default Credentials:${NC}"
    echo "  • GeoServer: admin/geoserver"
    echo "  • Grafana: admin/admin (or check GRAFANA_ADMIN_PASSWORD in .env)"
    echo "  • ActiveMQ: admin/admin"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  • Check status: docker compose ps"
    echo "  • View logs: docker compose logs -f [service_name]"
    echo "  • Scale cluster: ./scripts/scale-cluster.sh up 4"
    echo "  • Health check: ./scripts/health-check.sh"
    echo "  • Stop cluster: docker compose down"
    echo ""
}

create_backup() {
    print_status "Creating deployment backup..."
    
    backup_dir="deployment-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Copy essential files
    cp docker compose.yml "$backup_dir/"
    cp .env "$backup_dir/"
    cp -r build_data "$backup_dir/" 2>/dev/null || true
    cp -r scripts "$backup_dir/" 2>/dev/null || true
    
    # Create archive
    tar -czf "${backup_dir}.tar.gz" "$backup_dir"
    rm -rf "$backup_dir"
    
    print_status "Backup created: ${backup_dir}.tar.gz"
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --check-only    Only check prerequisites and ports"
    echo "  -b, --backup        Create deployment backup"
    echo "  -q, --quick         Quick deployment (skip health checks)"
    echo "  --no-pull           Skip pulling latest images"
    echo ""
    echo "Examples:"
    echo "  $0                  Full deployment with health checks"
    echo "  $0 -q               Quick deployment without waiting"
    echo "  $0 -c               Check system readiness only"
    echo "  $0 -b               Create deployment backup"
}

# Main execution
main() {
    print_banner
    
    # Parse command line arguments
    QUICK_MODE=false
    CHECK_ONLY=false
    CREATE_BACKUP=false
    NO_PULL=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--check-only)
                CHECK_ONLY=true
                shift
                ;;
            -b|--backup)
                CREATE_BACKUP=true
                shift
                ;;
            -q|--quick)
                QUICK_MODE=true
                shift
                ;;
            --no-pull)
                NO_PULL=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Execute based on mode
    check_prerequisites
    setup_environment
    check_ports
    
    if [ "$CHECK_ONLY" = true ]; then
        print_status "System check complete. Ready for deployment!"
        exit 0
    fi
    
    if [ "$CREATE_BACKUP" = true ]; then
        create_backup
        exit 0
    fi
    
    deploy_cluster
    
    if [ "$QUICK_MODE" = false ]; then
        wait_for_services
    fi
    
    show_access_info
}

# Run main function
main "$@"
