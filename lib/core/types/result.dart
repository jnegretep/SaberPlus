// lib/core/types/result.dart
// Result type para error handling sin exceptions
// Inspirado en Kotlin's Result y Swift's Result

/// Result<T> = Success<T> | Failure<T>
/// Permite manejar errores de forma type-safe sin try/catch
sealed class Result<T> {
  const Result();

  /// Retorna true si es Success
  bool get isSuccess => this is Success<T>;

  /// Retorna true si es Failure
  bool get isFailure => this is Failure<T>;

  /// Retorna el valor o null si es Failure
  T? get valueOrNull => switch (this) {
    Success(:final data) => data,
    Failure() => null,
  };

  /// Retorna el error o null si es Success
  String? get errorOrNull => switch (this) {
    Success() => null,
    Failure(:final message) => message,
  };

  /// Transforma el valor si es Success
  Result<R> map<R>(R Function(T data) transformer) => switch (this) {
    Success(:final data) => Success(transformer(data)),
    Failure(:final message) => Failure(message),
  };

  /// Retorna el valor o ejecuta orElse si es Failure
  T getOrElse(T Function() orElse) => switch (this) {
    Success(:final data) => data,
    Failure() => orElse(),
  };

  /// Retorna el valor o el default
  T getOrDefault(T defaultValue) => getOrElse(() => defaultValue);
}

/// Resultado exitoso con data
class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);

  @override
  String toString() => 'Success($data)';
}

/// Resultado fallido con mensaje de error
class Failure<T> extends Result<T> {
  final String message;
  const Failure(this.message);

  @override
  String toString() => 'Failure($message)';
}
