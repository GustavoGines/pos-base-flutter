<?php
$file = 'lib/features/users/presentation/widgets/employee_form_dialog.dart';
$content = file_get_contents($file);

$search = "                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        ...kCategorizedPermissions.map((category) {";

$replace = "                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        if (!isAdmin)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _permissions.addAll(AppPermissions.all);
                                    });
                                  },
                                  child: const Text('Marcar Todos', style: TextStyle(fontSize: 12)),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _permissions.clear();
                                    });
                                  },
                                  child: const Text('Desmarcar Todos', style: TextStyle(fontSize: 12, color: Colors.red)),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        ...kCategorizedPermissions.map((category) {";

$content = str_replace($search, $replace, $content);

file_put_contents($file, $content);
?>
