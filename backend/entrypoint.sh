#!/bin/sh
set -e

# Apply database migrations
python manage.py migrate --noinput

# Execute container command
exec "$@"
