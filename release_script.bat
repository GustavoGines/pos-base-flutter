git add .
git commit -m "fix: resolver error de sintaxis de PowerShell en OTA y sanear rutas en actualizador"
git push origin develop
git checkout main
git merge develop
git push origin main
git tag -d v1.3.0
git push origin :refs/tags/v1.3.0
git tag v1.3.0
git push origin v1.3.0
git checkout develop
