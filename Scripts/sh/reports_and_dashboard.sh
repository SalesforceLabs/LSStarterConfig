#!/bin/bash
echo "Deployment of Reports and Dashboards - started"

#deploy custom layouts
if [ -d "PackageComponents/reportTypes" ]; then
    echo "Deploying report types..."
    sf project deploy start -d PackageComponents/reportTypes
else
    echo "No report types found to deploy."
fi

#deploy reports
if [ -d "PackageComponents/reports" ]; then
    echo "Deploying reports..."
    sf project deploy start -d PackageComponents/reports
else
    echo "No reports found to deploy."
fi

#deploy dashboards
if [ -d "PackageComponents/dashboards" ]; then
    echo "Deploying dashboards..."
    sf project deploy start -d PackageComponents/dashboards
else
    echo "No dashboards found to deploy."
fi

echo "Deployment of Reports and Dashboards - completed"
# -- new command here --