enum PreviewKind {
  image,
  text,
  binary,
}

class PreviewPayload {
  const PreviewPayload({
    required this.name,
    required this.bytes,
    required this.kind,
    this.text,
  });

  final String name;
  final List<int> bytes;
  final PreviewKind kind;
  final String? text;
}
