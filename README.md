# 🐘 PostgreSQL Centralizado com Docker

## 📖 Visão Geral

Arquitetura **simples, segura e performática**:

- ✅ **Microsserviços em Docker** (NestJS, etc) na VPS → acessam banco via `postgres-central:5432` (rede interna)
- ✅ **Você (DBeaver)** no seu PC → acessa banco via **SSH Tunnel** (banco invisível, super seguro)
- ✅ **Sem Nginx, sem SSL complexo** → apenas SSH (que já criptografa!)

---

## 📁 Estrutura de Arquivos

```
db/
├── docker-compose.postgres.yml      ← PostgreSQL em Docker (simples!)
├── postgres-setup.sql               ← Bancos + usuários
├── postgres.conf                    ← Config PostgreSQL
├── pg_hba.conf                      ← Autenticação
│
├── .env.example
│
└── README.md                        ← Este arquivo
```

---

## 🎯 Como Funciona

### Seu PC (em casa)

```
DBeaver
   ↓
[SSH Tunnel = localhost:5432]
   ↓
VPS (203.0.113.45:22 SSH)
   ↓
[PostgreSQL em localhost:5432]
```

### VPS (microsserviços)

```
Docker Network "backend"
   ├─ PostgreSQL (postgres-central:5432)
   ├─ NestJS Auth → postgres-central:5432
   └─ NestJS Bot  → postgres-central:5432
```

---

## 🚀 Quick Start

### 1️⃣ PostgreSQL já está rodando na VPS?

```bash
# SSH na VPS
ssh joannegton@203.0.113.45

# Verificar
docker ps | grep postgres-central
docker exec postgres-central psql -U postgres -c "SELECT version();"
```

### 2️⃣ PostgreSQL Não Está Rodando

#### Na VPS - Iniciar Container

```bash
# Dentro da pasta db/
cd /caminho/da/pasta/db

# Baixar a imagem e iniciar
docker-compose -f docker-compose.postgres.yml up -d

# Verificar se está rodando
docker ps | grep postgres-central

# Ver logs
docker logs postgres-central

# Entrar no container
docker exec -it postgres-central psql -U joannegton -d postgres
```

#### Troubleshooting

**❌ "Porta 5432 já está em uso"**

```bash
# Parar container anterior
docker-compose -f docker-compose.postgres.yml down

# Remover volumes se quiser resetar dados
docker-compose -f docker-compose.postgres.yml down -v

# Iniciar novamente
docker-compose -f docker-compose.postgres.yml up -d
```

**❌ "Arquivo config não encontrado"**

```bash
# Verificar se os arquivos existem
ls -la postgres.conf pg_hba.conf postgres-setup.sql

# Se não existir, clonar do repo
git clone <repo-url> --sparse
git sparse-checkout set db
```

**❌ "Erro ao conectar"**

```bash
# Ver logs detalhados
docker logs -f postgres-central

# Verificar saúde do container
docker exec postgres-central pg_isready -U joannegton
```

### 3️⃣ Configurar DBeaver (seu PC)

```
Abra DBeaver

Database → New Connection → PostgreSQL

MAIN:
  Host: localhost
  Port: 5432
  Database: auth
  Username: auth_app
  Password: senhaBanco

SSH:
  ☑ Use SSH Tunnel
  Remote Host: 203.0.113.45
  Remote Port: 22
  Username: joannegton
  Password: sua_senha_ssh ou chave

SSL: ☐ Desmarque (SSH já faz isso!)

Test Connection → ✅ Success!
```

### 4️⃣ Microsserviços (na VPS)

```env
# Seu .env no NestJS
DATABASE_URL=postgresql://auth_app:senha@postgres-central:5432/auth
```

Pronto! 🎉

---

## 🔐 Segurança

### Banco Está Completamente Invisível

```bash
# Na VPS
sudo ufw status
# Esperado:
# 22/tcp    ALLOW     (SSH - para você)
# 80/tcp    ALLOW     (seus apps)
# 443/tcp   ALLOW     (seus apps)

```

### Scanner de Vulnerabilidades Não Encontra Nada

```bash
# Alguém tentando escanear sua VPS
nmap 203.0.113.45
# Output: 22/tcp (SSH), 80/tcp (HTTP), 443/tcp (HTTPS)
# ❌ Nenhuma menção ao PostgreSQL!
```

---
