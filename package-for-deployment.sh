#!/bin/bash

# Package GeoServer Cluster for Deployment
# Creates a portable package that can be deployed on any server

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[PACKAGE]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Package details
PACKAGE_NAME="geoserver-cluster-$(date +%Y%m%d-%H%M%S)"
PACKAGE_DIR="/tmp/$PACKAGE_NAME"

print_header "Creating deployment package: $PACKAGE_NAME"

# Create package directory
mkdir -p "$PACKAGE_DIR"

print_status "Copying essential files..."

# Copy core files
cp docker-compose.yml "$PACKAGE_DIR/"
cp .env "$PACKAGE_DIR/.env.production"
cp deploy.sh "$PACKAGE_DIR/"
cp README.md "$PACKAGE_DIR/"

# Copy configuration directories
print_status "Copying configuration directories..."
cp -r build_data "$PACKAGE_DIR/" 2>/dev/null || print_warning "build_data directory not found"
cp -r scripts "$PACKAGE_DIR/" 2>/dev/null || print_warning "scripts directory not found"
cp -r dashboards "$PACKAGE_DIR/" 2>/dev/null || print_warning "dashboards directory not found"

# Create deployment instructions
print_status "Creating deployment instructions..."
cat > "$PACKAGE_DIR/DEPLOYMENT.md" << 'EOF'
# GeoServer Cluster Deployment Instructions

This package contains everything needed to deploy the GeoServer cluster on a new server.

## Quick Start

1. **Extract the package** on your target server
2. **Install prerequisites**: Docker and Docker Compose
3. **Run the deployment script**:
   ```bash
   ./deploy.sh
   ```

## Prerequisites

- Docker (20.10+ recommended)
- Docker Compose (2.0+ recommended)
- 4GB+ RAM available
- Ports 3000, 8081, 8082, 8161, 8600, 9090, 25432, 61616 available

## Configuration

Before deployment, review and modify `.env.production`:

```bash
# Copy to .env and customize
cp .env.production .env
nano .env
```

### Key Configuration Options

- `POSTGRES_USER/POSTGRES_PASS`: Database credentials
- `GEOSERVER_ADMIN_USER/GEOSERVER_ADMIN_PASSWORD`: GeoServer admin credentials
- `POSTGRES_PORT`: Database port (default: 25432)
- `GEOSERVER_INSTANCES`: Number of GeoServer nodes (default: 2)

## Deployment Options

### Standard Deployment
```bash
./deploy.sh
```

### Quick Deployment (no health checks)
```bash
./deploy.sh -q
```

### Check System Prerequisites Only
```bash
./deploy.sh -c
```

### Custom Port Configuration
Edit `.env` file before deployment to change default ports.

## Post-Deployment

### Access Points
- **GeoServer Cluster**: http://your-server:8600
- **Grafana Dashboard**: http://your-server:3000
- **Prometheus**: http://your-server:9090
- **Individual GeoServer Nodes**: http://your-server:8081, http://your-server:8082

### Scaling
```bash
# Scale to 4 instances
./scripts/scale-cluster.sh up 4
docker-compose up -d

# Scale down to 2 instances
./scripts/scale-cluster.sh down 2
docker-compose up -d
```

### Health Monitoring
```bash
# Check cluster health
./scripts/health-check.sh

# View service status
docker-compose ps

# View logs
docker-compose logs -f [service-name]
```

### Data Persistence

The following directories contain persistent data:
- `geoserver-data/`: GeoServer configuration and data
- `geoserver-cache/`: GeoWebCache tiles
- Docker volumes: `geo-db-data`, `prometheus-data`, `grafana-data`

### Backup and Migration

To backup your deployment:
```bash
# Stop services
docker-compose down

# Backup data directories
tar -czf geoserver-backup.tar.gz geoserver-data geoserver-cache

# Backup Docker volumes
docker run --rm -v geo-db-data:/data -v $(pwd):/backup alpine tar -czf /backup/db-backup.tar.gz -C /data .
```

## Troubleshooting

### Common Issues

1. **Port conflicts**: Check if ports are already in use
   ```bash
   ss -tuln | grep :8600
   ```

2. **Permission issues**: Ensure proper permissions for data directories
   ```bash
   sudo chown -R 1000:1000 geoserver-data geoserver-cache
   ```

3. **Memory issues**: Adjust memory limits in docker-compose.yml or .env

4. **Service won't start**: Check logs
   ```bash
   docker-compose logs [service-name]
   ```

### Getting Help

- Check service logs: `docker-compose logs -f`
- Verify configuration: `docker-compose config`
- Test connectivity: `./scripts/health-check.sh`

## Security Considerations

1. **Change default passwords** in `.env` file
2. **Configure firewall** to restrict access to necessary ports only
3. **Use HTTPS** in production (configure Caddy for SSL/TLS)
4. **Regular updates**: Keep Docker images updated
5. **Monitor logs** for suspicious activity

## Advanced Configuration

### SSL/TLS Setup
Edit `scripts/docker/build/caddy/Caddyfile` to configure HTTPS.

### Custom GeoServer Configuration
Place custom configuration files in `build_data/` directory.

### Monitoring Configuration
Customize Prometheus configuration in `scripts/docker/build/prometheus/prometheus.yml`.

EOF

# Create environment template with comments
print_status "Creating environment template..."
cat > "$PACKAGE_DIR/.env.template" << 'EOF'
# GeoServer Cluster Configuration Template
# Copy this file to .env and customize the values

# ==============================================
# Database Configuration
# ==============================================
POSTGIS_VERSION_TAG=15-3.3
POSTGRES_USER=geoserver_user
POSTGRES_PASS=change_this_password
POSTGRES_PORT=25432
ALLOW_IP_RANGE=0.0.0.0/0

# ==============================================
# GeoServer Configuration
# ==============================================
GEOSERVER_DATA_DIR=/opt/geoserver/data_dir
GEOSERVER_CACHE_DIR=/opt/geoserver/gwc
GEOSERVER_DATA_MNT=./geoserver-data
GEOSERVER_CACHE_MNT=./geoserver-cache
GEOSERVER_ADMIN_USER=admin
GEOSERVER_ADMIN_PASSWORD=change_this_password

# ==============================================
# Cluster Scaling Configuration
# ==============================================
GEOSERVER_INSTANCES=2
GEOSERVER_BASE_PORT=8081
GEOSERVER_MEMORY_LIMIT=2G
GEOSERVER_MEMORY_RESERVATION=1G
GEOSERVER_CPU_LIMIT=1.0
GEOSERVER_CPU_RESERVATION=0.5

# ==============================================
# Build Configuration
# ==============================================
BUILD_WEB_XML=./build_data/web.xml

# ==============================================
# Network Configuration
# ==============================================
# Ensure these ports are available on your host
DB_PORT=25432
ACTIVEMQ_WEB_PORT=8161
ACTIVEMQ_BROKER_PORT=61616
GEOSERVER_NODE1_PORT=8081
GEOSERVER_NODE2_PORT=8082
CADDY_PORT=8600
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000

# ==============================================
# Monitoring Configuration
# ==============================================
GRAFANA_DATA_DIR=./grafana-data
GRAFANA_ADMIN_PASSWORD=change_this_password

EOF

# Create quick start script
print_status "Creating quick start script..."
cat > "$PACKAGE_DIR/quick-start.sh" << 'EOF'
#!/bin/bash

echo "GeoServer Cluster Quick Start"
echo "============================="
echo ""

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "Creating .env file from template..."
    if [ -f ".env.production" ]; then
        cp .env.production .env
    elif [ -f ".env.template" ]; then
        cp .env.template .env
    else
        echo "ERROR: No environment template found!"
        exit 1
    fi
    echo "✓ .env file created"
    echo ""
    echo "IMPORTANT: Please review and update the passwords in .env file before proceeding!"
    echo "Edit .env with your preferred text editor:"
    echo "  nano .env    (or vim, emacs, etc.)"
    echo ""
    echo "Press Enter when you've updated the .env file..."
    read -r
fi

# Run deployment
echo "Starting deployment..."
./deploy.sh

EOF

chmod +x "$PACKAGE_DIR/quick-start.sh"

# Create portable docker-compose override for different environments
print_status "Creating environment-specific overrides..."
cat > "$PACKAGE_DIR/docker-compose.override.yml.example" << 'EOF'
# Example override file for different environments
# Copy to docker-compose.override.yml and customize

version: "3.9"

services:
  # Production overrides
  caddy:
    # Uncomment to enable HTTPS in production
    # ports:
    #   - "80:80"
    #   - "443:443"
    # volumes:
    #   - ./caddy-data:/data
    #   - ./caddy-config:/config

  # Development overrides
  # gs-node1:
  #   environment:
  #     - GEOSERVER_OPTS=-Djava.awt.headless=true -server -Xms1g -Xmx2g
  
  # Monitoring overrides for production
  # prometheus:
  #   command:
  #     - '--config.file=/etc/prometheus/prometheus.yml'
  #     - '--storage.tsdb.path=/prometheus'
  #     - '--web.console.libraries=/etc/prometheus/console_libraries'
  #     - '--web.console.templates=/etc/prometheus/consoles'
  #     - '--storage.tsdb.retention.time=30d'
  #     - '--web.enable-lifecycle'

EOF

# Create verification script
print_status "Creating verification script..."
cat > "$PACKAGE_DIR/verify-deployment.sh" << 'EOF'
#!/bin/bash

echo "Verifying GeoServer Cluster Deployment"
echo "======================================"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_service() {
    local service_name=$1
    local url=$2
    local expected_status=${3:-200}
    
    echo -n "Checking $service_name... "
    
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "$expected_status"; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# Load environment variables
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

echo ""
echo "Service Health Checks:"
echo "---------------------"

# Check services
check_service "Load Balancer" "http://localhost:8600" "200\|302"
check_service "GeoServer Node 1" "http://localhost:8081/geoserver/web/" "200\|302"
check_service "GeoServer Node 2" "http://localhost:8082/geoserver/web/" "200\|302"
check_service "Grafana" "http://localhost:3000/api/health" "200"
check_service "Prometheus" "http://localhost:9090/-/healthy" "200"
check_service "ActiveMQ" "http://localhost:8161" "200\|401"

echo ""
echo "Docker Service Status:"
echo "---------------------"
docker-compose ps

echo ""
echo "Resource Usage:"
echo "---------------"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

EOF

chmod +x "$PACKAGE_DIR/verify-deployment.sh"

# Create archive
print_status "Creating deployment archive..."
cd /tmp
tar -czf "${PACKAGE_NAME}.tar.gz" "$PACKAGE_NAME"

# Move to original directory
mv "${PACKAGE_NAME}.tar.gz" "$SCRIPT_DIR/"

# Cleanup
rm -rf "$PACKAGE_DIR"

print_status "Package created successfully!"
echo ""
echo -e "${BLUE}Package Details:${NC}"
echo "  File: ${PACKAGE_NAME}.tar.gz"
echo "  Size: $(du -h "${SCRIPT_DIR}/${PACKAGE_NAME}.tar.gz" | cut -f1)"
echo ""
echo -e "${BLUE}To deploy on a new server:${NC}"
echo "  1. Copy ${PACKAGE_NAME}.tar.gz to target server"
echo "  2. Extract: tar -xzf ${PACKAGE_NAME}.tar.gz"
echo "  3. Enter directory: cd $PACKAGE_NAME"
echo "  4. Run: ./quick-start.sh"
echo ""
echo -e "${BLUE}Package Contents:${NC}"
tar -tzf "${SCRIPT_DIR}/${PACKAGE_NAME}.tar.gz" | head -20
echo "  ... and more"