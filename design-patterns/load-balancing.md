# Load Balancing Pattern

## Overview
Load balancing distributes incoming network traffic across multiple servers to ensure no single server bears too much load.

## Load Balancing Algorithms
1. **Round Robin**: Distributes requests sequentially
2. **Least Connections**: Routes to server with fewest active connections
3. **IP Hash**: Routes based on client IP
4. **Weighted Round Robin**: Assigns weights to servers

## Types of Load Balancers
- Layer 4 (Transport): TCP/UDP level
- Layer 7 (Application): HTTP/HTTPS level

## Benefits
- High availability
- Scalability
- Fault tolerance
- Better resource utilization

## Implementation Examples
- Hardware: F5, Cisco
- Software: Nginx, HAProxy
- Cloud: AWS ELB, Azure Load Balancer
