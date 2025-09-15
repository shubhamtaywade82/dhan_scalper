# Redis Integration Documentation

This directory contains all Redis-related documentation for the DhanScalper system.

## Overview

The DhanScalper system uses Redis for persistent storage of trading session data, including positions, orders, balance, and session information. Market tick data is kept in-memory using `TickCache` for optimal performance.

## Documentation Files

### Core Documentation
- **[Data Contracts](redis_data_contracts.md)** - Complete specification of Redis data structures, field requirements, and key naming conventions
- **[Migration Summary](REDIS_MIGRATION_SUMMARY.md)** - Detailed overview of the migration from file-based to Redis-based storage

### Visual Documentation
- **[Data Structure Diagram](redis_structure_diagram.txt)** - ASCII diagram showing Redis key hierarchy and relationships
- **[Contracts Diagram](redis_contracts_diagram.txt)** - Visual representation of data contracts and field mappings

### Technical Analysis
- **[Keys Analysis](redis_keys_analysis.md)** - Analysis of Redis key patterns and usage

## Key Concepts

### Data Separation
- **Redis**: Trading session data (positions, orders, balance, sessions)
- **TickCache**: Market data (LTP, volume, OHLC) - in-memory only
- **CSV Master**: Instrument metadata (expiry, strike, option type) - file-based

### Session Management
- Intraday sessions using `PAPER_YYYYMMDD` format
- Automatic session resumption on application restart
- Real-time persistence of all trading data

### Performance Considerations
- Hot cache for frequently accessed data
- TTL-based expiration for temporary data
- Atomic operations for data consistency

## Usage

The Redis integration is transparent to the application. All trading data is automatically persisted to Redis when using the paper trading mode.

For development and debugging, refer to the individual documentation files for detailed technical specifications.
