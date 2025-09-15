# DhanScalper Documentation

This directory contains comprehensive documentation for the DhanScalper trading system.

## Directory Structure

```
docs/
├── README.md                    # This file
└── redis/                       # Redis integration documentation
    ├── README.md               # Redis documentation index
    ├── redis_data_contracts.md # Redis data structure specifications
    ├── REDIS_MIGRATION_SUMMARY.md # Migration from file-based to Redis storage
    ├── redis_structure_diagram.txt # Visual Redis key hierarchy
    ├── redis_contracts_diagram.txt # Data contracts visualization
    └── redis_keys_analysis.md  # Redis key patterns analysis
```

## Documentation Overview

### Redis Integration
The Redis integration documentation covers the migration from file-based storage to Redis for trading session data, including:
- Data structure specifications
- Key naming conventions
- Migration strategies
- Performance considerations

### System Architecture
- **Market Data**: In-memory `TickCache` for real-time performance
- **Trading Data**: Redis for persistent session data
- **Instrument Data**: CSV Master for metadata

## Quick Start

1. **Redis Setup**: Ensure Redis is running on `localhost:6379`
2. **Configuration**: Use `config/scalper.yml` for system configuration
3. **Paper Trading**: Run `bundle exec exe/dhan_scalper paper -c config/scalper.yml`

## Contributing

When adding new documentation:
- Place Redis-related docs in `docs/redis/`
- Update the appropriate README.md files
- Follow the existing naming conventions
- Include both technical specifications and visual diagrams where helpful
