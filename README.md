# README

# Prerequisites 
1. LSC4CE Org with 2GP package installed is available
2. Org must have the permission set licenses "Health Cloud Starter" and "Life Science Commercial"

# Steps to load data into Org
1. Clone the repo “https://git.soma.salesforce.com/industries-extn/ls_starter_config.git” to local on a laptop
2. Open the SFDX project “LSStarterConfig” in Visual Studio Code
3. Authorize the LSC4CE Org and connect to the Org.
4. Open Terminal in Visual Studio Code and run the command “npm install” from "LSStarterConfig" folder
5. From Terminal in Visual Studio Code run the command "sh Scripts/sh/data_load.sh" from "LSStarterConfig" folder
