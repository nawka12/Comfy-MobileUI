import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? 0;
  return 0;
}

double _asDouble(dynamic v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

class TamsService {
  String _baseUrl;
  String? _apiToken;
  final http.Client _client;

  TamsService({String baseUrl = 'https://ap-east-1.tensorart.cloud/v1'})
      : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _client = http.Client();

  String get baseUrl => _baseUrl;

  bool get hasToken => _apiToken != null && _apiToken!.isNotEmpty;

  void updateBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  void setToken(String? token) {
    _apiToken = token;
  }

  Map<String, String> get _authHeaders {
    if (_apiToken != null && _apiToken!.isNotEmpty) {
      return {'Authorization': 'Bearer $_apiToken'};
    }
    return {};
  }

  Future<bool> testConnection() async {
    try {
      final resp = await _client
          .get(Uri.parse('$_baseUrl/models/1'), headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      return resp.statusCode != 401 && resp.statusCode != 403;
    } catch (_) {
      return false;
    }
  }

  Future<TamsJobResponse> createWorkflowJob(
      String requestId, Map<String, dynamic> params) async {
    final body = jsonEncode({
      'requestId': requestId,
      'params': params,
    });
    final resp = await _client.post(
      Uri.parse('$_baseUrl/jobs/workflow'),
      headers: {
        'Content-Type': 'application/json',
        ..._authHeaders,
      },
      body: body,
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return TamsJobResponse.fromJson(data);
    }
    throw _parseError(resp.statusCode, resp.body, 'Failed to create job');
  }

  Future<TamsJobResponse> getJobStatus(int jobId) async {
    final resp = await _client.get(
      Uri.parse('$_baseUrl/jobs/$jobId'),
      headers: _authHeaders,
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return TamsJobResponse.fromJson(data);
    }
    throw _parseError(resp.statusCode, resp.body, 'Failed to get job status');
  }

  TamsException _parseError(int statusCode, String body, String context) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final details = <TamsErrorDetail>[];
      if (data['details'] is List) {
        for (final d in data['details'] as List) {
          if (d is Map<String, dynamic>) {
            details.add(TamsErrorDetail(
              field: d['field'] as String? ?? '',
              message: d['message'] as String? ?? '',
            ));
          }
        }
      }
      final error = TamsError(
        statusCode: statusCode,
        code: _asInt(data['code']),
        message: data['message'] as String? ?? 'Unknown error',
        details: details,
      );

      final isCredits = details.any((d) =>
          d.message.toLowerCase().contains('credit') ||
          d.field.toLowerCase().contains('credit'));
      if (isCredits) {
        return TamsCreditsException(error);
      }

      return TamsException(error);
    } catch (_) {
      return TamsException(TamsError(
        statusCode: statusCode,
        message: '$context: $statusCode $body',
      ));
    }
  }

  Future<bool> cancelJob(int jobId) async {
    final resp = await _client.post(
      Uri.parse('$_baseUrl/jobs/$jobId/cancel'),
      headers: _authHeaders,
    );
    return resp.statusCode == 200;
  }

  Future<Map<String, dynamic>?> getModelInfo(int modelId) async {
    final resp = await _client.get(
      Uri.parse('$_baseUrl/models/$modelId'),
      headers: _authHeaders,
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['model'] as Map<String, dynamic>?;
    }
    return null;
  }

  Future<Uint8List> downloadImage(String url) async {
    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      return resp.bodyBytes;
    }
    throw TamsException(TamsError(
      statusCode: resp.statusCode,
      message: 'Failed to download image: ${resp.statusCode}',
    ));
  }

  void dispose() {
    _client.close();
  }
}

class TamsJobResponse {
  final int id;
  final String status;
  final double credits;
  final TamsWaitingInfo? waitingInfo;
  final TamsFailedInfo? failedInfo;
  final TamsRunningInfo? runningInfo;
  final TamsSuccessInfo? successInfo;

  TamsJobResponse({
    required this.id,
    required this.status,
    required this.credits,
    this.waitingInfo,
    this.failedInfo,
    this.runningInfo,
    this.successInfo,
  });

  factory TamsJobResponse.fromJson(Map<String, dynamic> json) {
    final job = json['job'] as Map<String, dynamic>? ?? json;
    return TamsJobResponse(
      id: _asInt(job['id']),
      status: job['status'] as String? ?? 'DEFAULT',
      credits: _asDouble(job['credits']),
      waitingInfo: job['waitingInfo'] != null
          ? TamsWaitingInfo.fromJson(job['waitingInfo'] as Map<String, dynamic>)
          : null,
      failedInfo: job['failedInfo'] != null
          ? TamsFailedInfo.fromJson(job['failedInfo'] as Map<String, dynamic>)
          : null,
      runningInfo: job['runningInfo'] != null
          ? TamsRunningInfo.fromJson(job['runningInfo'] as Map<String, dynamic>)
          : null,
      successInfo: job['successInfo'] != null
          ? TamsSuccessInfo.fromJson(job['successInfo'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get isComplete => status == 'SUCCESS' || status == 'FAILED' || status == 'CANCELED';
  bool get isSuccess => status == 'SUCCESS';

}

class TamsWaitingInfo {
  final int queueRank;
  final int queueLen;

  TamsWaitingInfo({required this.queueRank, required this.queueLen});

  factory TamsWaitingInfo.fromJson(Map<String, dynamic> json) {
    return TamsWaitingInfo(
      queueRank: _asInt(json['queueRank']),
      queueLen: _asInt(json['queueLen']),
    );
  }
}

class TamsFailedInfo {
  final String reason;
  final String code;

  TamsFailedInfo({required this.reason, required this.code});

  factory TamsFailedInfo.fromJson(Map<String, dynamic> json) {
    return TamsFailedInfo(
      reason: json['reason'] as String? ?? 'Unknown error',
      code: json['code'] as String? ?? 'DEFAULT',
    );
  }
}

class TamsRunningInfo {
  final List<TamsProcessingImage> processingImages;
  final TamsWorkflowFinishItem? workflowFinishItem;

  TamsRunningInfo({this.processingImages = const [], this.workflowFinishItem});

  factory TamsRunningInfo.fromJson(Map<String, dynamic> json) {
    return TamsRunningInfo(
      processingImages: (json['processingImages'] as List<dynamic>?)
              ?.map((e) => TamsProcessingImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      workflowFinishItem: json['workflowFinishItem'] != null
          ? TamsWorkflowFinishItem.fromJson(json['workflowFinishItem'] as Map<String, dynamic>)
          : null,
    );
  }
}

class TamsProcessingImage {
  final String? url;
  final double progress;

  TamsProcessingImage({this.url, required this.progress});

  factory TamsProcessingImage.fromJson(Map<String, dynamic> json) {
    final resourceImage = json['resourceImage'] as Map<String, dynamic>?;
    return TamsProcessingImage(
      url: resourceImage?['url'] as String?,
      progress: _asDouble(json['progress']),
    );
  }
}

class TamsWorkflowFinishItem {
  final double progress;
  final int step;
  final String status;

  TamsWorkflowFinishItem({required this.progress, required this.step, required this.status});

  factory TamsWorkflowFinishItem.fromJson(Map<String, dynamic> json) {
    return TamsWorkflowFinishItem(
      progress: _asDouble(json['progress']),
      step: _asInt(json['step']),
      status: json['status'] as String? ?? 'DEFAULT',
    );
  }
}

class TamsSuccessInfo {
  final List<TamsOutputImage> images;
  final List<TamsOutputVideo> videos;

  TamsSuccessInfo({this.images = const [], this.videos = const []});

  factory TamsSuccessInfo.fromJson(Map<String, dynamic> json) {
    return TamsSuccessInfo(
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => TamsOutputImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      videos: (json['videos'] as List<dynamic>?)
              ?.map((e) => TamsOutputVideo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class TamsOutputImage {
  final String id;
  final String url;
  final int expiredIn;
  final int width;
  final int height;
  final String format;

  TamsOutputImage({
    required this.id,
    required this.url,
    required this.expiredIn,
    required this.width,
    required this.height,
    required this.format,
  });

  factory TamsOutputImage.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>?;
    final image = meta?['image'] as Map<String, dynamic>?;
    return TamsOutputImage(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      expiredIn: _asInt(json['expiredIn']),
      width: _asInt(image?['width']),
      height: _asInt(image?['height']),
      format: (image?['format'] as String?) ?? 'png',
    );
  }
}

class TamsOutputVideo {
  final String id;
  final String url;
  final int expiredIn;
  final int width;
  final int height;
  final String format;

  TamsOutputVideo({
    required this.id,
    required this.url,
    required this.expiredIn,
    required this.width,
    required this.height,
    required this.format,
  });

  factory TamsOutputVideo.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] as Map<String, dynamic>?;
    final image = meta?['image'] as Map<String, dynamic>?;
    return TamsOutputVideo(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      expiredIn: _asInt(json['expiredIn']),
      width: _asInt(image?['width']),
      height: _asInt(image?['height']),
      format: (image?['format'] as String?) ?? 'mp4',
    );
  }
}

class TamsError {
  final int statusCode;
  final int code;
  final String message;
  final List<TamsErrorDetail> details;

  TamsError({
    required this.statusCode,
    this.code = 0,
    this.message = '',
    this.details = const [],
  });
}

class TamsErrorDetail {
  final String field;
  final String message;

  TamsErrorDetail({required this.field, required this.message});
}

class TamsException implements Exception {
  final TamsError error;

  TamsException(this.error);

  String get message {
    final detailMsgs = error.details
        .map((d) => d.message)
        .where((m) => m.isNotEmpty)
        .toList();
    if (detailMsgs.isNotEmpty) return detailMsgs.join('; ');
    return error.message.isNotEmpty ? error.message : 'TAMS API error';
  }

  int get statusCode => error.statusCode;

  @override
  String toString() => 'TamsException($statusCode): $message';
}

class TamsCreditsException extends TamsException {
  TamsCreditsException(super.error);

  @override
  String get message {
    return 'Insufficient TAMS credits. '
        'Please top up at https://tams.tensor.art/app';
  }
}
