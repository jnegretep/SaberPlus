// test/core/result_test.dart
// Unit tests for Result<T> sealed class

import 'package:flutter_test/flutter_test.dart';
import 'package:saberplus_app/core/types/result.dart';

void main() {
  group('Result<T>', () {
    test('Success holds value', () {
      const result = Success<int>(42);
      expect(result, isA<Success<int>>());
      expect((result as Success<int>).value, equals(42));
    });

    test('Failure holds error message', () {
      const result = Failure<String>('Error de red');
      expect(result, isA<Failure<String>>());
      expect((result as Failure<String>).message, equals('Error de red'));
    });

    test('Success.when calls onSuccess callback', () {
      const result = Success<int>(10);
      final output = result.when(
        onSuccess: (value) => 'Valor: $value',
        onFailure: (message) => 'Error: $message',
      );
      expect(output, equals('Valor: 10'));
    });

    test('Failure.when calls onFailure callback', () {
      const result = Failure<int>('No encontrado');
      final output = result.when(
        onSuccess: (value) => 'Valor: $value',
        onFailure: (message) => 'Error: $message',
      );
      expect(output, equals('Error: No encontrado'));
    });

    test('Success.isSuccess is true', () {
      const result = Success<int>(5);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
    });

    test('Failure.isFailure is true', () {
      const result = Failure<int>('Error');
      expect(result.isFailure, isTrue);
      expect(result.isSuccess, isFalse);
    });
  });
}
