import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// BrandingBlock shows logo, version and byline. It will try to read the
/// version from PackageInfo; if [forcedVersion] is provided it will use that
/// instead. [showDivider] controls whether a red divider is shown below.
class BrandingBlock extends StatefulWidget {
  final String? forcedVersion;
  final bool showDivider;
  const BrandingBlock({super.key, this.forcedVersion, this.showDivider = false});

  @override
  State<BrandingBlock> createState() => _BrandingBlockState();
}

class _BrandingBlockState extends State<BrandingBlock> {
  String? _version;

  @override
  void initState() {
    super.initState();
    if (widget.forcedVersion != null) {
      _version = widget.forcedVersion;
    } else {
      _loadVersion();
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version;
      final b = info.buildNumber;
      setState(() {
        _version = v.isNotEmpty ? 'V $v${b.isNotEmpty ? '+$b' : ''}' : null;
      });
    } catch (_) {
      // ignore - keep _version null so caller can fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayVersion = _version ?? 'V 1.5.5';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Image.asset('assets/images/logo.png', height: 28, fit: BoxFit.contain),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayVersion, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('By OskitarWorld', style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    // Removed 'Versión Tester' label for release builds.
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.showDivider)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(color: Colors.red, thickness: 2),
          ),
      ],
    );
  }
}
