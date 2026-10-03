<?php
$file = 'lib/features/users/presentation/widgets/employee_form_dialog.dart';
$content = file_get_contents($file);

$search = "const SizedBox(height: 12),
                      ...kCategorizedPermissions.map((category) {";

$replace = "const SizedBox(height: 12),
                      if (!isAdmin)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _permissions.addAll(AppPermissions.all);
                                  });
                                },
                                icon: const Icon(Icons.check_box_outlined, size: 18),
                                label: const Text('Marcar Todos', style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _permissions.clear();
                                  });
                                },
                                icon: const Icon(Icons.check_box_outline_blank, size: 18, color: Colors.redAccent),
                                label: const Text('Desmarcar Todos', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ...kCategorizedPermissions.map((category) {";

$content = str_replace($search, $replace, $content);

file_put_contents($file, $content);
?>
