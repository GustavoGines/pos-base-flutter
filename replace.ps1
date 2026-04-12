$files = Get-ChildItem -Path "c:\laragon\www\Sistema_POS\pos-frontend\lib" -Recurse -Filter "*.dart"

foreach ($file in $files) {
    if ($file.FullName -match "currency_formatter.dart$") { continue }
    $content = Get-Content $file.FullName -Raw
    
    $modified = $false
    
    if ($content -match "\.toStringAsFixed\(2\)") {
        $content = $content -replace '\.toStringAsFixed\(2\)', '.toCurrency()'
        $modified = $true
    }
    
    if ($content -match "\.toStringAsFixed\(3\)") {
        $content = $content -replace '\.toStringAsFixed\(3\)', '.toQty()'
        $modified = $true
    }
    
    if ($modified) {
        if (-not ($content -match "package:frontend_desktop/core/utils/currency_formatter.dart")) {
            $content = "import 'package:frontend_desktop/core/utils/currency_formatter.dart';`n" + $content
        }
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Updated $($file.FullName)"
    }
}
