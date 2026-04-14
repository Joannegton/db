-- ============================================================================
-- PostgreSQL Setup - Banco Centralizado com Usuários e Permissões
-- ============================================================================
-- Execute este script como SUPERUSER (postgres)
-- psql -U postgres -d postgres -f postgres-setup.sql
-- ============================================================================

-- ===========================================
-- 1. CRIAR USUÁRIOS (ROLES)
-- ===========================================

-- Deletar usuários se existirem (para reset)
DROP ROLE IF EXISTS auth_app;
DROP ROLE IF EXISTS bot_financas_app;

-- Criar usuários com segurança
CREATE ROLE auth_app WITH LOGIN PASSWORD 'aB7kQxM9wL2pRsT4vU5zY8nJ3cD6eF1hG';
CREATE ROLE bot_financas_app WITH LOGIN PASSWORD 'mN4oP7qR8sT9uV2wX3yZ5aB6cD9eF1gH';

-- Configurar parâmetros padrão para os usuários
ALTER ROLE auth_app SET statement_timeout = '30s';
ALTER ROLE bot_financas_app SET statement_timeout = '30s';

-- ===========================================
-- 2. CRIAR BANCOS DE DADOS
-- ===========================================

-- Criar bancos
CREATE DATABASE auth WITH OWNER auth_app ENCODING 'UTF8';
CREATE DATABASE bot_financas WITH OWNER bot_financas_app ENCODING 'UTF8';

-- ===========================================
-- 3. PERMISSÕES NO BANCO auth
-- ===========================================

\c auth

-- Criar extension para UUIDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- auth_app: OWNER do banco, acesso total
GRANT ALL PRIVILEGES ON DATABASE auth TO auth_app;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO auth_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO auth_app;


-- ===========================================
-- 4. PERMISSÕES NO BANCO bot_financas
-- ===========================================

\c bot_financas

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- bot_financas_app: OWNER do banco, acesso total
GRANT ALL PRIVILEGES ON DATABASE bot_financas TO bot_financas_app;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO bot_financas_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO bot_financas_app;


-- ===========================================
-- 5. CONFIGURAÇÕES DE SEGURANÇA GLOBAIS
-- ===========================================

\c postgres

-- SSL desabilitado (use em produção com certificados válidos)
-- ALTER SYSTEM SET ssl = on;

-- Configurar log de conexões
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
ALTER SYSTEM SET log_duration = off;

-- Configurar log de statements lentos (> 1s)
ALTER SYSTEM SET log_min_duration_statement = 1000;

-- Recarregar configurações
SELECT pg_reload_conf();

\echo '✅ Setup concluído! Bancos, usuários e permissões criados.'
