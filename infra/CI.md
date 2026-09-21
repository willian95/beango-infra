# CI/CD: tests → build fuera del servidor → Docker Hub → deploy

Cada repo (`beango-front`, `beango-admin`, `beango-backend`) tiene su propio
workflow en `.github/workflows/ci.yml`. En cada push a `main`:

1. **Test** — corre la suite de tests del repo (PHPUnit en backend contra un
   contenedor de MySQL; `pnpm test --if-present` + `pnpm build` en
   front/admin, que además valida que el proyecto compila).
2. **Build & push** (solo si `test` pasó) — compila la imagen Docker
   **en el runner de GitHub Actions**, nunca en el servidor, usando los
   `Dockerfile` de este repo (`infra/*.Dockerfile`, que cada workflow
   descarga haciendo checkout de `willian95/beango-infra` como contexto
   adicional). La imagen se sube a Docker Hub como
   `willian95/beango-<app>:latest` y `willian95/beango-<app>:<sha>`.
3. **Dispatch** — el repo avisa a `beango-infra` (este repo) con un evento
   `repository_dispatch` de tipo `image-updated`.

Este repo (`beango-infra`) reacciona a ese evento con
[`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml): se
conecta por SSH al EC2 y ejecuta:

```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```

Como las imágenes ya vienen compiladas desde Docker Hub, el servidor nunca
vuelve a compilar nada — se elimina el problema de OOM al construir en una
instancia de ~950MB de RAM (ver el historial de [DEPLOY.md](DEPLOY.md)).

## Secrets y variables a configurar

### En cada repo de aplicación (`beango-front`, `beango-admin`, `beango-backend`)

Bajo `Settings > Secrets and variables > Actions`:

| Nombre | Tipo | Valor |
|---|---|---|
| `DOCKERHUB_USERNAME` | Secret | `willian95` |
| `DOCKERHUB_TOKEN` | Secret | [Access Token](https://hub.docker.com/settings/security) de Docker Hub (no la contraseña) con permiso de escritura |
| `INFRA_DISPATCH_TOKEN` | Secret | Personal Access Token de GitHub (classic, scope `repo`, o fine-grained con `contents:write` + `actions:write` sobre `willian95/beango-infra`) perteneciente a una cuenta con acceso de push a `beango-infra` |

Solo en `beango-front` y `beango-admin`, además:

| Nombre | Tipo | Valor |
|---|---|---|
| `VITE_API_URL` | Variable (no secret) | URL pública de la API, p.ej. `http://<ip-o-dominio>:8000/api/v1` — queda incrustada en el build, igual que en `DEPLOY.md` |

### En este repo (`beango-infra`)

| Nombre | Tipo | Valor |
|---|---|---|
| `DEPLOY_HOST` | Secret | IP o dominio del EC2 (hoy `44.203.210.231`) |
| `DEPLOY_USER` | Secret | `ubuntu` |
| `DEPLOY_SSH_KEY` | Secret | Contenido **privado** de `beangofront.pem` — pégalo tal cual (incluyendo las líneas `BEGIN/END`) desde tu máquina, nunca lo subas a un archivo del repo |

> `beangofront.pem` y `.env` están sin trackear (`git status` los marca con
> `??`) — que siga así. La clave privada solo debe vivir en el secret de
> GitHub Actions y en tu máquina local.

## Primer despliegue con este flujo

El servidor ya no necesita clonar `beango-front`/`beango-admin`/`beango-backend`
ni sus submódulos — solo compone contenedores a partir de imágenes ya
construidas. Ver [DEPLOY.md](DEPLOY.md) actualizado.

## Redeploy manual

Si necesitas forzar un redeploy sin tocar código (p.ej. tras cambiar un
secret), dispara `deploy.yml` a mano desde la pestaña *Actions* de
`beango-infra` (`workflow_dispatch`), o directo en el servidor:

```bash
cd ~/beango-infra
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```
