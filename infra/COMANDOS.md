# Docker: comandos de BeanGo

Ejecuta todos los comandos desde la raíz del proyecto.

## Primera ejecución

```bash
cp .env.docker.example .env
docker compose run --rm backend php artisan key:generate --show
```

Copia la clave que imprime el segundo comando en `APP_KEY` dentro de `.env`.
Después, construye e inicia los servicios:

```bash
docker compose up --build -d
docker compose exec backend php artisan migrate --seed
docker compose exec backend php artisan storage:link
```

Servicios disponibles: cliente en `http://localhost:8080`, panel en
`http://localhost:8081` y API en `http://localhost:8000`.

## Operación diaria

```bash
# Ver estado y logs
docker compose ps
docker compose logs -f

# Logs de un servicio concreto
docker compose logs -f backend
docker compose logs -f queue

# Ejecutar Artisan
docker compose exec backend php artisan migrate
docker compose exec backend php artisan test
docker compose exec backend php artisan tinker

# Reconstruir después de cambiar dependencias o Dockerfiles
docker compose up --build -d

# Detener los servicios sin borrar datos
docker compose down
```

## Reinicio completo de datos locales

Este comando elimina de forma irreversible la base de datos, Redis y los
archivos almacenados por Docker. Úsalo solamente para reiniciar el entorno de
desarrollo.

```bash
docker compose down -v
docker compose up --build -d
docker compose exec backend php artisan migrate --seed
docker compose exec backend php artisan storage:link
```
