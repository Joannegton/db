-- ============================================================================
-- PostgreSQL Monitoring Queries
-- Útil para diagnóstico e ajuste de performance
-- ============================================================================

-- ===========================================
-- 1. CACHE HIT RATIO (Target > 99%)
-- ===========================================
SELECT
  sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit) as heap_hit,
  ROUND(100.0 * sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read))::numeric, 2) as cache_hit_ratio
FROM pg_statio_user_tables;

-- Por índice:
SELECT
  schemaname,
  tablename,
  indexname,
  idx_blks_read as read_count,
  idx_blks_hit as hit_count,
  ROUND(100.0 * idx_blks_hit / (idx_blks_hit + idx_blks_read)::numeric, 2) as hit_ratio
FROM pg_statio_user_indexes
WHERE idx_blks_read + idx_blks_hit > 0
ORDER BY hit_ratio ASC
LIMIT 10;

-- ===========================================
-- 2. QUERIES LENTAS (Top 10)
-- ===========================================
-- ⚠️ Requer: CREATE EXTENSION pg_stat_statements;
SELECT
  query,
  calls,
  total_exec_time::numeric / 1000 as total_time_sec,
  mean_exec_time::numeric / 1000 as mean_time_sec,
  max_exec_time::numeric / 1000 as max_time_sec,
  ROUND(100.0 * total_exec_time / sum(total_exec_time) OVER()::numeric, 2) as pct_total
FROM pg_stat_statements
WHERE mean_exec_time > 100  -- > 100ms
ORDER BY total_exec_time DESC
LIMIT 10;

-- Resetar stats (depois de análise):
-- SELECT pg_stat_statements_reset();

-- ===========================================
-- 3. AUTOVACUUM STATUS
-- ===========================================
SELECT
  schemaname,
  tablename,
  n_live_tup as live_rows,
  n_dead_tup as dead_rows,
  ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup, 0)::numeric, 2) as dead_ratio,
  last_vacuum,
  last_autovacuum,
  last_analyze,
  last_autoanalyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000  -- Só tabelas com muitos dead rows
ORDER BY n_dead_tup DESC;

-- Tabelas que NUNCA foram autovaacuum'd (problemático):
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
WHERE last_autovacuum IS NULL
ORDER BY n_live_tup DESC;

-- ===========================================
-- 4. CONEXÕES ATIVAS
-- ===========================================
SELECT
  datname as database,
  usename as user,
  count(*) as connection_count,
  max(query_start) as oldest_query_start,
  max(backend_start) as oldest_connection
FROM pg_stat_activity
GROUP BY datname, usename
ORDER BY connection_count DESC;

-- Queries longas em execução (> 5min):
SELECT
  pid,
  usename,
  datname,
  state,
  query_start,
  NOW() - query_start as duration,
  query
FROM pg_stat_activity
WHERE state = 'active'
  AND query_start < NOW() - INTERVAL '5 minutes'
ORDER BY query_start ASC;

-- ===========================================
-- 5. TAMANHO DE TABELAS E ÍNDICES
-- ===========================================
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) as indexes_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Maiores índices (pode estar inflado):
SELECT
  schemaname,
  tablename,
  indexname,
  pg_size_pretty(pg_relation_size(schemaname||'.'||indexname)) as index_size,
  idx_scan as scans,
  idx_tup_read as tuples_read,
  idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(schemaname||'.'||indexname) DESC
LIMIT 20;

-- ===========================================
-- 6. ÍNDICES NÃO UTILIZADOS (Candidatos para drop)
-- ===========================================
-- ⚠️ Não delete sem verificar!
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan as scans,
  pg_size_pretty(pg_relation_size(schemaname||'.'||indexname)) as size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexname NOT LIKE 'pg_toast%'
ORDER BY pg_relation_size(schemaname||'.'||indexname) DESC;

-- Índices com low selectivity (< 0.1% scans vs reads):
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan as scans,
  idx_tup_read as reads,
  CASE
    WHEN idx_tup_read = 0 THEN 0
    ELSE ROUND(100.0 * idx_tup_fetch / idx_tup_read::numeric, 2)
  END as selectivity
FROM pg_stat_user_indexes
WHERE idx_scan > 0
ORDER BY selectivity ASC;

-- ===========================================
-- 7. BLOAT (Espaço desperdiçado por UPDATE/DELETE)
-- ===========================================
-- ⚠️ Requer n_live_tup + n_dead_tup > 0
SELECT
  schemaname,
  tablename,
  ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0)::numeric, 2) as dead_pct,
  n_dead_tup,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_stat_user_tables
WHERE (n_dead_tup::float / (n_live_tup + n_dead_tup)) > 0.2  -- > 20% dead
ORDER BY n_dead_tup DESC;

-- ===========================================
-- 8. LOCKS E LOCKS AGUARDANDO
-- ===========================================
SELECT
  blocked_locks.pid AS blocked_pid,
  blocked_activity.usename AS blocked_user,
  blocking_locks.pid AS blocking_pid,
  blocking_activity.usename AS blocking_user,
  blocked_activity.query AS blocked_statement,
  blocking_activity.query AS blocking_statement,
  blocked_activity.application_name AS blocked_application,
  blocking_activity.application_name AS blocking_application
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
  AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
  AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
  AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
  AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- ===========================================
-- 9. REPLICAÇÃO STATUS (se tiver replicas)
-- ===========================================
SELECT
  client_addr,
  usename,
  pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) / 1024 / 1024 as replication_lag_mb,
  state,
  write_lag,
  flush_lag,
  replay_lag
FROM pg_stat_replication;

-- ===========================================
-- 10. INFORMAÇÕES DO SERVIDOR
-- ===========================================
SELECT name, setting, short_desc
FROM pg_settings
WHERE name IN (
  'shared_buffers',
  'effective_cache_size',
  'work_mem',
  'maintenance_work_mem',
  'max_connections',
  'shared_preload_libraries',
  'max_parallel_workers',
  'wal_level'
)
ORDER BY name;

-- Versão:
SELECT version();

-- Tempo de uptime:
SELECT
  now() - pg_postmaster_start_time() as uptime,
  pg_postmaster_start_time();

-- Tamanho total de databases:
SELECT
  datname,
  pg_size_pretty(pg_database_size(datname)) as size
FROM pg_database
WHERE datname NOT IN ('template0', 'template1', 'postgres')
ORDER BY pg_database_size(datname) DESC;

-- ===========================================
-- Monitoramento continuo
-- ===========================================
-- 1. Rodar estas queries regularmente (daily/weekly)
-- 2. Configure alertas para:
--    - cache_hit_ratio < 99%
--    - dead_ratio > 20%
--    - queries mean_exec_time > 1000ms
-- 3. Use pgBadger para parsear logs automaticamente
-- 4. Configure monitoramento com Prometheus + Grafana
-- 5. Para queries lentas, use: EXPLAIN ANALYZE SELECT...;
