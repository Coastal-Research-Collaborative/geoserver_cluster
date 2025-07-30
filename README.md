# GeoServer Cluster with Monitoring

A production-ready, scalable GeoServer cluster with comprehensive monitoring, load balancing, and high availability features.

## Features

- **Scalable Cluster**: Horizontal scaling with automated load balancing
- **High Availability**: Fault-tolerant setup with health monitoring
- **JMS Clustering**: Real-time data synchronization across nodes
- **Comprehensive Monitoring**: Prometheus metrics with Grafana dashboards
- **Load Balancing**: Caddy reverse proxy with sticky sessions
- **Database Integration**: PostGIS-enabled PostgreSQL database
- **Message Queuing**: ActiveMQ for cluster coordination

## Prerequisites

- **Docker**: Version 20.10+ 
- **Docker Compose**: Version 2.0+
- **System Resources**:
  - Minimum: 4 GB RAM, 2 CPU cores
  - Recommended: 8 GB RAM, 4 CPU cores
  - Storage: 10 GB available disk space
- **Network**: Ports 3000, 8081-8090, 8600, 9090, 25432, 61616 available

## Technology Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| [GeoServer](https://hub.docker.com/r/geobeyond/geoserver) | 2.20.6 | Geospatial data server |
| PostgreSQL | 15 | Primary database with PostGIS |
| Caddy | Latest | Load balancer and reverse proxy |
| ActiveMQ | Latest | Message broker for clustering |
| Prometheus | Latest | Metrics collection |
| Grafana | Latest | Monitoring dashboards |

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd geoserver_cluster
   ```

2. **Configure environment** (optional):
   ```bash
   cp .env.example .env
   # Edit .env with your preferred settings
   ```

3. **Start the cluster**:
   ```bash
   docker compose up -d
   ```

4. **Verify deployment**:
   ```bash
   ./scripts/health-check.sh
   ```

## Configuration

### Environment Variables

Key configuration options in `.env`:

```bash
# Cluster Configuration
GEOSERVER_INSTANCES=2              # Number of GeoServer instances
GEOSERVER_BASE_PORT=8081          # Starting port for instances
GEOSERVER_ADMIN_USER=admin        # GeoServer admin username
GEOSERVER_ADMIN_PASSWORD=geoserver # GeoServer admin password

# Resource Limits
GEOSERVER_MEMORY_LIMIT=2G         # Memory limit per instance
GEOSERVER_CPU_LIMIT=1.0           # CPU limit per instance

# Database
POSTGRES_USER=docker              # PostgreSQL username
POSTGRES_PASS=docker              # PostgreSQL password
POSTGRES_PORT=25432               # PostgreSQL port
```

## Scaling

### Quick Scaling with Script
Use the provided scaling script for easy horizontal scaling:

```bash
# Scale up to 4 GeoServer instances
./scripts/scale-cluster.sh up 4

# Scale down to 2 GeoServer instances  
./scripts/scale-cluster.sh down 2

# Apply changes
docker compose up -d
```

### Manual Scaling
You can also manually add GeoServer instances by adding the docker compose snippet with appropriate environment variables to [docker-compose.yml](docker-compose.yml):

```yaml
gs-node#:
    image: geobeyond/geoserver:2.20.6
    volumes:
      - ${GEOSERVER_DATA_MNT}:${GEOSERVER_DATA_DIR}
      - ${GEOSERVER_CACHE_MNT}:${GEOSERVER_CACHE_DIR}
    ports:
      - "808#:8080"
    environment: 
    # ... (copy environment from existing nodes)
```

## Services & Access

| Service | URL | Port | Credentials |
|---------|-----|------|-------------|
| **GeoServer Cluster** | http://localhost:8600 | 8600 | admin/geoserver |
| GeoServer Node 1 | http://localhost:8081 | 8081 | admin/geoserver |
| GeoServer Node 2 | http://localhost:8082 | 8082 | admin/geoserver |
| Grafana Dashboard | http://localhost:3000 | 3000 | admin/admin |
| Prometheus | http://localhost:9090 | 9090 | - |
| PostgreSQL | localhost:25432 | 25432 | docker/docker |
| ActiveMQ Web Console | http://localhost:8161 | 8161 | admin/admin |

### Health Monitoring
Check cluster health status:
```bash
./scripts/health-check.sh
```

This will verify:
- All GeoServer instances are responding
- Load balancer is distributing requests
- Database connectivity
- ActiveMQ broker status
- Monitoring services
- Container resource usage

## Clustering using JMS Plugin
GeoServer supports clustering using JMS cluster plugin or using the ActiveMQ-broker. 

This setup uses the JMS cluster plugin which uses an embedded broker. A docker-compose.yml
is provided in the clustering folder which simulates the replication using 
a shared data directory.

The environment variables associated with replication are listed below
* `CLUSTERING=True` - Specified whether clustering should be activated.
* `BROKER_URL=tcp://0.0.0.0:61661` - This links to the internal broker provided by the JMS cluster plugin.
This value will be different for (Master-Node)
* `READONLY=disabled` - Determines if the GeoServer instance is Read only
* `RANDOMSTRING=87ee2a9b6802b6da_master` - Used to create a unique CLUSTER_CONFIG_DIR for each instance. Not mandatory as the container can self generate this.
* `INSTANCE_STRING=d8a167a4e61b5415ec263` - Used to differentiate cluster instance names. Not mandatory as the container can self generate this.
* `CLUSTER_DURABILITY=false`
* `TOGGLE_MASTER=true` - Differentiates if the instance will be a Master
* `TOGGLE_SLAVE=true` - Differentiates if the instance will be a Node
* `EMBEDDED_BROKER=disabled` - Should be disabled for the Node
* `CLUSTER_CONNECTION_RETRY_COUNT=10` - How many times try to connect to broker
* `CLUSTER_CONNECTION_MAX_WAIT=500` - Wait time between connection to broker retry (in milliseconds)

## Monitoring & Observability

### Prometheus Metrics
The system automatically collects metrics from:
- GeoServer instances (JVM, request rates, response times)
- PostgreSQL database performance
- ActiveMQ broker statistics
- Docker container resources
- System host metrics

### Grafana Dashboards
Pre-configured dashboards available at http://localhost:3000:

| Dashboard | Description |
|-----------|-------------|
| `docker-containers` | Container resource usage and health |
| `docker-host` | Host system metrics (CPU, memory, disk) |
| `monitoring-services` | Prometheus and Grafana service status |

**Default Login**: admin/admin (change on first login)

### Custom Alerts
Configure alerts in Grafana for:
- High memory usage (>80%)
- GeoServer response time degradation
- Database connection failures
- Container restarts

## Troubleshooting

### Common Issues

**Services won't start**:
```bash
# Check port conflicts
docker compose ps
netstat -tulpn | grep :8600

# Check logs
docker compose logs geoserver-node1
```

**GeoServer clustering not working**:
```bash
# Verify ActiveMQ connectivity
docker compose exec geoserver-node1 curl activemq:61616
```

**High memory usage**:
```bash
# Monitor container resources
docker stats

# Adjust memory limits in .env
GEOSERVER_MEMORY_LIMIT=4G
```

**Database connection issues**:
```bash
# Test database connectivity
docker compose exec geoserver-node1 nc -zv postgis 5432
```

### Log Locations
- GeoServer logs: `./geoserver-data/logs/`
- Container logs: `docker compose logs [service-name]`
- Prometheus logs: `docker compose logs prometheus`

### Performance Tuning

**For high-load scenarios**:
1. Increase memory allocation:
   ```bash
   GEOSERVER_MEMORY_LIMIT=4G
   GEOSERVER_MEMORY_RESERVATION=2G
   ```

2. Scale instances:
   ```bash
   ./scripts/scale-cluster.sh up 4
   ```

3. Tune database connections in `docker-compose.yml`

## Backup & Recovery

### Data Backup
```bash
# Backup GeoServer data
docker compose exec geoserver-node1 tar -czf /tmp/geoserver-backup.tar.gz /opt/geoserver/data_dir
docker compose cp geoserver-node1:/tmp/geoserver-backup.tar.gz ./backups/

# Backup PostgreSQL
docker compose exec postgis pg_dump -U docker > ./backups/postgres-backup.sql
```

### Restore Process
```bash
# Stop services
docker compose down

# Restore data directories
tar -xzf ./backups/geoserver-backup.tar.gz -C ./geoserver-data/

# Restart services
docker compose up -d
```

## Development

### Local Development
```bash
# Build custom GeoServer image
docker compose -f docker-compose.dev.yml build

# Run with development overrides
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

### Contributing
1. Fork the repository
2. Create a feature branch
3. Test your changes with `./scripts/health-check.sh`
4. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## References

- **GeoServer Documentation**: https://docs.geoserver.org/
- **Clustering Guide**: https://github.com/geobeyond/geoserver-clustering-playground
- **Monitoring Setup**: https://github.com/DoTheEvo/selfhosted-apps-docker/blob/master/prometheus_grafana_loki/
- **Performance Blog**: https://medium.com/geobeyond/making-geoserver-fast-vertical-geoserver-clustering-bf9dbdb5d61a
- **Docker Hub Image**: https://hub.docker.com/r/geobeyond/geoserver

## Support

For issues and questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review existing [GitHub Issues](../../issues)
3. Create a new issue with detailed information
