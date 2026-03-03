#!/bin/bash

# Setup script for LSStarter Config Deployer
# This script helps configure environment variables for local and Heroku deployment

set -e

echo "======================================"
echo "LSStarter Config Deployer Setup"
echo "======================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to generate random secret
generate_secret() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 32
    else
        node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
    fi
}

# Check if we're in the right directory
if [ ! -f "index.js" ]; then
    echo -e "${RED}Error: Please run this script from the heroku-app directory${NC}"
    exit 1
fi

echo "This script will help you configure:"
echo "  1. Local development (.env file)"
echo "  2. Heroku deployment (config vars)"
echo ""

# Prompt for SF_CLIENT_ID
echo -e "${BLUE}Step 1: Salesforce Connected App Consumer Key${NC}"
echo ""
echo "To get your Consumer Key:"
echo "  1. Log into your Salesforce Sandbox"
echo "  2. Go to Setup → Apps → App Manager"
echo "  3. Find your Connected App → View"
echo "  4. Copy the Consumer Key"
echo ""
read -p "Enter your SF_CLIENT_ID (Consumer Key): " SF_CLIENT_ID

if [ -z "$SF_CLIENT_ID" ]; then
    echo -e "${RED}Error: SF_CLIENT_ID is required${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Consumer Key configured${NC}"
echo ""

# Generate SESSION_SECRET
echo -e "${BLUE}Step 2: Session Secret${NC}"
echo ""
SESSION_SECRET=$(generate_secret)
echo "Generated random SESSION_SECRET:"
echo "$SESSION_SECRET"
echo ""
read -p "Use this generated secret? (Y/n): " USE_GENERATED

if [[ "$USE_GENERATED" =~ ^[Nn]$ ]]; then
    read -p "Enter your SESSION_SECRET: " SESSION_SECRET
fi

echo ""
echo -e "${GREEN}✓ Session secret configured${NC}"
echo ""

# Ask what to configure
echo -e "${BLUE}Step 3: Where to configure?${NC}"
echo ""
echo "1) Local development only (.env file)"
echo "2) Heroku only (config vars)"
echo "3) Both local and Heroku"
echo ""
read -p "Choose option (1-3): " DEPLOY_OPTION

# Configure local .env
if [ "$DEPLOY_OPTION" = "1" ] || [ "$DEPLOY_OPTION" = "3" ]; then
    echo ""
    echo -e "${YELLOW}Configuring local development...${NC}"
    
    cat > .env << EOF
# Salesforce Connected App Configuration
SF_CLIENT_ID=$SF_CLIENT_ID

# Session Secret for PKCE flow
SESSION_SECRET=$SESSION_SECRET

# Environment
NODE_ENV=development
PORT=3000
EOF
    
    # Add .env to .gitignore if not already there
    if [ -f ".gitignore" ]; then
        if ! grep -q "^\.env$" .gitignore; then
            echo ".env" >> .gitignore
            echo -e "${GREEN}✓ Added .env to .gitignore${NC}"
        fi
    else
        echo ".env" > .gitignore
        echo -e "${GREEN}✓ Created .gitignore with .env${NC}"
    fi
    
    # Check if dotenv is installed
    if ! npm list dotenv &> /dev/null; then
        echo ""
        read -p "Install dotenv package for local development? (Y/n): " INSTALL_DOTENV
        if [[ ! "$INSTALL_DOTENV" =~ ^[Nn]$ ]]; then
            npm install dotenv --registry https://registry.npmjs.org/
            echo -e "${GREEN}✓ dotenv installed${NC}"
            echo ""
            echo -e "${YELLOW}NOTE: Add this line at the top of index.js:${NC}"
            echo -e "${BLUE}require('dotenv').config();${NC}"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}✓ Local .env file created${NC}"
    echo ""
fi

# Configure Heroku
if [ "$DEPLOY_OPTION" = "2" ] || [ "$DEPLOY_OPTION" = "3" ]; then
    echo ""
    echo -e "${YELLOW}Configuring Heroku...${NC}"
    
    # Check if Heroku CLI is installed
    if ! command -v heroku &> /dev/null; then
        echo -e "${RED}Error: Heroku CLI not installed${NC}"
        echo "Install it from: https://devcenter.heroku.com/articles/heroku-cli"
        echo ""
        echo "Manual setup instructions:"
        echo "  heroku config:set SF_CLIENT_ID=$SF_CLIENT_ID"
        echo "  heroku config:set SESSION_SECRET=$SESSION_SECRET"
        exit 1
    fi
    
    # Check if logged in to Heroku
    if ! heroku auth:whoami &> /dev/null; then
        echo "Not logged in to Heroku. Logging in..."
        heroku login
    fi
    
    # List apps and let user choose
    echo ""
    echo "Available Heroku apps:"
    heroku apps --json | node -e "
        const apps = JSON.parse(require('fs').readFileSync(0, 'utf-8'));
        apps.forEach((app, i) => console.log(\`  \${i+1}) \${app.name}\`));
    " 2>/dev/null || heroku apps
    
    echo ""
    read -p "Enter Heroku app name: " HEROKU_APP
    
    if [ -z "$HEROKU_APP" ]; then
        echo -e "${RED}Error: App name is required${NC}"
        exit 1
    fi
    
    # Set config vars
    echo ""
    echo "Setting Heroku config vars..."
    heroku config:set SF_CLIENT_ID="$SF_CLIENT_ID" -a "$HEROKU_APP"
    heroku config:set SESSION_SECRET="$SESSION_SECRET" -a "$HEROKU_APP"
    
    # Check if session affinity is enabled (for multi-dyno setups)
    echo ""
    read -p "Enable session affinity (recommended for multiple dynos)? (Y/n): " ENABLE_AFFINITY
    if [[ ! "$ENABLE_AFFINITY" =~ ^[Nn]$ ]]; then
        heroku features:enable http-session-affinity -a "$HEROKU_APP" 2>/dev/null || echo "Session affinity already enabled or not available"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Heroku configured${NC}"
    echo ""
fi

# Summary
echo ""
echo "======================================"
echo -e "${GREEN}Setup Complete!${NC}"
echo "======================================"
echo ""
echo "Configuration Summary:"
echo "  SF_CLIENT_ID: ${SF_CLIENT_ID:0:20}..."
echo "  SESSION_SECRET: ${SESSION_SECRET:0:20}..."
echo ""

if [ "$DEPLOY_OPTION" = "1" ] || [ "$DEPLOY_OPTION" = "3" ]; then
    echo "Local Development:"
    echo "  • Run: npm start"
    echo "  • Access: http://localhost:3000"
    echo ""
fi

if [ "$DEPLOY_OPTION" = "2" ] || [ "$DEPLOY_OPTION" = "3" ]; then
    echo "Heroku Deployment:"
    echo "  • App: $HEROKU_APP"
    echo "  • Push: git push heroku main"
    echo "  • View: heroku open -a $HEROKU_APP"
    echo ""
fi

echo "Next Steps:"
echo "  1. Ensure your Connected App has PKCE enabled"
echo "  2. Add your Heroku URL to Connected App's Callback URL"
echo "     Example: https://your-app.herokuapp.com/oauth/callback"
echo "  3. Test the deployment!"
echo ""
echo -e "${GREEN}Happy Deploying! 🚀${NC}"
echo ""

