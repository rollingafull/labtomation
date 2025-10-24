# State Directory

This directory contains runtime state files for labtomation scripts.

## Files

- `labtomation.state` - Main execution state (template IDs, clone IDs, etc.)
- `*.lock` - Lock files to prevent concurrent executions
- `*.tmp` - Temporary files during execution

## Important

**DO NOT** manually edit these files unless you know what you're doing.
State files are automatically managed by the scripts for idempotency.

## Cleanup

State files are automatically cleaned up on successful completion.
If a script fails, state files remain to allow resumption.

To manually reset state:
```bash
rm -f state/*.state state/*.lock
```
