import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../library/library_store.dart';
import 'tiers.dart';

class EntitlementVerifier {
  EntitlementVerifier(this.publicKey);
  final String publicKey;
  Future<AppTier> verify(String token, String uid) async {
    final parts = token.split('.');
    if (parts.length != 3 || token.length > 4096) {
      throw const FormatException('Invalid entitlement.');
    }
    List<int> decode(String s) => base64Url.decode(base64Url.normalize(s));
    final header = jsonDecode(utf8.decode(decode(parts[0]))) as Map;
    final value = jsonDecode(utf8.decode(decode(parts[1]))) as Map;
    if (header['alg'] != 'EdDSA' ||
        value['aud'] != 'dev.linqo.linqo' ||
        value['iss'] != 'linqo-cloud' ||
        value['sub'] != uid ||
        value['version'] != 1 ||
        value['iat'] is! num ||
        (value['iat'] as num) >
            DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300) {
      throw const FormatException('Entitlement does not match this account.');
    }
    final verified = await Ed25519().verify(
      utf8.encode('${parts[0]}.${parts[1]}'),
      signature: Signature(
        decode(parts[2]),
        publicKey: SimplePublicKey(
          decode(publicKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!verified) {
      throw const FormatException('Invalid entitlement signature.');
    }
    return AppTier.values.byName(value['tier'] as String);
  }

  Future<AppTier> restore(LibraryStore store, String uid) async {
    try {
      return await verify(
        await store.preference('entitlement_$uid') ?? '',
        uid,
      );
    } catch (_) {
      return AppTier.free;
    }
  }
}
