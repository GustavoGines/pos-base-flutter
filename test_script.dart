import 'dart:io';

void main() async {
  final targetDir = r'C:\pos\pos-backend';
  final zipPath = r'C:\pos\temp.zip';
  final argList = '--component=backend --target-dir="$targetDir" --zip-path="$zipPath"';
  
  final processArgs = [
    'Start-Process',
    '-FilePath', 'cmd',
    '-ArgumentList', '\'/c echo $argList > C:\\laragon\\www\\Sistema_POS\\pos-frontend\\test_output.txt\'',
    '-Wait'
  ];

  final result = await Process.run('powershell', processArgs);
  print(result.stdout);
  print(result.stderr);
}
