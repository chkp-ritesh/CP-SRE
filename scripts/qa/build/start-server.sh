#!/bin/bash

# Install cert tools if needed
sudo apt-get update
sudo apt-get install -y python3 openssl

# Create dummy HTML file
echo "<h1>QA NEW SITE HTTP PAGE</h1>" > index.html

# Create self-signed cert (valid 1 year)
openssl req -new -x509 -keyout key.pem -out cert.pem -days 365 -nodes \
  -subj "/CN=localhost"

# Start HTTP on 127.0.0.1:8080
nohup python3 -m http.server 8080 --bind 0.0.0.0 --directory . > http.log 2>&1 &

# Start HTTPS on 127.0.0.1:8443
nohup python3 -m http.server 8443 --bind 0.0.0.0 --directory . --certfile cert.pem --keyfile key.pem > https.log 2>&1 &


