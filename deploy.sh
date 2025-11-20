#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command_exists docker; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command_exists docker-compose; then
        print_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    print_success "All prerequisites satisfied"
}

# Function to setup hosts file (Linux/Mac)
setup_hosts() {
    print_status "Setting up hosts file..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
        if ! grep -q "app.localhost" /etc/hosts; then
            print_status "Adding entries to /etc/hosts..."
            echo "127.0.0.1 app.localhost" | sudo tee -a /etc/hosts
            echo "127.0.0.1 traefik.localhost" | sudo tee -a /etc/hosts
            print_success "Hosts file updated"
        else
            print_success "Hosts file already configured"
        fi
    else
        print_warning "Please manually add the following to your hosts file:"
        print_warning "127.0.0.1 app.localhost"
        print_warning "127.0.0.1 traefik.localhost"
    fi
}

# Function to build and start services
deploy_services() {
    print_status "Building and starting services..."
    
    # Stop any existing services
    docker-compose down 2>/dev/null || true
    
    # Build and start services
    if docker-compose up --build -d; then
        print_success "Services started successfully"
    else
        print_error "Failed to start services"
        exit 1
    fi
}

# Function to wait for services to be ready
wait_for_services() {
    print_status "Waiting for services to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:80 >/dev/null 2>&1; then
            print_success "Services are ready!"
            return 0
        fi
        
        print_status "Attempt $attempt/$max_attempts - waiting for services..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "Services did not become ready within expected time"
    return 1
}

# Function to show service status
show_status() {
    print_status "Service Status:"
    docker-compose ps
    
    echo
    print_status "Service Logs (last 10 lines):"
    docker-compose logs --tail=10
}

# Function to test load balancing
test_load_balancing() {
    print_status "Testing load balancing..."
    
    echo
    print_status "Making 10 requests to see load distribution:"
    
    for i in {1..10}; do
        response=$(curl -s http://localhost/ | grep -o '"instanceId":"[^"]*"' | cut -d'"' -f4)
        echo "Request $i: Instance $response"
        sleep 0.5
    done
}

# Function to show access URLs
show_access_info() {
    echo
    print_success "🚀 Deployment completed successfully!"
    echo
    print_status "Access URLs:"
    echo "  📱 Main Application: http://app.localhost (or http://localhost)"
    echo "  📊 Traefik Dashboard: http://traefik.localhost:8080 (or http://localhost:8080)"
    echo
    print_status "API Endpoints:"
    echo "  📈 Stats: http://app.localhost/api/stats"
    echo "  💾 Health: http://app.localhost/health"
    echo "  ⚡ Load Test: http://app.localhost/api/load-test"
    echo
    print_status "Useful Commands:"
    echo "  📋 View logs: docker-compose logs -f"
    echo "  📊 Service status: docker-compose ps"
    echo "  🔄 Restart: docker-compose restart"
    echo "  🛑 Stop: docker-compose down"
}

# Function to perform health checks
health_check() {
    print_status "Performing health checks..."
    
    # Check Traefik
    if curl -s http://localhost:8080/api/overview >/dev/null 2>&1; then
        print_success "✅ Traefik is healthy"
    else
        print_warning "⚠️ Traefik may not be fully ready"
    fi
    
    # Check Application instances
    for instance in 1 2; do
        if docker-compose exec -T web-app-${instance} wget -q -O- http://localhost:3000/health >/dev/null 2>&1; then
            print_success "✅ Web App Instance ${instance} is healthy"
        else
            print_warning "⚠️ Web App Instance ${instance} may not be ready"
        fi
    done
    
    # Check Redis
    if docker-compose exec -T redis redis-cli ping | grep -q "PONG"; then
        print_success "✅ Redis is healthy"
    else
        print_warning "⚠️ Redis may not be ready"
    fi
}

# Main deployment function
main() {
    echo "🐳 Docker Traefik Load Balancer Deployment Script"
    echo "=================================================="
    
    check_prerequisites
    setup_hosts
    deploy_services
    
    if wait_for_services; then
        show_status
        health_check
        test_load_balancing
        show_access_info
    else
        print_error "Deployment failed - services are not ready"
        print_status "Check logs with: docker-compose logs"
        exit 1
    fi
}

# Run main function
main "$@"