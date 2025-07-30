# Geoserver Cluster + Prometheus Monitoring

## Description
This repository provides a scalable and resilient Geoserver cluster setup, along with a comprehensive monitoring stack, all orchestrated using Docker containers. The cluster is designed to handle high loads efficiently.

## Requirements
* Docker + Docker Compose
* 4 GB RAM
* Additional RAM to allocate more RAM per instance or create more instances

## Technology
* Docker
* PostgreSQL
* ActiveMQ Broker
* [Geoserver](https://hub.docker.com/r/geobeyond/geoserver)
* Caddy Load Balancer
* Prometheus
* Grafana

## Setup
Type the following command and docker containers will be up
```
docker compose up
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

### Scaling Configuration
Configure scaling parameters in your `.env` file:
```bash
GEOSERVER_INSTANCES=2              # Number of instances
GEOSERVER_BASE_PORT=8081          # Starting port number
GEOSERVER_MEMORY_LIMIT=2G         # Memory limit per instance
GEOSERVER_MEMORY_RESERVATION=1G   # Memory reservation per instance
GEOSERVER_CPU_LIMIT=1.0           # CPU limit per instance
GEOSERVER_CPU_RESERVATION=0.5     # CPU reservation per instance
```

## Services
| Service  | Port | Description |
| -------- | -------- | ----------- |
| **Caddy Load Balancer**   | 8600   | Main entry point for GeoServer cluster |
| GeoServer Instance 1   | 8081   | First GeoServer node |
| GeoServer Instance 2   | 8082   | Second GeoServer node |
| PostgreSQL Database   | 25432  | PostGIS-enabled database |
| ActiveMQ Broker | 61616   | JMS clustering coordination |
| Grafana Dashboard   | 3000   | Monitoring visualization |
| Prometheus   | 9090   | Metrics collection |

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

## Monitoring
Prometheus collects metrics from Geoserver, RabbitMQ, and other services, and Grafana provides visualization and alerting capabilities. Grafana dashboards can be tailored to track various performance metrics, such as server load, request rates, and response times.

## Grafana Dashboards
The dashboards were pulled from https://github.com/DoTheEvo/selfhosted-apps-docker/tree/master/prometheus_grafana_loki/dashboards
docker-container.md: Monitor docker container metrics
docker-host.md: Monitor docker host metrics
monitoring-services.md: Monitor monitoring services (Prometheus, grafana, node exporter)

## Reference Links
 * Monitoring + Logging: https://github.com/DoTheEvo/selfhosted-apps-docker/blob/master/prometheus_grafana_loki/
 * Cluster: https://github.com/geobeyond/geoserver-clustering-playground
 * Blog: https://medium.com/geobeyond/making-geoserver-fast-vertical-geoserver-clustering-bf9dbdb5d61a
