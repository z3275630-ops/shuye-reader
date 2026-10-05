import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'form_field.dart';

Future<Map<String, String>?> editFields(
  BuildContext context,
  String title,
  Map<String, String> fields, {
  Set<String> passwords = const {},
  String? description,
  Map<String, String? Function(String)> validators = const {},
  Map<String, int> maxLengths = const {},
  Map<String, TextInputType> keyboardTypes = const {},
  bool autofocus = false,
}) => showDialog<Map<String, String>>(
  context: context,
  builder: (_) => _EditDialog(
    title: title,
    fields: fields,
    passwords: passwords,
    description: description,
    validators: validators,
    maxLengths: maxLengths,
    keyboardTypes: keyboardTypes,
    autofocus: autofocus,
  ),
);

class _EditDialog extends StatefulWidget {
  final String title;
  final Map<String, String> fields;
  final Set<String> passwords;
  final String? description;
  final Map<String, String? Function(String)> validators;
  final Map<String, int> maxLengths;
  final Map<String, TextInputType> keyboardTypes;
  final bool autofocus;
  const _EditDialog({
    required this.title,
    required this.fields,
    required this.passwords,
    required this.description,
    required this.validators,
    required this.maxLengths,
    required this.keyboardTypes,
    required this.autofocus,
  });

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final form = GlobalKey<FormState>();
  late final controllers = {
    for (final entry in widget.fields.entries)
      entry.key: TextEditingController(text: entry.value),
  };
  final visiblePasswords = <String>{};

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void save() {
    if (!form.currentState!.validate()) return;
    Navigator.pop(context, {
      for (final entry in controllers.entries)
        entry.key: entry.value.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(widget.description!),
              ),
            for (final entry in controllers.entries) field(entry),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: save, child: const Text('保存')),
    ],
  );

  Widget field(MapEntry<String, TextEditingController> entry) {
    final name = entry.key;
    final password = widget.passwords.contains(name);
    final multiline =
        !password &&
        (name.contains('正文') || name.contains('提示词') || name.contains('说明'));
    final last = name == controllers.keys.last;
    final visible = visiblePasswords.contains(name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LabeledField(
        label: name,
        child: TextFormField(
          controller: entry.value,
          autofocus: widget.autofocus && name == controllers.keys.first,
          obscureText: password && !visible,
          autocorrect: !password,
          enableSuggestions: !password,
          maxLines: multiline ? 5 : 1,
          maxLength: widget.maxLengths[name],
          keyboardType: widget.keyboardTypes[name],
          validator: (value) => widget.validators[name]?.call(value!.trim()),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          textInputAction: multiline
              ? TextInputAction.newline
              : last
              ? TextInputAction.done
              : TextInputAction.next,
          onFieldSubmitted: last && !multiline ? (_) => save() : null,
          decoration: InputDecoration(
            suffixIcon: password
                ? IconButton(
                    tooltip: visible ? '隐藏$name' : '显示$name',
                    onPressed: () => setState(() {
                      if (visible) {
                        visiblePasswords.remove(name);
                      } else {
                        visiblePasswords.add(name);
                      }
                    }),
                    icon: ShuyeIcon(
                      visible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
