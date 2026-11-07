# Third-party notices

Linqo's original code is licensed under [Apache-2.0](LICENSE). Dependencies and model files retain their own licenses; the app license does not replace them.

The complete [accompanying license bundle](THIRD_PARTY_LICENSES.txt) is regenerated from the current v0.8.3 build and attached to its release. Keep it with the APK when redistributing it. It combines this build's Flutter-generated notices with the MIT notices for the pinned native llama.cpp/ggml runtime, whose attribution is absent from Flutter's generated in-app list. Earlier published releases include their corresponding notice bundles.

- **Fredoka** and **Nunito** are bundled under the SIL Open Font License 1.1. Their complete copyright and license notices ship in [assets/fonts/fredoka-OFL.txt](assets/fonts/fredoka-OFL.txt) and [assets/fonts/nunito-OFL.txt](assets/fonts/nunito-OFL.txt).
- **Flutter/Dart packages and native dependencies:** Flutter assembles their dependency notices into the APK's `NOTICES.Z`. Open **Settings → Open-source licenses** in Linqo to read the notices. Dependency versions are pinned in `pubspec.lock`; native inference uses llamadart and llama.cpp. Redistribution must preserve applicable upstream notices.
- **Optional Qwen3 model:** weights are downloaded only after explicit user action, and are not included in the repository or APK. See the [pinned model repository](https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/tree/50968a4468ef4233ed78cd7c3de230dd1d61a56b) for its license and model card. Imported models may have different licenses.
- **Brand artwork:** supplied by the project owner; the text-free mascot variant was isolated using image generation. Artwork provenance is embedded in the PNG assets. The software license does not grant trademark rights to the Linqo name or logo.
