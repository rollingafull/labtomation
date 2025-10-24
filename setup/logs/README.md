# Logs Directory

This directory contains execution logs for labtomation scripts.

## Log Files

Logs are named with the pattern: `{script_name}_{timestamp}.log`

Example:
- `labtomation_20251020_143022.log`
- `create_template_20251020_150135.log`

## Log Retention

By default, logs older than 30 days are automatically deleted.
Configure retention in `config/labtomation.conf`:

```bash
LOG_RETENTION_DAYS="30"
```

## Manual Cleanup

To clean old logs:
```bash
find logs/ -name "*.log" -mtime +30 -delete
```
