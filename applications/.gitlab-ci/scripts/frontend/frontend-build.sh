#!/bin/bash

set -e

echo "Installing dependencies..."

cd win-web

corepack enable
corepack prepare pnpm@9.15.4 --activate

pnpm install --frozen-lockfile

echo "Building web application..."

pnpm --filter @repo/web exec vite build

ls -la apps/web/dist