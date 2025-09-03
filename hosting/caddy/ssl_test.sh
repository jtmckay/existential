#!/bin/bash

# SSL Test and Certificate Trust Script for existential.company domains
# Run from the project root directory

echo "🔐 SSL Certificate Test and Trust Setup"
echo "======================================="
echo ""

# Test SSL connectivity
test_ssl() {
    echo "🧪 Testing SSL connectivity..."
    
    domains=(
        "local.existential.company:Dashy Dashboard"
        "cloud.local.existential.company:Nextcloud"
        "portainer.local.existential.company:Portainer"
        "tasks.local.existential.company:Vikunja"
        "windmill.local.existential.company:Windmill"
    )
    
    for domain_info in "${domains[@]}"; do
        IFS=':' read -r domain name <<< "$domain_info"
        
        echo "Testing $name ($domain)..."
        if curl -k -s --connect-timeout 5 "https://$domain" >/dev/null; then
            echo "✅ $name is accessible via HTTPS"
        else
            echo "❌ $name is not responding (service may not be running)"
        fi
    done
}

# Get CA certificate for manual trust
extract_ca_cert() {
    echo ""
    echo "📜 Extracting CA certificate for browser trust..."
    
    if docker exec caddy cat /data/caddy/pki/authorities/local/root.crt > caddy-local-ca.crt 2>/dev/null; then
        echo "✅ CA certificate saved to: caddy-local-ca.crt"
        echo ""
        echo "📋 To trust this certificate:"
        echo "   • System-wide: sudo cp caddy-local-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
        echo "   • Firefox: Settings → Privacy & Security → Certificates → View Certificates → Import"
        echo "   • Chrome: Settings → Privacy and security → Security → Manage certificates → Import"
        echo ""
        return 0
    else
        echo "❌ Could not extract CA certificate"
        return 1
    fi
}

# Try automatic trust
try_auto_trust() {
    echo "🔒 Attempting automatic certificate trust..."
    
    if docker exec caddy caddy trust 2>/dev/null; then
        echo "✅ Certificates trusted automatically!"
        return 0
    else
        echo "⚠️  Automatic trust failed - will extract certificate for manual trust"
        return 1
    fi
}

# Show access URLs
show_urls() {
    echo ""
    echo "🌐 Your services are accessible at:"
    echo "=================================="
    echo "  🏠 Dashboard:  https://local.existential.company"
    echo "  ☁️  Nextcloud:   https://cloud.local.existential.company"
    echo "  🐳 Portainer:   https://portainer.local.existential.company"
    echo "  📝 Tasks:       https://tasks.local.existential.company"
    echo "  ⚡ Windmill:    https://windmill.local.existential.company"
    echo "  🔧 Tools:       https://tools.local.existential.company"
    echo "  🗄️  Database:    https://db.local.existential.company"
    echo "  📦 Storage:     https://storage.local.existential.company"
    echo "  🚀 Apps:        https://apps.local.existential.company"
    echo "  🔄 Queue:       https://queue.local.existential.company"
    echo ""
}

# Main execution
main() {
    # Test SSL
    test_ssl
    
    # Try automatic trust
    if ! try_auto_trust; then
        extract_ca_cert
    fi
    
    # Show URLs
    show_urls
    
    echo "✨ SSL Setup Complete!"
    echo ""
    echo "💡 If you still see certificate warnings:"
    echo "   1. Trust the CA certificate (see instructions above)"
    echo "   2. Or simply accept the browser warning for local development"
    echo "   3. Restart your browser after trusting certificates"
}

# Run if not sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
