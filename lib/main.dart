// 1800多行还行 以后可能要拆出去多个文件

// ignore_for_file: non_constant_identifier_names, unused_element

import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as flutter_acrylic;
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';

const String keyAutoLogin = "auto_login";
const String keySavedEmail = "saved_email";
const String keySavedHashedPassword = "saved_hashed_password";
const String apiEndpoint = "https://https.ghs.wiki:7002/API?void=post";

class UserInfo {
  final String username;
  final String email;
  final String userID;
  final String gold;
  final String silver;
  final String qq;
  final bool hasSignedIn;

  UserInfo({
    required this.username,
    required this.email,
    required this.userID,
    required this.gold,
    required this.silver,
    required this.qq,
    required this.hasSignedIn,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    var info = json['userInfo'];
    return UserInfo(
      username: info['username'] ?? "未知",
      email: info['email'] ?? "未知",
      userID: info['userID'] ?? "0",
      gold: info['gold'].toString(),
      silver: info['silver'].toString(),
      qq: info['qq']?.toString() ?? "822585140",
      hasSignedIn: info['signIn'] ?? false,
    );
  }
}

class NodeInfo {
  final String id;
  final String name;
  final String address;
  final String status;
  final String load;
  final String cpu;
  final String mem;
  final String info;
  final bool online;
  final String upBand;
  final String downBand;
  final int price;
  final int bandMaxPer;

  NodeInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.status,
    required this.load,
    required this.cpu,
    required this.mem,
    required this.info,
    required this.online,
    required this.upBand,
    required this.downBand,
    required this.price,
    required this.bandMaxPer,
  });

  factory NodeInfo.fromJson(String id, Map<String, dynamic> json) {
    String decode(String? input) {
      if (input == null || input.isEmpty) return "暂无数据";
      try {
        return utf8.decode(input.runes.toList());
      } catch (_) {
        return input;
      }
    }

    final String decodedStatus = decode(json['status']);

    return NodeInfo(
      id: id,
      name: decode(json['name']),
      address: decode(json['address']),
      status: decodedStatus,
      load: json['load'] ?? "0.00%",
      cpu: decode(json['CPUUsage']),
      mem: decodedStatus.contains("在线") 
          ? "${json['memoryUsed']} / ${json['memoryTotal']}" 
          : "暂无数据",
      info: decode(json['info']),
      online: decodedStatus.contains("在线"),
      upBand: json['uploadBand'] ?? "0.00Mbps",
      downBand: json['downloadBand'] ?? "0.00Mbps",
      price: int.tryParse(json['price']?.toString() ?? "37") ?? 37,
      bandMaxPer: int.tryParse(json['band-max-per']?.toString() ?? "20") ?? 20,
    );
  }
}

class ProxyCode {
  final String node;
  final String number;
  final String code;
  final String stopTimestamp;
  final String port;
  final String band;
  final String status;
  bool isLocalRunning;

  ProxyCode({
    required this.node,
    required this.number,
    required this.code,
    required this.stopTimestamp,
    required this.port,
    required this.band,
    required this.status,
    this.isLocalRunning = false,
  });

  factory ProxyCode.fromJson(Map<String, dynamic> json) {
    return ProxyCode(
      node: json['node'] ?? "",
      number: json['number'] ?? "",
      code: json['code'] ?? "",
      stopTimestamp: json['stop'] ?? "0",
      port: json['port'] ?? "",
      band: json['band'] ?? "0",
      status: json['status'] ?? "stop",
    );
  }

  String get formattedExpiry {
    try {
      int ms = int.parse(stopTimestamp);
      var date = DateTime.fromMillisecondsSinceEpoch(ms);
      return "${date.year.toString().substring(2)}/${date.month.toString().padLeft(2,'0')}/${date.day.toString().padLeft(2,'0')} ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}";
    } catch (_) {
      return "未知";
    }
  }
}

void main() async {
  // 初始化
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await flutter_acrylic.Window.initialize();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1000, 750),
    center: true,
    title: "Mossfrp Windows GUI",
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setPreventClose(true); // 阻止直接关掉窗口
  });
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  //ThemeMode _themeMode = ThemeMode.system;
  bool _isLoggedIn = false;
  bool _isInitializing = true;
  String? _userToken;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  // token是会过期的！！！！！
  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(keyAutoLogin) ?? false) {
      String? email = prefs.getString(keySavedEmail);
      String? hashedPass = prefs.getString(keySavedHashedPassword);
      if (email != null && hashedPass != null) {
        String? token = await _attemptLoginApi(
          email,
          hashedPass,
          isAlreadyHashed: true,
        );
        if (token != null && mounted) {
          setState(() {
            _userToken = token;
            _isLoggedIn = true;
          });
        }
      }
    }
    if (mounted) setState(() => _isInitializing = false);
  }

  Future<String?> _attemptLoginApi(String email, String password,
      {bool isAlreadyHashed = false}) async {
    final String finalPassword = isAlreadyHashed
        ? password
        : sha256.convert(utf8.encode(password)).toString();
    try {
      final response = await http.post(
        Uri.parse(apiEndpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "type": "login",
          "loginType": "email",
          "account": email,
          "password": finalPassword,
          "encryption": "true"
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body)['token'];
    } catch (e) {
      debugPrint(e.toString());
    }
    return null;
  }

  

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyAutoLogin);
    await prefs.remove(keySavedHashedPassword);
    setState(() {
      _isLoggedIn = false;
      _userToken = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const String font = 'Microsoft YaHei UI'; 
    final baseTypography = Typography.raw(
      caption: const TextStyle(fontFamily: font, fontSize: 12),
      body: const TextStyle(fontFamily:font, fontSize: 14),
      subtitle: const TextStyle(fontFamily: font, fontSize: 18, fontWeight: FontWeight.w600),
      title: const TextStyle(fontFamily:font, fontSize: 28, fontWeight: FontWeight.bold),
    );
    if (_isInitializing) {
      return const FluentApp(
        home: ScaffoldPage(
          content: Center(child: ProgressRing()),
        ),
      );
    }

    return FluentApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
        fontFamily: font,
        visualDensity: VisualDensity.standard,
        typography: Typography.fromBrightness(
          brightness: Brightness.dark,
          color: Colors.white,
        ).merge(baseTypography),
        focusTheme: FocusThemeData(
          glowFactor: is10footScreen(context) ? 2.0 : 0.0,
        ),
      ),

      home: _isLoggedIn
          ? MainLayout(
              token: _userToken!, 
              onLogout: _logout,
            )
          : LoginPage(
              onLoginSuccess: (t) => setState(() {
                _userToken = t;
                _isLoggedIn = true;
              }),
              loginAction: _attemptLoginApi,
            ),
    );
  }
}

class LoginPage extends StatefulWidget {
  final Function(String) onLoginSuccess;
  final Future<String?> Function(String, String) loginAction;
  const LoginPage({
    super.key,
    required this.onLoginSuccess,
    required this.loginAction,
  });
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _pwdController = TextEditingController();
  bool _autoLogin = false;
  bool _isLoading = false;
  String _status = "";

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      content: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
           color: FluentTheme.of(context).cardColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            // border: Border.all(color: const Color(0xFFE5E5E5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Icon(FluentIcons.shield, size: 50, color: Colors.blue),
              ),
              const SizedBox(height: 15),
              const Center(
                child: Text(
                  "Mossfrp 登录",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 35),
              InfoLabel(
                label: "邮箱",
                child: TextBox(
                  controller: _emailController,
                  placeholder: "Email",
                ),
              ),
              const SizedBox(height: 20),
              InfoLabel(
                label: "密码",
                child: PasswordBox(
                  controller: _pwdController,
                  placeholder: "Password",
                ),
              ),
              const SizedBox(height: 15),
              Checkbox(
                checked: _autoLogin,
                onChanged: (v) => setState(() => _autoLogin = v ?? false),
                content: const Text("下次自动登录"),
              ),
              const SizedBox(height: 35),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: FilledButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          setState(() {
                            _isLoading = true;
                            _status = "验证中...";
                          });
                          String? token = await widget.loginAction(
                            _emailController.text,
                            _pwdController.text,
                          );
                          if (token != null) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool(keyAutoLogin, _autoLogin);
                            await prefs.setString(
                              keySavedEmail,
                              _emailController.text,
                            );
                            if (_autoLogin) {
                              await prefs.setString(
                                keySavedHashedPassword,
                                sha256
                                    .convert(utf8.encode(_pwdController.text))
                                    .toString(),
                              );
                            }
                            widget.onLoginSuccess(token);
                          } else {
                            if (mounted) {
                              setState(() {
                                _isLoading = false;
                                _status = "登录失败";
                              });
                            }
                          }
                        },
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: ProgressRing(),
                        )
                      : const Text("登录"),
                ),
              ),
              const SizedBox(height: 15),
              Center(
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _status == "登录失败"
                        ? Colors.red
                        : const Color(0xFF9E9E9E),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainLayout extends StatefulWidget {
  final String token;
  final VoidCallback onLogout;
  const MainLayout({
    super.key,
    required this.token,
    required this.onLogout,
  });
  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WindowListener {
  final ScrollController _horizontalScroll = ScrollController();
  final List<TextSpan> _logs = [];
  final _scroll = ScrollController();
  final _tunnelNameController = TextEditingController();
  final _localIpController = TextEditingController(text: '127.0.0.1');
  final _remoteInfoController = TextEditingController();
  final _localPortController = TextEditingController();
  final Map<String, Process> _runningProcesses = {}; 
  final Map<String, List<TextSpan>> _tunnelLogs = {};
  String? _selectedNodeId;
  int _idx = 0;
  int _createBand = 1;
  int _createDays = 3;
  Process? _process;
  UserInfo? _userInfo;
  ProxyCode? selectedCodeForTunnel;
  List<NodeInfo> _nodes = [];
  List<ProxyCode> _userCodes = [];
  bool _loadingNodes = true;
  bool _isLoading = false;
  bool _isCloseToTrayAlways = false;
  bool _hasSetCloseBehavior = false; 
  bool _isRunning = false;
  bool _loadingUser = true;

  @override
  void initState() {
    windowManager.removeListener(this);
    _loadSettings();
    super.initState();
    windowManager.addListener(this);
    Future.delayed(const Duration(milliseconds: 500), () {
      _initSystemTray();
    });
    _UserInfo(); 
    _fetchCtm();
    _UserCodes();
  }
  @override
  void dispose() {
    _horizontalScroll.dispose();
    _tunnelNameController.dispose();
    _localIpController.dispose();
    _localPortController.dispose();
    _remoteInfoController.dispose();
    super.dispose();
  }

  
  Future<void> _loadSettings() async {
    await SharedPreferences.getInstance();
  }

  Future<void> _UserInfo() async {
    try {
      final response = await http.post(
        Uri.parse(apiEndpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "type": "userInfo",
          "token": widget.token,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == "200" && mounted) {
          setState(() {
            _userInfo = UserInfo.fromJson(data);
            _loadingUser = false;
          });
        }
      }
    } catch (e) {
      debugPrint("获取用户信息失败: $e");
    }
  }

  void _showCreateTunnelDialog(BuildContext context, ProxyCode code) {
    _localPortController.clear();
    final TextEditingController remotePortController = TextEditingController();
    final String tunnelIdName = "code_${code.number}";

    int basePort = int.tryParse(code.port) ?? 0;
    int minRemote = basePort + 1;
    int maxRemote = basePort + 9;

    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('生成隧道配置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoLabel(label: '配置文件名', child: TextBox(controller: TextEditingController(text: tunnelIdName), readOnly: true, enabled: false)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: InfoLabel(label: '本地 IP', child: TextBox(controller: _localIpController))),
                const SizedBox(width: 8),
                Expanded(
                  child: InfoLabel(
                    label: '本地端口', 
                    child: TextBox(
                      controller: _localPortController,
                      placeholder: '如: 80',
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoLabel(
              label: '远程端口 (允许范围: $minRemote - $maxRemote)',
              child: TextBox(
                controller: remotePortController,
                placeholder: '请输入远程端口',
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ],
        ),
        actions: [
          Button(child: const Text('取消'), onPressed: () => Navigator.pop(context)),
          FilledButton(
            child: const Text('保存配置'),
            onPressed: () {
              final int? lp = int.tryParse(_localPortController.text);
              if (lp == null || lp < 1 || lp > 65535) {
                _showError("本地端口错误 (1-65535)");
                return;
              }
              final int? rp = int.tryParse(remotePortController.text);
              if (rp == null || rp < minRemote || rp > maxRemote) {
                _showError("远程端口超出范围！\n当前节点仅允许: $minRemote 到 $maxRemote");
                return;
              }
              Navigator.pop(context);
              _saveFRPConfig(code, tunnelIdName, remotePortController.text);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveFRPConfig(ProxyCode code, String fileName, String remotePort) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final tunnelDir = Directory(p.join(directory.path, 'tunnels'));
      if (!await tunnelDir.exists()) await tunnelDir.create(recursive: true);

      final configContent = """
[common]
server_addr = ${code.node}.mossfrp.cn
server_port = ${code.port}
token = ${code.code}
[$fileName]
type = tcp
local_ip = "${_localIpController.text}"
local_port = ${_localPortController.text}
remote_port = $remotePort
  """;

      final file = File(p.join(tunnelDir.path, '$fileName.ini'));
      await file.writeAsString(configContent);
      _log(">>>> [系统] 配置文件 $fileName.ini 已生成，远程端口: $remotePort", sys: true);
      
      await showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: const Text('保存成功'),
          content: Text('配置已保存，您可以点击开关启动穿透了。'),
          actions: [Button(child: const Text('确定'), onPressed: () => Navigator.pop(context))],
        ),
      );
    } catch (e) {
      _showError("写入配置失败: $e");
    }
  }
  
  Future<void> _UserCodes() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse(apiEndpoint),
        headers: {
          "Content-Type": "application/json",
          "Origin": "https://www.mossfrp.top",
          "Referer": "https://www.mossfrp.top/",
        },
        body: jsonEncode({
          "type": "userCode",
          "token": widget.token,
          "getAsList": true,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['status'] == "200") {
          final List<dynamic> rawCodes = data['codeData'] ?? [];
          setState(() {
            _userCodes = rawCodes.map((c) => ProxyCode.fromJson(c)).toList();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("获取穿透码失败: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCtm() async {
  if (!mounted) return;
  setState(() => _loadingNodes = true);
  try {
    final response = await http.post(
      Uri.parse(apiEndpoint),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "type": "allNode",
        "token": widget.token,
        "getAsList": false,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      
      if (data['status'] == "200") {
        final dynamic rawNodeData = data['nodeData'];
        List<NodeInfo> tempNodes = [];

        if (rawNodeData is Map) {
          tempNodes = rawNodeData.entries.map((e) {
            return NodeInfo.fromJson(e.key, e.value as Map<String, dynamic>);
          }).toList();
        }

        if (mounted) {
          setState(() {
            _nodes = tempNodes;
            _loadingNodes = false;
            if (_nodes.isNotEmpty && (_selectedNodeId == null || !_nodes.any((n) => n.id == _selectedNodeId))) {
              _selectedNodeId = _nodes.first.id;
            }
          });
        }
      }
    }
  } catch (e) {
    debugPrint("获取节点失败解析: $e");
    if (mounted) {
      setState(() {
        _loadingNodes = false;
      });
    }
  }
}

  Future<void> _SignIn() async {
    if (_userInfo?.hasSignedIn == true) return;

    try {
      final response = await http.post(
        Uri.parse(apiEndpoint),
        headers: {
          "Content-Type": "application/json",
          "Origin": "https://www.mossfrp.top",
          "Referer": "https://www.mossfrp.top/",
        },
        body: jsonEncode({
          "type": "signIn",
          "token": widget.token,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        String decodeSign(String input) {
          try {
            return utf8.decode(input.runes.toList());
          } catch (_) {
            return input;
          }
        }

        if (data['status'] == "200") {
          final String luckMsg = decodeSign(data['luckMessage'] ?? "");
          final String signMsg = decodeSign(data['signInMessage'] ?? "");
          final int luck = data['luck'] ?? 0;

          await showDialog(
            context: context,
            builder: (context) => ContentDialog(
              title: const Text('签到成功'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("今日人品值: $luck $luckMsg"),
                  const SizedBox(height: 10),
                  Text(signMsg.replaceAll("\r\n", " ")),
                ],
              ),
              actions: [
                FilledButton(
                  child: const Text('好的'),
                  onPressed: () {
                    Navigator.pop(context);
                    _UserInfo();
                  },
                ),
              ],
            ),
          );
        } else {
          displayInfoBar(
            context,
            builder: (c, b) => InfoBar(
              title: const Text("签到提示"),
              content: Text(data['message'] ?? "今日已签到过啦~"),
              severity: InfoBarSeverity.warning,
            ),
          );
          _UserInfo();
        }
      }
    } catch (e) {
      debugPrint("签到失败: $e");
    }
  }

  TextSpan _parseAnsi(String text) {
    final pattern = RegExp(r'\x1B\[([0-9;]*)m');
    List<TextSpan> spans = [];
    int lastMatchEnd = 0;
    Color currentColor = Colors.white;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: TextStyle(color: currentColor),
          ),
        );
      }
      String code = match.group(1) ?? "";
      if (code == "31") {
        currentColor = Colors.red;
      } else if (code == "32") {
        currentColor = Colors.green;
      } else if (code == "33") {
        currentColor = Colors.orange;
      } else if (code == "36") {
        currentColor = const Color(0xFF00FFFF);
      } else if (code == "0") {
        currentColor = Colors.white;
      }
      lastMatchEnd = match.end;
    }
    spans.add(
      TextSpan(
        text: text.substring(lastMatchEnd),
        style: TextStyle(color: currentColor),
      ),
    );
    return TextSpan(children: spans);
  }


  void _toggleFrpcProcess(ProxyCode code, bool shouldRun) async {
    final tunnelId = code.number;
    
    if (shouldRun) {
      if (_runningProcesses.containsKey(tunnelId)) return;

      final directory = await getApplicationSupportDirectory();
      final frpcLocalPath = p.join(directory.path, 'frpc.exe');
      final configPath = p.join(directory.path, 'tunnels', 'code_$tunnelId.ini');

      try {
        Process process = await Process.start(
          frpcLocalPath,
          ['-c', configPath],
          workingDirectory: directory.path,
        );

        _runningProcesses[tunnelId] = process;
        setState(() => code.isLocalRunning = true);
        process.stdout.transform(gbk.decoder).listen((data) => _appendToLog(tunnelId, data.trim()));
        process.stderr.transform(gbk.decoder).listen((data) => _appendToLog(tunnelId, data.trim(), isError: true));
        process.exitCode.then((_) {
          if (mounted) {
            setState(() {
              code.isLocalRunning = false;
              _runningProcesses.remove(tunnelId);
            });
          }
        });
      } catch (e) {
        _showError("启动失败: $e");
        setState(() => code.isLocalRunning = false);
      }
    } else {
      if (_runningProcesses.containsKey(tunnelId)) {
        final process = _runningProcesses[tunnelId];
        if (process != null) {
          final pid = process.pid;
          if (Platform.isWindows) {
            await Process.run('taskkill', ['/F', '/PID', pid.toString(), '/T']);
          } else {
            process.kill();
          }
        }
        _runningProcesses.remove(tunnelId);
      }
      setState(() => code.isLocalRunning = false);
    }
  }

  void _appendToLog(String id, String msg, {bool isError = false}) {
    setState(() {
      _tunnelLogs[id] ??= [];
      _tunnelLogs[id]!.add(TextSpan(
        text: "[${DateTime.now().toString().split(' ').last.substring(0,8)}] $msg\n",
        style: TextStyle(color: isError ? Colors.red : Colors.white, fontSize: 12),
      ));
      if (_tunnelLogs[id]!.length > 300) _tunnelLogs[id]!.removeAt(0);
    });
  }

  void _log(String t, {bool sys = false}) {
    setState(() {
      _logs.add(
        sys
            ? TextSpan(
                text: "$t\n",
                style: TextStyle(color: Colors.grey[100], fontSize: 13),
              )
            : TextSpan(
                children: [
                  _parseAnsi(t),
                  const TextSpan(text: "\n"),
                ],
              ),
      );
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    });
  }

  Future<void> _killProcess() async {
    if (_process != null) {
      _process!.kill();
      await Process.run('taskkill', ['/F', '/IM', 'frpc.exe', '/T']);
      _process = null;
    }
    if (mounted) setState(() => _isRunning = false);
    _log("服务已停止", sys: true);
  }

  Future<void> _CreateCtm() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse(apiEndpoint),
        headers: {
          "Content-Type": "application/json",
          "Origin": "https://www.mossfrp.top",
          "Referer": "https://www.mossfrp.top/",
        },
        body: jsonEncode({
          "type": "createCode",
          "token": widget.token,
          "node": _selectedNodeId ?? _nodes.first.id,
          "date": _createDays.toString(),
          "band": _createBand.toString(),
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['status'] == "200") {
          await showDialog(
            context: context,
            builder: (context) => ContentDialog(
              title: const Text('创建成功'),
              content: Text('已成功创建穿透码！\nID: ${data['ID']}\n消耗: ${data['coin']}'),
              actions: [
                FilledButton(
                  child: const Text('确认'),
                  onPressed: () {
                    Navigator.pop(context);
                    _UserInfo();
                  },
                ),
              ],
            ),
          );
        } else {
          _showError("创建失败: ${data['message'] ?? '余额不足或节点异常'}");
        }
      } else {
        _showError("服务器响应异常: ${response.statusCode}");
      }
    } catch (e) {
      _showError("网络请求出错: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initSystemTray() async {
    final SystemTray systemTray = SystemTray();
    try {
      String iconPath = Platform.isWindows 
        ? p.join(p.dirname(Platform.resolvedExecutable), 'data/flutter_assets/assets/app_icon.ico')
        : 'assets/app_icon.png';
      await systemTray.initSystemTray(
        title: "Mossfrp",
        iconPath: iconPath,
      );
      final Menu menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: '显示主界面', onClicked: (menuItem) => windowManager.show()),
        MenuItemLabel(
          label: '彻底退出', 
          onClicked: (menuItem) async {
            await _killAllFrpcProcesses();
            windowManager.destroy();
          },
        ),
      ]);
      await systemTray.setContextMenu(menu);
      systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          windowManager.show();
          windowManager.focus();
        } else if (eventName == kSystemTrayEventRightClick) {
          systemTray.popUpContextMenu();
        }
      });
    } catch (e) {
      debugPrint("系统托盘初始化失败了喵: $e");
    }
  }

  @override
  void onWindowClose() async {
    if (_hasSetCloseBehavior && _isCloseToTrayAlways) {
      windowManager.hide();
      return;
    }
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('真的要走了吗'),
        content: const Text('彻底退出程序并停止所有穿透吗？\n（可以选择最小化到托盘）'),
        actions: [
          Button(
            child: const Text('最小化到托盘'),
            onPressed: () {
              windowManager.hide();
              Navigator.pop(context);
            },
          ),
          FilledButton(
            child: const Text('离开'),
            onPressed: () async {
              await _killAllFrpcProcesses(); 
              windowManager.destroy(); 
            },
          ),
        ],
      ),
    );
  }

  Future<void> _killAllFrpcProcesses() async {
    _log(">>>> [系统] 正在清理本软件启动的穿透进程...", sys: true);
    final keys = _runningProcesses.keys.toList();
    for (var tunnelId in keys) {
      final process = _runningProcesses[tunnelId];
      if (process != null) {
        final pid = process.pid;
        if (Platform.isWindows) {
          await Process.run('taskkill', ['/F', '/PID', pid.toString(), '/T']);
        } else {
          process.kill();
        }
      }
    }
    
    _runningProcesses.clear();
  }

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      appBar: NavigationAppBar(
        title: const Text("Mossfrp"),
        automaticallyImplyLeading: false,
      ),
      pane: NavigationPane(
        selected: _idx,
        onChanged: (i) {
          setState(() {
            _idx = i;
          });
          if (i == 2) { 
            _UserCodes(); 
          }
        },
        displayMode: PaneDisplayMode.auto,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.contact),
            title: const Text("账户中心"),
            body: _buildUserPage(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.add_link),
            title: const Text("创建穿透码"),
            body: _buildCreateCodePage(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.list),
            title: const Text("我的穿透码"),
            body: _buildCodePage(),
          ),
          /*PaneItem(
            icon: const Icon(FluentIcons.home),
            title: const Text("运行状态"),
            body: _buildStatusPage(),
          ),*/
          PaneItem(
            icon: const Icon(FluentIcons.home),
            title: const Text("运行日志"), 
            body: _buildLogPage(),      
          ),
          PaneItem(
            icon: const Icon(FluentIcons.server_processes),
            title: const Text("节点列表"),
            body: _buildNodesPage(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text("软件设置"),
            body: _buildSettingsPage(),
          ),
        ],
        footerItems: [
          PaneItemAction(
            icon: const Icon(FluentIcons.power_button),
            title: const Text("退出登录"),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => ContentDialog(
                  title: const Text('确认退出登录？'),
                  content: const Text('退出登录将清除已经保存到电脑里的邮箱及密码'),
                  actions: [
                    Button(
                      child: const Text('取消'),
                      onPressed: () => Navigator.pop(context),
                    ),
                    FilledButton(
                      child: const Text('退出'),
                      onPressed: () {
                        Navigator.pop(context);
                        _killProcess();
                        widget.onLogout();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCodePage() {
    if (_isLoading) return const Center(child: ProgressRing());
    if (_userCodes.isEmpty) return const Center(child: Text("暂无数据，请刷新"));

    return LayoutBuilder(
      builder: (context, constraints) {
        double width = constraints.maxWidth;
        int count = width > 1200 ? 4 : (width > 900 ? 3 : (width > 600 ? 2 : 1));
        double itemWidth = (width - 32 - (count - 1) * 16) / count;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: _userCodes.map((code) => SizedBox(
              width: itemWidth,
              child: _buildCodeRow(code),
            )).toList(),
          ),
        );
      },
    );
  }

  Widget _buildNodesPage() {
    return ScaffoldPage.withPadding(
      header: PageHeader(
        title: const Text('节点列表'),
        commandBar: Button(
          child: const Icon(FluentIcons.refresh),
          onPressed: _fetchCtm,
        ),
      ),
      content: _loadingNodes
          ? const Center(child: ProgressRing())
          : ListView.builder(
              itemCount: _nodes.length,
              itemBuilder: (context, index) {
                final node = _nodes[index];
                double loadPercent = double.tryParse(
                        RegExp(r'(\d+\.?\d*)').firstMatch(node.load)?.group(1) ??
                            '0') ??
                    0.0;
                if (loadPercent > 100) loadPercent = 100;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Expander(
                    header: _buildExpanderHeader(node, loadPercent),
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildDetailColumn(
                              "实时带宽",
                              "↑ ${node.upBand}\n↓ ${node.downBand}",
                              FluentIcons.cloud_upload,
                            ),
                            _buildDetailColumn(
                              "累计流量",
                              "▲ 暂无数据\n▼ 暂无数据",
                              FluentIcons.speed_high,
                            ),
                            _buildDetailColumn(
                              "硬件占用",
                              "CPU: ${node.cpu}%\nMEM: ${node.mem}",
                              FluentIcons.iot,
                            ),
                          ],
                        ),
                        const Divider(
                          style: DividerThemeData(
                            verticalMargin: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        _buildInfoBox("节点详细信息", node.info),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildExpanderHeader(NodeInfo node, double loadPercent) {
    return Row(
      children: [
        InfoBadge(
          color: node.online ? Colors.green : Colors.red,
          source: const Text(''),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                node.address,
                style: TextStyle(color: Colors.grey[120], fontSize: 11),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProgressBar(
                  value: loadPercent,
                  backgroundColor: Colors.grey[40].withValues(alpha: 0.2),
                  activeColor: _getLoadColor(loadPercent),
                ),
                const SizedBox(height: 4),
                Text(
                  "${loadPercent.toStringAsFixed(2)}%",
                  style: TextStyle(
                    fontSize: 10,
                    color: _getLoadColor(loadPercent),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildStatusTag(node.online),
      ],
    );
  }

  Widget _buildDetailColumn(String title, String content, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.blue),
            const SizedBox(width: 5),
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          content,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, height: 1.5),
        ),
      ],
    );
  }
/*
  Widget _buildCreateTunnelPage() {
    if (_selectedCodeForTunnel == null) return const Center(child: Text("数据丢失，请返回重试"));
    final code = _selectedCodeForTunnel!;
    _remoteInfoController.text = "节点: ${code.node} | 端口: ${code.port}";

    return ScaffoldPage.withPadding(
      header: PageHeader(
        title: const Text('创建隧道配置'),
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: () => setState(() => _idx = 2),
        ),
      ),
      content: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InfoLabel(label: '隧道名称', child: TextBox(controller: _tunnelNameController)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: InfoLabel(label: '本地IP', child: TextBox(controller: _localIpController))),
                  const SizedBox(width: 10),
                  Expanded(child: InfoLabel(label: '本地端口', child: TextBox(controller: _localPortController))),
                ]),
                const SizedBox(height: 16),
                InfoLabel(label: '远程信息', child: TextBox(controller: _remoteInfoController, readOnly: true, enabled: false)),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: FilledButton(
                  onPressed: () => _showCreateTunnelDialog(context, code),
                  child: const Text('保存配置'),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
*/

  Widget _buildCodeRow(ProxyCode code) {
    int basePort = int.tryParse(code.port) ?? 0;
    String portRange = "${basePort + 1} - ${basePort + 9}";

    return Card(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildStatusBadge(_runningProcesses.containsKey(code.number)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  code.number,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ToggleSwitch(
                checked: _runningProcesses.containsKey(code.number),
                onChanged: (v) => _toggleFrpcProcess(code, v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildInfoBox("节点地址", code.node),
              _buildInfoBox("连接端口", code.port),
              _buildInfoBox("可用远程", portRange),
              _buildInfoBox("到期时间", code.formattedExpiry),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Button(
                  child: const Text('复制穿透码'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code.code));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  child: const Text('配置'),
                  onPressed: () => _showCreateTunnelDialog(context, code),
                ),
              ),
              const SizedBox(width: 8),
              Button(
                child: const Icon(FluentIcons.text_document_edit, size: 14),
                onPressed: () {
                  setState(() => _idx = 3);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(bool isRunning) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isRunning 
            ? Colors.green.withAlpha(25) 
            : Colors.red.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isRunning ? Colors.green : Colors.red,
          width: 0.5,
        ),
      ),
      child: Text(
        isRunning ? "正在运行" : "已停止",
        style: TextStyle(
          color: isRunning ? Colors.green : Colors.red,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoBox(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color.fromARGB(255, 151, 151, 151), fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

/*
  Widget _buildInfoItem(String label, String value) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[100], fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
*/

  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('提示'),
        content: Text(msg),
        actions: [Button(child: const Text('确定'), onPressed: () => Navigator.pop(context))],
      ),
    );
  }

  Widget _buildStatusTag(bool online) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: online
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        online ? "在线" : "离线",
        style: TextStyle(
          color: online ? Colors.green : Colors.red,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getLoadColor(double percent) {
    if (percent < 40) return Colors.green;
    if (percent < 80) return Colors.orange;
    return Colors.red;
  }

  Widget _buildUserPage() {
    if (_loadingUser) return const Center(child: ProgressRing());
    bool canSignIn = _userInfo?.hasSignedIn == false;

    return ScaffoldPage.withPadding(
      header: const PageHeader(title: Text('账户中心')),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.network(
                    "https://q2.qlogo.cn/headimg_dl?dst_uin=${_userInfo?.qq ?? '822585140'}&spec=100",
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, lp) => lp == null
                        ? child
                        : const SizedBox(
                            width: 60,
                            height: 60,
                            child: ProgressRing(strokeWidth: 3),
                          ),
                    errorBuilder: (context, error, stackTrace) =>
                        const CircleAvatar(
                      radius: 30,
                      child: Icon(FluentIcons.contact, size: 30),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userInfo?.username ?? "",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        "UID: ${_userInfo?.userID}",
                        style: TextStyle(color: Colors.grey[120], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: FilledButton(
                    onPressed: canSignIn ? _SignIn : null,
                    child: Row(
                      children: [
                        Icon(
                          canSignIn
                              ? FluentIcons.edit_contact
                              : FluentIcons.completed,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(canSignIn ? "每日签到" : "今日已签到"),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expander(
            initiallyExpanded: true,
            header: const Text("基本信息"),
            content: Column(
              children: [
                _infoRow("邮箱地址", _userInfo?.email ?? ""),
                const Divider(),
                _infoRow(
                  "我的金币",
                  "${_userInfo?.gold} Gold",
                  color: Colors.yellow,
                ),
                const Divider(),
                _infoRow(
                  "我的银币",
                  "${_userInfo?.silver} Silver",
                  color: Colors.grey[100],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildLogPage() {
    if (_tunnelLogs.isEmpty) {
      return const Center(child: Text("暂无运行日志，请先开启穿透隧道"));
    }

    return ScaffoldPage.withPadding(
      header: const PageHeader(title: Text("运行日志")),
      content: ListView(
        children: _tunnelLogs.keys.map((id) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Expander(
              header: Text("穿透码: $id", style: const TextStyle(fontWeight: FontWeight.bold)),
              content: Container(
                height: 300,
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: const Color(0xFF1E1E1E),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText.rich(
                    TextSpan(children: _tunnelLogs[id]!),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettingsPage() {
    return ScaffoldPage.scrollable(
      header: const PageHeader(title: Text('软件设置')),
      children: [
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('常规设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(
                title: const Text('点击关闭按钮时的行为'),
                subtitle: const Text('勾选后点击主窗口关闭按钮将直接最小化到系统托盘'),
                trailing: ToggleSwitch(
                  checked: _isCloseToTrayAlways,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('close_to_tray_always', v);
                    await prefs.setBool('has_set_close_behavior', v);
                    setState(() {
                      _isCloseToTrayAlways = v;
                      _hasSetCloseBehavior = v;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 以后再加点东西
      ],
    );
  }

  Widget _buildCreateCodePage() {
    if (_loadingNodes || _nodes.isEmpty) {
      return const Center(
        child: ProgressRing(),
      );
    }

    NodeInfo selectedNode = _nodes.firstWhere(
      (n) => n.id == _selectedNodeId,
      orElse: () => _nodes.first,
    );

    return ScaffoldPage.withPadding(
      header: const PageHeader(
        title: Text('创建穿透码'),
      ),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoLabel(
                  label: "选择节点",
                  child: ComboBox<String>(
                    value: _selectedNodeId ?? _nodes.first.id,
                    items: _nodes.map((node) {
                      return ComboBoxItem(
                        value: node.id,
                        child: Text(node.name),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedNodeId = v;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 20),

                InfoLabel(
                  label: "带宽 (Mbps) - 当前节点最高 ${selectedNode.bandMaxPer}Mbps",
                  child: NumberBox<int>(
                    value: _createBand,
                    min: 1,
                    max: selectedNode.bandMaxPer,
                    onChanged: (v) => setState(() => _createBand = v ?? 1),
                    mode: SpinButtonPlacementMode.inline,
                  ),
                ),
                const SizedBox(height: 20),

                InfoLabel(
                  label: "天数 (最短3天起步)",
                  child: NumberBox<int>(
                    value: _createDays,
                    min: 3,
                    onChanged: (v) => setState(() => _createDays = v ?? 3),
                    mode: SpinButtonPlacementMode.inline,
                  ),
                ),
                const SizedBox(height: 30),

                const Text(
                  "* 注意：官方节点禁止建站，违规将封禁账户。\n* 穿透码一旦创建，对应的金币/银币将立即扣除。",
                  style: TextStyle(
                    color: Color.fromARGB(255, 151, 151, 151),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 40),

          Expanded(
            flex: 2,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "订单详情",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildSummaryRow("节点", selectedNode.name),
                    _buildSummaryRow("单价", "${selectedNode.price}"),
                    _buildSummaryRow("带宽", "${_createBand} Mbps"),
                    _buildSummaryRow("天数", "${_createDays} 天"),
                    const Divider(
                      style: DividerThemeData(
                          verticalMargin: EdgeInsets.symmetric(vertical: 15)),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "预计消耗",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          "${selectedNode.price * _createBand * _createDays} 金币/银币",
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        child: const Text('确认创建'),
                        onPressed: () {
                          _CreateCtm(); 
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[120])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  



}