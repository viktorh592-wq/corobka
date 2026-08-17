import 'package:flutter_test/flutter_test.dart';

import 'package:korobka/features/images/image_service.dart';

void main() {
  const service = ImageService();

  test('Поддерживаемые расширения распознаются', () {
    expect(service.isSupported('photo.png'), isTrue);
    expect(service.isSupported('photo.JPG'), isTrue);
    expect(service.isSupported('photo.webp'), isTrue);
    expect(service.isSupported('photo.gif'), isTrue);
  });

  test('Неподдерживаемые расширения отклоняются', () {
    expect(service.isSupported('doc.pdf'), isFalse);
    expect(service.isSupported('archive.zip'), isFalse);
    expect(service.isSupported('script.dart'), isFalse);
  });
}