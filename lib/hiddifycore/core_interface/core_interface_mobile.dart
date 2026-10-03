import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/services.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/utils/laststeam.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/core_interface/mtls_channel_cred.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello_service.pbgrpc.dart';
import 'package:hiddify/singbox/model/core_status.dart';

import 'package:hiddify/utils/utils.dart';
import 'package:loggy/loggy.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final _logger = Loggy('FFIHiddifyCoreService');

class CoreInterfaceMobile extends CoreInterface with InfraLogger {
  static const channelPrefix = "com.hiddify.app";
  static const methodChannel = MethodChannel("$channelPrefix/method");
  static const statusChannel = EventChannel("$channelPrefix/service.status", JSONMethodCodec());
  static const alertsChannel = EventChannel("$channelPrefix/service.alerts", JSONMethodCodec());

  late Uint8List serverPublicKey;
  static final cert = CryptoUtils.generateEcKeyPair();

  static const portBack = 17079;
  static const portFront = 17078;

  bool _isBgClientAvailable = false;
  bool _debug = false;

  late LastStream<CoreStatus> _status;
  @override
  Future<String> setup(Directories directories, bool debug, int mode) async {
    final channelOption = [1, 2].contains(mode)
        ? MTLSChannelCredentials(serverPublicKey: serverPublicKey, clientKey: cert)
        : const ChannelCredentials.insecure();
    _debug = debug;
    final helloClient = HelloClient(
      ClientChannel(
        '127.0.0.1',
        port: portFront,
        options: ChannelOptions(credentials: channelOption),
      ),
    );
    final status = statusChannel.receiveBroadcastStream().map(CoreStatus.fromEvent);
    final alerts = alertsChannel.receiveBroadcastStream().map(CoreStatus.fromEvent);

    _status = LastStream(ValueConnectableStream(Rx.merge([status, alerts])).autoConnect());
    try {
      await helloClient.sayHello(HelloRequest(name: "test")).timeout(const Duration(seconds: 4));
      loggy.info("core is already started!");
    } catch (e) {
      //core is not started yet
      final sw = Stopwatch()..start();
      await methodChannel.invokeMethod("setup", {
        "baseDir": directories.baseDir.path,
        "workingDir": directories.workingDir.path,
        "tempDir": directories.tempDir.path,
        "grpcPort": portFront,
        "mode": mode,
        // forced true (diagnostic): params.Debug also gates hcore's
        // net/http/pprof server on localhost:6060 (grpc_server.go), which
        // is the only way to see what a hung (non-crashing) goroutine is
        // blocked on - see _fetchGoroutineDump below.
        "debug": true,
      });
      final invokeMs = sw.elapsedMilliseconds;
      // the first sayHello above already failed once (core wasn't up yet),
      // which can leave that ClientChannel in gRPC reconnect-backoff even
      // though the port is open now - use a fresh channel for the retry
      // instead of reusing the one that already failed.
      final retryHelloClient = HelloClient(
        ClientChannel(
          '127.0.0.1',
          port: portFront,
          options: ChannelOptions(credentials: channelOption),
        ),
      );
      try {
        final res = await retryHelloClient.sayHello(HelloRequest(name: "test")).timeout(const Duration(seconds: 30));
        loggy.info(res.toString());
      } catch (e, st) {
        final portOpen = await isPortOpen('127.0.0.1', portFront);
        // hcore's Setup() starts a net/http/pprof server on :6060 when
        // Debug=true (forced above). /debug/pprof/goroutine?debug=1 dumps
        // every live goroutine's stack, grouped by identical trace - this
        // is a hang (no crash), so it's the only channel that can show
        // what's actually blocked; a crash-only log (debug.SetCrashOutput)
        // would stay empty even if it worked.
        final goroutineDump = await _fetchGoroutineDump();
        unawaited(
          Sentry.captureException(
            e,
            stackTrace: st,
            withScope: (scope) => scope.setContexts("ios_core_setup", {
              "invokeMs": invokeMs,
              "totalMs": sw.elapsedMilliseconds,
              "portOpen": portOpen,
              "goroutineDump": goroutineDump,
            }),
          ),
        );
        // surfaced in the "failed to add profile" dialog so we can see it
        // from a screenshot without Sentry/Xcode.
        throw Exception("$e (invokeMs=$invokeMs, frontPortOpen=$portOpen)\n$goroutineDump");
      }
    }

    // serverPublicKey = await methodChannel.invokeMethod<Uint8List>("get_grpc_server_public_key") ?? Uint8List.fromList([]);
    // await methodChannel.invokeMethod(
    //   "add_grpc_client_public_key",
    //   {
    //     "clientPublicKey": ascii.encode(CryptoUtils.encodeEcPublicKeyToPem(cert.publicKey as ECPublicKey)),
    //   },
    // );
    // serverPublicKey = X509Utils.x509CertificateFromPem(String.fromCharCodes(serverPublicKey));
    // var chanelOption = ChannelOptions(
    //   credentials: MTLSChannelCredentials(serverPublicKey: serverPublicKey, clientPrivateKey: cert.privateKey as ECPrivateKey),
    // );
    fgClient = CoreClient(
      ClientChannel(
        '127.0.0.1',
        port: portFront,
        options: ChannelOptions(credentials: channelOption),
      ),
    );

    bgClient = CoreClient(
      ClientChannel(
        '127.0.0.1',
        port: portBack,
        options: ChannelOptions(credentials: channelOption),
      ),
    );
    // await start("/sdcard/Android/data/app.hiddify.com/files/configs/cdc633e9-8cfc-4a67-948d-009f779a5c91.json", "hiddify");
    return "";
  }

  @override
  Future<CoreStatus> setupBackground(String path, String name) async {
    // if (!await waitUntilPort(portBack, false, stop)) return const CoreStatus.stopped(alert: CoreAlert.createService);
    if (!await stop()) return const CoreStatus.stopped(alert: CoreAlert.createService);
    _status.clean();
    await methodChannel.invokeMethod("start", {
      "path": path,
      "name": name,
      "grpcPort": portBack,
      "startBg": true,
      "debug": _debug,
    });

    _isBgClientAvailable = true;
    loggy.info("Waiting for starting core");
    for (var i = 0; i < 20; i++) {
      try {
        final res = await _status.get(timeout: const Duration(seconds: 1));

        switch (res) {
          case CoreStarted():
            break;
          case CoreStopped():
            if (res.alert != null) {
              return res;
            }

          case CoreStopping():
          // return res;
          case CoreStarting():
        }
        await Future.delayed(const Duration(milliseconds: 200));
      } on TimeoutException {
        // just retry
      }
    }
    loggy.info("Waiting for starting core finished");

    if (!await waitUntilPort(portBack, true, null, maxTry: 10)) {
      await stopMethodChannel();
      return const CoreStatus.stopped(alert: CoreAlert.startService, message: "starting background core...");
    }
    return const CoreStarted();
  }

  @override
  Future<bool> stop() async {
    await stopMethodChannel();
    // iOS now awaits saveToPreferences() (disabling on-demand) before
    // stopVPNTunnel() to prevent the system auto-reconnecting - that round
    // trip can exceed the default 2s budget, so give iOS more room.
    if (!await waitUntilPort(portBack, false, null, maxTry: Platform.isIOS ? 25 : 10)) {
      return false;
    }

    _isBgClientAvailable = false;
    return true;
  }

  Future stopMethodChannel() async {
    await methodChannel.invokeMethod("stop");
  }

  @override
  Future<bool> isBgClientAvailable() async {
    return _isBgClientAvailable;
  }

  @override
  Future<bool> resetTunnel() async {
    await methodChannel.invokeMethod("reset");
    return true;
  }

  @override
  Future<bool> isActiveFg() async {
    return await isPortOpen("127.0.0.1", portFront);
  }

  @override
  Future<bool> isActiveBg() async {
    return await isPortOpen("127.0.0.1", portBack);
  }
}

Future<bool> waitUntilPort(
  int portNumber,
  bool isOpen,
  Future Function()? callFunctionAfterEachFail, {
  int maxTry = 10,
}) async {
  for (var i = 0; i < maxTry; i++) {
    if (await isPortOpen("127.0.0.1", portNumber) == isOpen) {
      return true;
    }
    if (callFunctionAfterEachFail != null) {
      await callFunctionAfterEachFail();
    }

    await Future.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

Future<String> _fetchGoroutineDump() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  // grpc_server.go binds with http.ListenAndServe("localhost:6060", nil), which
  // resolves "localhost" via DNS and listens on ONE address only - on iOS that
  // can come back IPv6-first (::1). A client hitting 127.0.0.1 explicitly then
  // gets a real "connection refused" even though the server is up. Try every
  // loopback form so a family mismatch doesn't look like "server never started".
  const hosts = ['127.0.0.1', '[::1]', 'localhost'];
  final errors = <String>[];
  try {
    for (final host in hosts) {
      try {
        final request = await client
            .getUrl(Uri.parse('http://$host:6060/debug/pprof/goroutine?debug=1'))
            .timeout(const Duration(seconds: 3));
        final response = await request.close().timeout(const Duration(seconds: 3));
        final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
        return body.length > 2500 ? "${body.substring(0, 2500)}\n...(truncated, ${body.length}b total)" : body;
      } catch (e) {
        errors.add('$host: $e');
      }
    }
    return "(failed to fetch goroutine dump: ${errors.join(' | ')})";
  } finally {
    client.close(force: true);
  }
}

Future<bool> isPortOpen(String host, int port, {Duration timeout = const Duration(milliseconds: 300)}) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    await socket.close();
    return true;
  } on SocketException catch (_) {
    return false;
  } catch (_) {
    return false;
  }
}
