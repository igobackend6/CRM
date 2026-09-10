enum AppFlavor {
  development,
  staging,
  production;

  static AppFlavor fromName(String name) {
    return AppFlavor.values.firstWhere(
      (flavor) => flavor.name == name,
      orElse: () => AppFlavor.development,
    );
  }
}
