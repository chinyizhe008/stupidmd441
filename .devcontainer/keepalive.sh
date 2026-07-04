#!/bin/bash
while true; do
    curl -s "http://localhost:8080/health" > /dev/null 2>&1
    curl -s "http://localhost:5000/health" > /dev/null 2>&1
    sleep 300
done