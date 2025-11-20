# Docker Traefik Load Balancer Deployment Script for Windows PowerShell

# Colors for output
$Colors = @{
    Red = "Red"
    Green = "Green" 
    Yellow = "Yellow"
    Blue = "Blue"
    White = "White"
}

function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor $Colors.Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $Colors.Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $Colors.Red
}

# Function to check if command exists
function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

# Check prerequisites
function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    if (-not (Test-Command "docker")) {
        Write-Error "Docker is not installed or not in PATH"
        exit 1
    }
    
    if (-not (Test-Command "docker-compose")) {
        Write-Error "Docker Compose is not installed or not in PATH"
        exit 1
    }
    
    Write-Success "All prerequisites satisfied"
}

# Function to setup hosts file (Windows)
function Set-HostsFile {
    Write-Status "Setting up hosts file..."
    
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hostsContent = Get-Content $hostsPath -ErrorAction SilentlyContinue
    
    $appEntry = "127.0.0.1 app.localhost"
    $traefikEntry = "127.0.0.1 traefik.localhost"
    
    $needsUpdate = $false
    
    if ($hostsContent -notcontains $appEntry) {
        $needsUpdate = $true
    }
    
    if ($hostsContent -notcontains $traefikEntry) {
        $needsUpdate = $true
    }
    
    if ($needsUpdate) {
        Write-Status "Adding entries to hosts file..."
        try {
            if ($hostsContent -notcontains $appEntry) {
                Add-Content -Path $hostsPath -Value $appEntry -Force
            }
            if ($hostsContent -notcontains $traefikEntry) {
                Add-Content -Path $hostsPath -Value $traefikEntry -Force
            }
            Write-Success "Hosts file updated"
        } catch {
            Write-Warning "Could not update hosts file automatically. Please run as Administrator or add manually:"
            Write-Warning "127.0.0.1 app.localhost"
            Write-Warning "127.0.0.1 traefik.localhost"
        }
    } else {
        Write-Success "Hosts file already configured"
    }
}

# Function to build and start services
function Start-Services {
    Write-Status "Building and starting services..."
    
    # Stop any existing services
    docker-compose down 2>$null
    
    # Build and start services
    $result = docker-compose up --build -d
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Services started successfully"
    } else {
        Write-Error "Failed to start services"
        Write-Host $result
        exit 1
    }
}

# Function to wait for services to be ready
function Wait-ForServices {
    Write-Status "Waiting for services to be ready..."
    
    $maxAttempts = 30
    $attempt = 1
    
    while ($attempt -le $maxAttempts) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:80" -TimeoutSec 3 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Write-Success "Services are ready!"
                return $true
            }
        } catch {
            # Continue waiting
        }
        
        Write-Status "Attempt $attempt/$maxAttempts - waiting for services..."
        Start-Sleep -Seconds 2
        $attempt++
    }
    
    Write-Error "Services did not become ready within expected time"
    return $false
}

# Function to show service status
function Show-Status {
    Write-Status "Service Status:"
    docker-compose ps
    
    Write-Host ""
    Write-Status "Service Logs (last 10 lines):"
    docker-compose logs --tail=10
}

# Function to test load balancing
function Test-LoadBalancing {
    Write-Status "Testing load balancing..."
    
    Write-Host ""
    Write-Status "Making 10 requests to see load distribution:"
    
    for ($i = 1; $i -le 10; $i++) {
        try {
            $response = Invoke-RestMethod -Uri "http://localhost/" -ErrorAction SilentlyContinue
            $instanceId = $response.instanceId
            Write-Host "Request $i : Instance $instanceId"
            Start-Sleep -Milliseconds 500
        } catch {
            Write-Warning "Request $i failed"
        }
    }
}

# Function to show access URLs
function Show-AccessInfo {
    Write-Host ""
    Write-Success "🚀 Deployment completed successfully!"
    Write-Host ""
    Write-Status "Access URLs:"
    Write-Host "  📱 Main Application: http://app.localhost (or http://localhost)"
    Write-Host "  📊 Traefik Dashboard: http://traefik.localhost:8080 (or http://localhost:8080)"
    Write-Host ""
    Write-Status "API Endpoints:"
    Write-Host "  📈 Stats: http://app.localhost/api/stats"
    Write-Host "  💾 Health: http://app.localhost/health"
    Write-Host "  ⚡ Load Test: http://app.localhost/api/load-test"
    Write-Host ""
    Write-Status "Useful Commands:"
    Write-Host "  📋 View logs: docker-compose logs -f"
    Write-Host "  📊 Service status: docker-compose ps"
    Write-Host "  🔄 Restart: docker-compose restart"
    Write-Host "  🛑 Stop: docker-compose down"
    Write-Host ""
    Write-Status "To open in browser:"
    Write-Host "  Start-Process 'http://app.localhost'"
    Write-Host "  Start-Process 'http://localhost:8080'"
}

# Function to perform health checks
function Test-Health {
    Write-Status "Performing health checks..."
    
    # Check Traefik
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/api/overview" -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            Write-Success "✅ Traefik is healthy"
        }
    } catch {
        Write-Warning "⚠️ Traefik may not be fully ready"
    }
    
    # Check Application instances
    for ($instance = 1; $instance -le 2; $instance++) {
        try {
            $result = docker-compose exec -T "web-app-$instance" wget -q -O- http://localhost:3000/health 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "✅ Web App Instance $instance is healthy"
            } else {
                Write-Warning "⚠️ Web App Instance $instance may not be ready"
            }
        } catch {
            Write-Warning "⚠️ Could not check Web App Instance $instance"
        }
    }
    
    # Check Redis
    try {
        $result = docker-compose exec -T redis redis-cli ping 2>$null
        if ($result -like "*PONG*") {
            Write-Success "✅ Redis is healthy"
        } else {
            Write-Warning "⚠️ Redis may not be ready"
        }
    } catch {
        Write-Warning "⚠️ Could not check Redis"
    }
}

# Function to open URLs in browser
function Open-Applications {
    Write-Status "Opening applications in browser..."
    
    try {
        Start-Process "http://app.localhost"
        Start-Sleep -Seconds 2
        Start-Process "http://localhost:8080"
        Write-Success "Applications opened in browser"
    } catch {
        Write-Warning "Could not open browsers automatically"
    }
}

# Main deployment function
function Start-Deployment {
    Write-Host "🐳 Docker Traefik Load Balancer Deployment Script" -ForegroundColor $Colors.Blue
    Write-Host "==================================================" -ForegroundColor $Colors.Blue
    
    Test-Prerequisites
    Set-HostsFile
    Start-Services
    
    if (Wait-ForServices) {
        Show-Status
        Test-Health
        Test-LoadBalancing
        Show-AccessInfo
        
        $openBrowser = Read-Host "`nWould you like to open the applications in your browser? (y/N)"
        if ($openBrowser -eq "y" -or $openBrowser -eq "Y") {
            Open-Applications
        }
    } else {
        Write-Error "Deployment failed - services are not ready"
        Write-Status "Check logs with: docker-compose logs"
        exit 1
    }
}

# Run main function
Start-Deployment