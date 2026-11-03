import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linqo/theme.dart';
import 'package:linqo/ui/brand.dart';

void main() {
  testWidgets(
    'complete-logo startup fits narrow, short and large-text screens',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final size in [const Size(360, 800), const Size(800, 360)]) {
        tester.view.physicalSize = size;
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: linqoTheme(Brightness.light),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: const LinqoSplash(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$size / $scale');
          final image = tester.widget<Image>(find.byType(Image));
          expect((image.image as ResizeImage).imageProvider, isA<AssetImage>());
          expect(
            ((image.image as ResizeImage).imageProvider as AssetImage)
                .assetName,
            'assets/brand/linqo-full.png',
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'primary controls and secondary copy retain readable contrast in both themes',
    () {
      double contrast(Color a, Color b) {
        final first = a.computeLuminance(), second = b.computeLuminance();
        return first > second
            ? (first + .05) / (second + .05)
            : (second + .05) / (first + .05);
      }

      for (final brightness in Brightness.values) {
        final theme = linqoTheme(brightness), scheme = theme.colorScheme;
        expect(
          contrast(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.onSurfaceVariant, theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(7),
        );
      }
    },
  );
}
