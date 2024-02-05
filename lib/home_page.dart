import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_test_prj/local_notification.dart'; // local_notification 패키지 활용
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var messageTitle = "";
  var messageBody = "";
  String _responseText = '';

  Future<String> _getMyDeviceToken() async {
    // 디바이스 토큰 요청
    final token = await FirebaseMessaging.instance.getToken();

    print("=== 내 Device Token : $token");

    return token!;
  }

  Future<void> _postData() async {
    String data = await _getMyDeviceToken();
    const apiUrl = 'http://192.168.0.91:8080/endpoint.do';

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{'data': data}),
    );

    setState(() {
      if (response.statusCode == 200) {
        print('=== response : ${response.body}');
        _responseText = '=== Data sent successfully!';
      } else {
        _responseText = '=== Failed to send data';
      }
    });
  }

  final GlobalKey webViewKey = GlobalKey();

  // 인앱웹뷰 컨트롤러
  InAppWebViewController? webViewController;
  InAppWebViewSettings options = InAppWebViewSettings(
    useShouldOverrideUrlLoading: true,
    // URL 로딩 제어
    mediaPlaybackRequiresUserGesture: false,
    // 미디어 자동재생
    javaScriptEnabled: true,
    // js 실행여부
    javaScriptCanOpenWindowsAutomatically: true,
    // 팝업 여부
    useHybridComposition: true,
    // 하이브리드 사용을 위한 안드로이드 웹뷰 최적화
    supportMultipleWindows: true,
    // 멀티 윈도우 허용
    allowsInlineMediaPlayback: true, // 웹뷰 내 미디어 재생 허용
  );

  late PullToRefreshController pullToRefreshController; // 당겨서 새로고침 컨트롤러
  String url = "";
  double progress = 0;
  final urlController = TextEditingController();

  @override
  void initState() {
    _postData();

    // local_notification 초기화
    FlutterLocalNotification.init();

    // 2초 후 권한 요청
    Future.delayed(const Duration(seconds: 2),
        FlutterLocalNotification.requestNotificationPermission());

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.blue, // 새로고침 아이콘 색상
      ),
      // 플랫폼별 새로고침
      onRefresh: () async {
        if (Platform.isAndroid) {
          webViewController?.reload();
        } else if (Platform.isIOS) {
          webViewController?.loadUrl(
              urlRequest: URLRequest(url: await webViewController?.getUrl()));
        }
      },
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      RemoteNotification? notification = message.notification;

      if (notification != null) {
        setState(() {
          messageTitle = message.notification!.title!;
          messageBody = message.notification!.body!;

          print("=== Foreground FCM Title ==> $messageTitle");
          print("=== Foreground FCM Body  ==> $messageBody");

          // 푸시 알림 데이터에서 필요한 정보
          String title = message.notification?.title ?? 'Title';
          String body = message.notification?.body ?? 'Body';

          // push notification 생성 (foreground)
          FlutterLocalNotification.showNotification(title: title, body: body);
        });
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text(
            "e진로",
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: SafeArea(
            child: Column(children: <Widget>[
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
            ),
            controller: urlController,
            keyboardType: TextInputType.url,
            onSubmitted: (value) {
              var url = WebUri(value);
              if (url.scheme.isEmpty) {
                url = WebUri("https://www.google.com/search?q=$value");
              }
              webViewController?.loadUrl(urlRequest: URLRequest(url: url));
            },
          ),
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  key: webViewKey,
                  // 시작페이지
                  initialUrlRequest:
                      URLRequest(url: WebUri("http://192.168.0.91:8080")),
                  // 초기 설정
                  initialSettings: options,
                  // 당겨서 새로고침 컨트롤러 정의
                  pullToRefreshController: pullToRefreshController,
                  // 인앱웹뷰 생성 시 컨트롤러 정의
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                  },
                  // 페이지 로딩 시 수행 메서드 정의
                  onLoadStart: (controller, url) {
                    setState(() {
                      this.url = url.toString();
                      urlController.text = this.url;
                    });
                  },
                  // 안드로이드 웹뷰에서 권한 처리 메서드 정의
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.GRANT,
                    );
                  },
                  // URL 로딩 제어
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                    var uri = navigationAction.request.url!;

                    // 아래의 키워드가 포함되면 페이지 로딩
                    if (![
                      "http",
                      "https",
                      "file",
                      "chrome",
                      "data",
                      "javascript",
                      "about"
                    ].contains(uri.scheme)) {
                      if (await canLaunchUrl(Uri.parse(url))) {
                        // Launch the App
                        await launchUrl(
                          Uri.parse(url),
                        );
                        // and cancel the request
                        return NavigationActionPolicy.CANCEL;
                      }
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  // 페이지 로딩이 정지 시 메서드 정의
                  onLoadStop: (controller, url) async {
                    // 당겨서 새로고침 중단
                    pullToRefreshController.endRefreshing();
                    setState(() {
                      this.url = url.toString();
                      urlController.text = this.url;
                    });
                  },
                  // 페이지 로딩 중 오류 발생 시 메서드 정의
                  onReceivedError: (controller, request, error) {
                    pullToRefreshController?.endRefreshing();
                  },
                  // 로딩 상태 변경 시 메서드 정의
                  onProgressChanged: (controller, progress) {
                    // 로딩이 완료되면 당겨서 새로고침 중단
                    if (progress == 100) {
                      pullToRefreshController.endRefreshing();
                    }
                    // 현재 페이지 로딩 상태 업데이트(0~100%)
                    setState(() {
                      this.progress = progress / 100;
                      urlController.text = this.url;
                    });
                  },
                  onUpdateVisitedHistory: (controller, url, androidIsReload) {
                    setState(() {
                      this.url = url.toString();
                      urlController.text = this.url;
                    });
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    print(consoleMessage);
                  },
                ),
                progress < 1.0
                    ? LinearProgressIndicator(value: progress)
                    : Container(),
              ],
            ),
          ),
          ButtonBar(
            alignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  // backend 서버로 전송 및 안드로이드 앱 푸시 발송
                  _postData();
                },
                child: Icon(Icons.send),
              ),
            ],
          ),
        ])));
  }
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("=== Background FCM Title 처리 ==> ${message.notification!.title!}");
  print("=== Background FCM Body 처리 ==> ${message.notification!.body!}");

  // 푸시 알림 데이터에서 필요한 정보
  String title = message.notification?.title ?? 'Title';
  String body = message.notification?.body ?? 'Body';

  // push notification 생성 (background)
  FlutterLocalNotification.showNotification(title: title, body: body);
}
