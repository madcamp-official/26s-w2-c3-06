import 'package:flutter/material.dart';

/// 공통 입력창. 라벨/힌트/키보드 타입 등을 통일된 스타일로 제공한다.
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hintText;
  final int? maxLength;
  final int maxLines;
  final TextInputType keyboardType;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final EdgeInsetsGeometry? contentPadding;
  final bool enabled;
  final bool readOnly;

  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hintText,
    this.maxLength,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.onSubmitted,
    this.onChanged,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.contentPadding,
    this.enabled = true,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        counterText: '',
        suffixIcon: suffixIcon,
        prefixIcon: prefixIcon,
        contentPadding: contentPadding,
      ),
    );
  }
}
