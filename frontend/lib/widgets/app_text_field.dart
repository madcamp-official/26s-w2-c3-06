import 'package:flutter/material.dart';

/// 공통 입력창. 라벨/힌트/키보드 타입 등을 통일된 스타일로 제공한다.
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final int? maxLength;
  final int maxLines;
  final TextInputType keyboardType;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.maxLength,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.onSubmitted,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        counterText: '',
      ),
    );
  }
}
