## Overview
The interview task was to create a monitoring system for a HTTPS server and deploy it on Docker using docker-compose.

## Requirements
1) Build a new container image based on nginx:1.21.1, mount a static webpage to /opt/www/ path.
2) Generate self-signed SSL certificates and mount it to the docker-compose configuration file.
3) Configure and deploy an open source monitoring stack.

## App Architecture
![[App Diagram.drawio.png]]
## Configuration
### Nginx

Nginx configuration is based on sample configuration generated with
`docker run --rm --entrypoint=cat nginx /etc/nginx/nginx.conf > ./nginx/nginx.conf`.
Changes made:
- Redirect HTTP traffic to HTTPS
```
server {
	listen 80 default_server;
	server_name _;
	return 301 https://$host$request_uri;
}
```
- HTTPS server configuration:
```
server {
	listen 443 ssl;
	server_name _;
	ssl_certificate /etc/nginx/ssl/enigma.crt;
	ssl_certificate_key /etc/nginx/ssl/enigma.key;

	# Set a path where web page will be stored
	root /opt/www;
	index index.html;
	  
	# Turn on the metrics
	location /metrics {
		stub_status on;
	}
}
```

In order to allow HTTPS connection, generat SSL certificates with OpenSSL.
`$sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ./nginx/ssl/enigma.key -out ./nginx/ssl/enigma.crt`

Nginx Dockerfile:
```
FROM nginx:1.21.1
RUN rm /etc/nginx/nginx.conf
CMD [ "nginx", "-g", "daemon off;"]
```

Final Nginx container setup in docker-compose.yaml file:
```
web:
	image: enigma-rekr-nginx:0.1
	build: .
	container_name: nginx-https-server
	ports:
		- "443:443"
	restart: always
	volumes:
		- ./html/:/opt/www/:ro
		- ./nginx/:/etc/nginx/:ro
	tty: true
```
The server can be accessed from https://localhost in a web browser.

---
### Nginx Prometheus Exporter

Allows to export Nginx metrics parsed to Prometheus format at http://localhost:9113.

Setup in docker-compose.yaml:
```
exporter:
	image: nginx/nginx-prometheus-exporter:1.1.0
	container_name: nginx-prometheus-exporter
	ports:
		- "9113:9113"
	restart: unless-stopped
	command:
		- "-nginx.scrape-uri=https://nginx-https-server:443/metrics"
		- "-web.telemetry-path=/metrics"
```
### Prometheus

Prometheus serves for scrapping the metrics in real time and passes it for further processing to Grafana.
Configuration is stored in ./prometheus/prometheus.yml. Right now it is only targeting nginx-prometheus-exporter
```
global:
	scrape_interval: 15s
	scrape_timeout: 10s
	evaluation_interval: 15s
scrape_configs:
	- job_name: 'nginx exporter'
	metrics_path: /metrics
	static_configs:
		- targets:
			- nginx-prometheus-exporter:9113
```
docker-compose.yaml setup:
```
prometheus:
	image: prom/prometheus
	container_name: prometheus
	depends_on: [ exporter ]
	command:
		- "--config.file=/etc/prometheus/prometheus.yml"
	ports:
		- "9090:9090"
	restart: unless-stopped
	volumes:
		- ./prometheus:/etc/prometheus:ro
		- ./nginx/ssl:/etc/nginx/ssl/:ro
		- prom_data:/prometheus
```
It can be further accessed at http://localhost:9090

### Grafana

Grafana sources information from Prometheus, which is stated in ./grafana/datasources/datasource.yml file:
```
apiVersion: 1

datasources:
  - name: Prometheus
	type: prometheus
	url: http://prometheus:9090
    isDefault: true
    access: proxy
	editable: true
```
Sample Dashboard is stored as a JSON file, but it needs to be provisioned first.
```
apiVersion: 1
  
providers:
	- name: 'prometheus'
		orgId: 1
		folder: ''
		type: file
		disableDeletion: false
		editable: true
		options:
			path: /etc/grafana/provisioning/dashboards
```
 docker-compose.yaml:
```
grafana:
	image: grafana/grafana
	container_name: grafana
	restart: unless-stopped
	ports:
		- "3000:3000"
	environment:
		- GF_SECURITY_ADMIN_USER=admin
		- GF_SECURITY_ADMIN_PASSWORD=grafana
	volumes:
		- ./grafana:/etc/grafana/provisioning/
	depends_on: [ prometheus ]
```
 
 ## Possible improvements:
 - Implement Let's encrypt for generating and renewal SSL certs
 - Handle Grafana credentials as secrets
 - Implement a logging layer
 