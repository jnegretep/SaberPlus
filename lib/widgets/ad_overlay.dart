import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ad_model.dart';
import '../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_colors.dart';

class AdOverlay extends StatefulWidget {
  final AdModel ad;

  const AdOverlay({super.key, required this.ad});

  @override
  State<AdOverlay> createState() => _AdOverlayState();
}

class _AdOverlayState extends State<AdOverlay> {
  int _remainingSeconds = 0;
  bool _canClose = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    final api = context.read<ApiService>();
    api.trackAdEvent(adId: widget.ad.id, event: 'impression');

    _remainingSeconds = widget.ad.minViewSeconds;

    if (widget.ad.showCloseImmediately || _remainingSeconds == 0) {
      _canClose = true;
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_remainingSeconds <= 1) {
          timer.cancel();
          setState(() {
            _remainingSeconds = 0;
            _canClose = true;
          });
        } else {
          setState(() => _remainingSeconds--);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _closeAd() {
    final api = context.read<ApiService>();
    api.trackAdEvent(
      adId: widget.ad.id,
      event: 'close',
      watchedSeconds: widget.ad.minViewSeconds - _remainingSeconds,
    );
    Navigator.of(context).pop();
  }

  void _handleClick() async {
    if (widget.ad.targetUrl == null) return;

    final api = context.read<ApiService>();
    api.trackAdEvent(adId: widget.ad.id, event: 'click');

    final uri = Uri.parse(widget.ad.targetUrl!);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.75),
      child: Center(
        child: Stack(
          children: [
            GestureDetector(
              onTap: _handleClick,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  widget.ad.mediaUrl,
                  width: MediaQuery.of(context).size.width * 0.85,
                  fit: BoxFit.contain,
                ),
              ),
            ),

            if (!_canClose)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_remainingSeconds',
                    style: TextStyle(color: AppColors.textOnPrimary),
                  ),
                ),
              ),

            if (_canClose)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: Icon(Icons.close, color: AppColors.textOnPrimary),
                  onPressed: _closeAd,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
