# Deploy en AWS (EC2)

Guía paso a paso para desplegar `beango-infra` en una instancia EC2 nueva,
basada en el despliegue realizado en `44.203.210.231`. Ejecuta todo lo que
sea posible desde la raíz del repo en el servidor (`~/beango-infra`).

> Desde que existe el pipeline de CI/CD ([CI.md](CI.md)), las imágenes de
> `front`, `admin` y `backend` se compilan en GitHub Actions y se publican en
> Docker Hub — **el servidor solo hace `pull`, nunca `build`**. Esta guía usa
> `docker-compose.prod.yml` (basado en imágenes) en vez de
> `docker-compose.yml` (basado en build, pensado para desarrollo local).

## 0. Datos del servidor de referencia

- IP: `44.203.210.231` (DNS público: `ec2-44-203-210-231.compute-1.amazonaws.com`)
- Usuario: `ubuntu`
- Acceso: `ssh -i beangofront.pem ubuntu@44.203.210.231`
- Recursos: **~950MB RAM, ~6.7GB de disco** — instancia muy pequeña (tipo
  micro). Antes del pipeline de CI/CD, compilar las 3 imágenes en esta
  instancia tumbaba el sistema por OOM (ver la sección "Problemas
  conocidos"); con `docker-compose.prod.yml` ya no se compila nada aquí, así
  que ese riesgo desaparece.

## 1. Conexión y clonado del repositorio

```bash
ssh -i beangofront.pem ubuntu@44.203.210.231
```

`beango-infra` es un repo público, se clona sin credenciales:

```bash
git clone https://github.com/willian95/beango-infra.git
cd beango-infra
```

## 2. Submódulos

Ya **no hacen falta** en el servidor: `beango-front`, `beango-admin` y
`beango-backend` se compilan en GitHub Actions (ver [CI.md](CI.md)) y llegan
al servidor como imágenes de Docker Hub, no como código fuente. No corras
`git submodule update` aquí — las carpetas `beango-front/`, `beango-admin/`
y `beango-backend/` quedarán vacías y no se usan para nada en
`docker-compose.prod.yml`.

## 3. Instalar Docker y Docker Compose

```bash
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu   # cierra y abre sesión SSH para que aplique
```

## 4. (Obsoleto) Limitaciones de recursos al construir localmente

Esta sección aplicaba cuando el servidor compilaba las 3 imágenes con
`docker compose build`. Ya no aplica con `docker-compose.prod.yml`, porque
el servidor solo descarga imágenes ya construidas — no necesita swap ni
construir una por una. Se deja documentada por si alguna vez vuelves a
compilar localmente con `docker-compose.yml` (por ejemplo, en un entorno de
desarrollo):

- La instancia de referencia solo tiene ~950MB de RAM y sin swap; compilar
  los 3 servicios en paralelo tumbó el sistema completo por OOM.
- Si necesitas construir ahí de todos modos: agrega un swapfile de
  512MB–1GB, construye una imagen a la vez (`docker compose build backend`,
  luego `front`, luego `admin`), y si el disco se llena usa
  `docker image prune -af && docker builder prune -af`.

## 5. Configurar `.env`

Copia `.env.docker.example` como base, pero **usa la IP pública o el dominio
real del servidor, no `localhost`** en las URLs — si dejas `localhost`, el
front queda con la URL de la API mal incrustada (Vite la fija en tiempo de
build) y el backend rechaza las peticiones por CORS.

```env
APP_KEY=base64:...   # docker compose -f docker-compose.prod.yml run --rm backend php artisan key:generate --show
DB_DATABASE=beango
DB_USERNAME=beango
DB_PASSWORD=<contraseña real, no la de ejemplo>
DB_ROOT_PASSWORD=<contraseña real, no la de ejemplo>

APP_URL=http://<ip-o-dominio>:8000
FRONTEND_URL=http://<ip-o-dominio>:8080
ADMIN_URL=http://<ip-o-dominio>:8081
VITE_API_URL=http://<ip-o-dominio>:8000/api/v1
```

Si más adelante cambias la IP/dominio, `VITE_API_URL` ya no se toca en el
servidor: es un **build arg** que se fija en el workflow de `beango-front` y
`beango-admin` (repository variable `VITE_API_URL`, ver [CI.md](CI.md)).
Actualiza esa variable en GitHub, vuelve a correr el workflow (push a `main`
o "Re-run jobs"), y cuando termine el deploy automático llegará la imagen
nueva al servidor.

## 6. Levantar el stack

```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml ps
```

## 7. Inicializar la base de datos

```bash
docker compose -f docker-compose.prod.yml exec -u www-data backend php artisan migrate --force
```

Passport necesita dos cosas más que `migrate` no hace por sí solo:

```bash
# Llaves de cifrado OAuth (si no existen)
docker compose -f docker-compose.prod.yml exec -u www-data backend php artisan passport:keys --force

# Cliente de acceso personal — sin esto, cualquier login/registro falla
# con "Personal access client not found."
docker compose -f docker-compose.prod.yml exec -u www-data backend php artisan passport:client --personal --name="BeanGo Personal Access Client" --no-interaction
```

Luego los datos base (roles, categorías, salas de ejemplo, etc.):

```bash
docker compose -f docker-compose.prod.yml exec -u www-data backend php artisan db:seed --force
docker compose -f docker-compose.prod.yml exec -u www-data backend php artisan db:seed --class=PaymentAccountSeeder --force
```

No corras `OauthSeed`: es una alternativa a `passport:client` que inserta un
`oauth_clients` con id fijo — si ya creaste el cliente con el comando de
arriba, `OauthSeed` falla por clave duplicada.

> **Importante:** ejecuta los comandos `artisan` con `-u www-data` (como en
> los ejemplos de arriba). Si los corres como root (usuario por defecto de
> `docker compose exec`), cualquier archivo que Laravel cree en `storage/`
> (cache, sesiones, llaves) queda con dueño `root` y Apache (que corre como
> `www-data`) no puede escribirlo ni leerlo después — causa errores como
> `Permission denied` en `storage/framework/cache/...`. Si ya se te olvidó y
> ves ese error, arréglalo con:
> ```bash
> docker compose -f docker-compose.prod.yml exec backend chown -R www-data:www-data storage bootstrap/cache
> ```

## 8. Verificación

```bash
curl -s -o /dev/null -w 'backend: %{http_code}\n' http://localhost:8000
curl -s -o /dev/null -w 'front: %{http_code}\n'   http://localhost:8080
curl -s -o /dev/null -w 'admin: %{http_code}\n'   http://localhost:8081
```

Los tres deben responder `200`. Prueba también un registro real desde el
front en el navegador.

## Problemas conocidos y solución rápida

| Síntoma | Causa | Solución |
|---|---|---|
| Error de CORS en el navegador | `.env` con URLs `localhost` en vez de la IP/dominio real | Corregir `.env` y actualizar la variable `VITE_API_URL` en GitHub (paso 5) para que se reconstruya la imagen |
| Backend responde 500 en `/` | Faltan llaves de Passport o no son legibles por `www-data` | `passport:keys --force` + `chown -R www-data:www-data storage` |
| 422 al registrarse: `REGISTRATION_FAILED` | Falta el Personal Access Client de Passport, o falta sembrar los roles (`user`, `admin`, `organizer`) | `passport:client --personal` y `db:seed --class=RolesPermissionSeeder` |
| `Permission denied` al escribir en `storage/framework/...` | Un comando `artisan` se corrió como root y dejó archivos con ese dueño | `docker compose -f docker-compose.prod.yml exec backend chown -R www-data:www-data storage bootstrap/cache` |
| `no space left on device` al hacer `pull` | Poco disco + caché de imágenes/capas anteriores | `docker image prune -af` |
| El deploy automático no llega al servidor | El `repository_dispatch` no disparó (`INFRA_DISPATCH_TOKEN` inválido/expirado) o el job SSH falló | Revisa los logs de *Actions* en el repo de la app y en `beango-infra`; corre `deploy.yml` manualmente (`workflow_dispatch`) mientras tanto |

Riesgo de OOM al **construir** localmente: ver la sección 4 (obsoleta con
el pipeline de CI/CD, pero útil si alguna vez vuelves a compilar en el
servidor).
