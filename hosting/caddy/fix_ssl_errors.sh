#!/bin/bash

# Fix SSL errors for local development domains
# This script helps resolve ERR_SSL_PROTOCOL_ERROR and certificate trust issues

echo "🔐 Fixing SSL Errors for Local Development"
echo "=========================================="
echo ""

check_caddy_status() {
    echo "📋 Checking Caddy status..."
    if docker ps | grep -q "caddy.*Up"; then
        echo "✅ Caddy is running"
        return 0
    else
        echo "❌ Caddy is not running"
        echo "💡 Start with: docker compose up -d"
        return 1
    fi
}

clear_failed_certificates() {
    echo "🧹 Clearing failed certificate attempts..."
    
    # Stop Caddy
    docker compose down
    
    # Remove certificate data to start fresh
    docker volume rm caddy_caddy_data 2>/dev/null || echo "Volume didn't exist"
    docker volume rm caddy_caddy_config 2>/dev/null || echo "Config volume didn't exist"
    
    echo "✅ Certificate data cleared"
}

start_caddy_with_internal_certs() {
    echo "🚀 Starting Caddy with internal certificates..."
    
    docker compose up -d
    
    if [ $? -eq 0 ]; then
        echo "✅ Caddy started successfully"
        
        # Wait a moment for certificates to generate
        echo "⏳ Waiting for certificate generation..."
        sleep 5
        
        return 0
    else
        echo "❌ Failed to start Caddy"
        return 1
    fi
}

trust_internal_ca() {
    echo "🔒 Setting up certificate trust..."
    
    # Try to get Caddy to trust its own CA
    if docker exec caddy caddy trust 2>/dev/null; then
        echo "✅ Internal CA trusted automatically"
        return 0
    else
        echo "⚠️  Automatic trust failed, trying manual extraction..."
        
        # Extract the CA certificate
        if docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > /tmp/caddy-local-ca.crt 2>/dev/null; then
            echo "📜 CA certificate extracted to /tmp/caddy-local-ca.crt"
            echo ""
            echo "📋 Manual trust instructions:"
            echo "   1. Copy the certificate to system trust store:"
            echo "      sudo cp /tmp/caddy-local-ca.crt /usr/local/share/ca-certificates/"
            echo "      sudo update-ca-certificates"
            echo ""
            echo "   2. For browsers, import /tmp/caddy-local-ca.crt as a trusted CA"
            echo "   3. Or restart browser and accept the security warning"
            return 0
        else
            echo "❌ Could not extract CA certificate"
            return 1
        fi
    fi
}

test_ssl_connectivity() {
    echo "🧪 Testing SSL connectivity..."
    
    domains=(
        "local.existential.company"
        "cloud.local.existential.company"
        "portainer.local.existential.company"
    )
    
    for domain in "${domains[@]}"; do
        echo "Testing $domain..."
        
        # Test with curl (ignoring certificate errors for now)
        if curl -k -s --connect-timeout 5 "https://$domain" >/dev/null; then
            echo "✅ $domain is responding (HTTPS working)"
        else
            echo "❌ $domain is not responding"
        fi
    done
}

check_dns_resolution() {
    echo "🔍 Checking DNS resolution..."
    
    domains=(
        "local.existential.company"
        "cloud.local.existential.company"
    )
    
    for domain in "${domains[@]}"; do
        ip=$(dig +short "$domain" A 2>/dev/null)
        if [ "$ip" = "127.0.0.1" ]; then
            echo "✅ $domain → 127.0.0.1"
        else
            echo "❌ $domain → $ip (expected 127.0.0.1)"
        fi
    done
}

show_solution_summary() {
    echo ""
    echo "🎯 Solution Summary"
    echo "=================="
    echo ""
    echo "The ERR_SSL_PROTOCOL_ERROR was caused by:"
    echo "  ❌ Let's Encrypt trying to validate localhost domains"
    echo "  ❌ DNSSEC validation failures"
    echo ""
    echo "✅ Fixed by:"
    echo "  ✓ Using Caddy's internal CA for self-signed certificates"
    echo "  ✓ Adding 'tls internal' to all domains in Caddyfile"
    echo "  ✓ Clearing failed certificate attempts"
    echo ""
    echo "🌐 Your services should now be accessible at:"
    echo "  • https://local.existential.company (Dashy)"
    echo "  • https://cloud.local.existential.company (Nextcloud)"
    echo "  • https://portainer.local.existential.company (Docker)"
    echo "  • https://tasks.local.existential.company (Vikunja)"
    echo "  • https://windmill.local.existential.company (Windmill)"
    echo "  • https://tools.local.existential.company (IT Tools)"
    echo "  • https://db.local.existential.company (NocoDB)"
    echo "  • https://storage.local.existential.company (MinIO)"
    echo "  • https://apps.local.existential.company (Appsmith)"
    echo "  • https://queue.local.existential.company (RabbitMQ)"
    echo ""
    echo "⚠️  Browser may show certificate warnings initially"
    echo "💡 Accept the warnings or trust the CA certificate"
}

# Main execution
main() {
    # Check if we're in the right directory
    if [ ! -f "Caddyfile" ]; then
        echo "❌ Please run this script from the hosting/caddy directory"
        exit 1
    fi
    
    # Check DNS resolution first
    check_dns_resolution
    echo ""
    
    # Clear failed certificates and restart
    clear_failed_certificates
    echo ""
    
    # Start Caddy with internal certs
    if start_caddy_with_internal_certs; then
        echo ""
        
        # Set up certificate trust
        trust_internal_ca
        echo ""
        
        # Test connectivity
        test_ssl_connectivity
        echo ""
        
        # Show summary
        show_solution_summary
    else
        echo "❌ Setup failed. Check the logs: docker logs caddy"
        exit 1
    fi
}

# Run main function
main "$@"
